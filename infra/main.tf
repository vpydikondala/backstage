############################
# Terraform + Providers
############################
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
  }
}

provider "azurerm" {
  features {}
}

############################
# Variables (set via tfvars or CI)
############################
variable "resource_group_name" { type = string }
variable "location"            { type = string  default = "westeurope" }
variable "aks_cluster_name"    { type = string }
variable "dns_prefix"          { type = string  default = "backstageaks" }
variable "node_count"          { type = number  default = 2 }
variable "vm_size"             { type = string  default = "Standard_DS3_v2" }
variable "acr_name"            { type = string }                   # e.g. "myacr"
variable "backstage_image_tag" { type = string  default = "latest" } # set by CI (commit SHA) or keep "latest"
variable "postgres_password"   { type = string  sensitive = true }   # choose a strong password

############################
# Resource Group, ACR, AKS
############################
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_cluster_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = var.dns_prefix

  default_node_pool {
    name                = "system"
    node_count          = var.node_count
    vm_size             = var.vm_size
    os_disk_size_gb     = 100
    type                = "VirtualMachineScaleSets"
    orchestrator_version = "1.29"
  }

  identity {
    type = "SystemAssigned"
  }

  # (optional) network profile settings if you need Azure CNI, etc.
  # network_profile {
  #   network_plugin = "kubenet"
  # }
}

# Allow AKS kubelet to pull from ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

############################
# Kubernetes + Helm providers (use AKS kubeconfig)
############################
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
  }
}

############################
# Ingress NGINX (Helm)
############################
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  # version        = "4.11.3" # pin if you prefer

  depends_on = [azurerm_kubernetes_cluster.aks]
}

# Read its public IP for DNS-less hostnames (nip.io)
data "kubernetes_service" "ingress_nginx_controller" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
  depends_on = [helm_release.ingress_nginx]
}

locals {
  ingress_ip     = try(data.kubernetes_service.ingress_nginx_controller.status[0].load_balancer[0].ingress[0].ip, "")
  backstage_host = "backstage.${local.ingress_ip}.nip.io"
  argocd_host    = "argocd.${local.ingress_ip}.nip.io"
}

############################
# Argo CD (behind same Ingress)
############################
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  # version        = "5.x.x"

  values = [
    yamlencode({
      server = {
        service = { type = "ClusterIP" }
        ingress = {
          enabled          = true
          ingressClassName = "nginx"
          hosts            = [ local.argocd_host ]
          paths            = [ "/" ]
          annotations      = { "kubernetes.io/ingress.class" = "nginx" }
          tls              = []
        }
      }
    })
  ]

  depends_on = [helm_release.ingress_nginx]
}

############################
# Backstage values (object -> yamlencode)
############################
locals {
  backstage_values = {
    containerPorts = { backend = 7007 }

    service = {
      type       = "ClusterIP"
      port       = 80
      targetPort = 7007
    }

    ingress = {
      enabled   = true
      className = "nginx"
      annotations = {
        "kubernetes.io/ingress.class" = "nginx"
      }
      hosts = [
        {
          host  = local.backstage_host
          paths = [
            { path = "/", pathType = "Prefix" }
          ]
        }
      ]
      tls = []
    }

    appConfig = {
      app = {
        title   = "Backstage on AKS"
        baseUrl = "http://${local.backstage_host}"
      }
      backend = {
        baseUrl = "http://${local.backstage_host}/api"
        listen  = { host = "0.0.0.0", port = 7007, basePath = "/api" }
        cors    = {
          origin      = "http://${local.backstage_host}"
          methods     = ["GET","HEAD","PATCH","POST","PUT","DELETE"]
          credentials = true
        }
      }
      database = {
        client     = "pg"
        connection = {
          host     = "backstage-postgresql"
          port     = 5432
          user     = "backstage"
          password = var.postgres_password
          database = "backstage"
        }
      }
    }

    backend = {
      image = {
        repository = "${var.acr_name}.azurecr.io/backstage"
        tag        = var.backstage_image_tag       # set by CI (commit SHA) or "latest"
        pullPolicy = "IfNotPresent"
      }
    }

    postgresql = {
      enabled = true
      auth = {
        username         = "backstage"
        password         = var.postgres_password
        postgresPassword = var.postgres_password
        database         = "backstage"
      }
    }

    # ServiceAccount so K8s plugin can be RBAC'ed later
    serviceAccount = { create = true, name = "backstage" }

    # Helpful env mirrors (optional)
    extraEnvVars = [
      { name = "APP_CONFIG_app_baseUrl",         value = "http://${local.backstage_host}" },
      { name = "APP_CONFIG_backend_baseUrl",     value = "http://${local.backstage_host}/api" },
      { name = "APP_CONFIG_backend_cors_origin", value = "http://${local.backstage_host}" }
    ]
  }
}

############################
# Backstage (Helm)
############################
resource "helm_release" "backstage" {
  name             = "backstage"
  repository       = "https://backstage.github.io/charts"
  chart            = "backstage"
  # version        = "1.x.x"
  namespace        = "backstage"
  create_namespace = true
  wait             = true

  values = [
    yamlencode(local.backstage_values)
  ]

  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_role_assignment.aks_acr_pull,
    helm_release.ingress_nginx
  ]
}

############################
# Outputs
############################
output "kubeconfig_raw" {
  value     = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive = true
  description = "Use with kubectl if needed"
}

output "acr_login_server" {
  value       = azurerm_container_registry.acr.login_server
  description = "ACR login server (for docker push/pull)"
}

output "backstage_url" {
  value       = "http://${local.backstage_host}"
  description = "Open Backstage here once apply completes"
}

output "argocd_url" {
  value       = "http://${local.argocd_host}"
  description = "Open Argo CD here once apply completes"
}
