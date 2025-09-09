############################
# Terraform + Providers
############################
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm   = { source = "hashicorp/azurerm",   version = "~> 3.116" }
    kubernetes= { source = "hashicorp/kubernetes",version = "~> 2.31" }
    helm      = { source = "hashicorp/helm",      version = "~> 2.13" }
  }
}

provider "azurerm" {
  features {}
}

############################
# Azure resources: RG, ACR, AKS
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

# Discover latest stable AKS version for the location (no preview)
data "azurerm_kubernetes_service_versions" "stable" {
  location        = var.location
  include_preview = false
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_cluster_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = var.dns_prefix

  # Set cluster version to latest stable for the region
  kubernetes_version = data.azurerm_kubernetes_service_versions.stable.latest_version

  default_node_pool {
    name            = "system"
    node_count      = var.node_count
    vm_size         = var.vm_size
    os_disk_size_gb = 100
    # NOTE: DO NOT set orchestrator_version here — that caused the downgrade error.
    type            = "VirtualMachineScaleSets"
  }

  identity {
    type = "SystemAssigned"
  }
}

# Allow AKS kubelet to pull from ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

############################
# Kubernetes + Helm Providers (use AKS kubeconfig)
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

  depends_on = [azurerm_kubernetes_cluster.aks]
}

# Read its external IP (for nip.io hostnames)
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

  values = [
    yamlencode({
      server = {
        service = { type = "ClusterIP" }
        ingress = {
          enabled          = true
          ingressClassName = "nginx"
          hosts            = [ local.argocd_host ]    # Argo CD expects an array
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
# Backstage values (OBJECT -> yamlencode)
# Matches Backstage chart schema
############################
locals {
  backstage_values = {
    containerPorts = { backend = 7007 }

    service = {
      type  = "ClusterIP"
      ports = {
        backend = 7007
      }
    }

    ingress = {
      enabled    = true
      className  = "nginx"
      annotations= { "kubernetes.io/ingress.class" = "nginx" }
      host       = local.backstage_host
      tls        = { enabled = false, secretName = "" }
    }

    appConfig = {
      app = {
        title   = "Backstage on AKS"
        baseUrl = "http://${local.backstage_host}"
      }
      backend = {
        baseUrl = "http://${local.backstage_host}"
        listen  = { host = "0.0.0.0", port = 7007 }
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

    image = {
      repository = "${var.acr_name}.azurecr.io/backstage"
      tag        = var.backstage_image_tag
      pullPolicy = "IfNotPresent"
    }

    postgresql = {
      enabled = true
      auth    = {
        username         = "backstage"
        password         = var.postgres_password
        postgresPassword = var.postgres_password
        database         = "backstage"
      }
    }

    serviceAccount = { create = true, name = "backstage" }

    extraEnvVars = [
      { name = "APP_CONFIG_app_baseUrl",     value = "http://${local.backstage_host}" },
      { name = "APP_CONFIG_backend_baseUrl", value = "http://${local.backstage_host}" }
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
  namespace        = "backstage"
  create_namespace = true
  wait             = true

  values = [ yamlencode(local.backstage_values) ]

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
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
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
