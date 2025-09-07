provider "azurerm" {
  features {}
}

# --------------------------
# Resource Group
# --------------------------
resource "azurerm_resource_group" "rg" {
  name     = "rg-backstage"
  location = var.location
}

# --------------------------
# Azure Kubernetes Service
# --------------------------
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-backstage"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  default_node_pool {
    name       = "agentpool"
    node_count = var.node_count
    vm_size    = var.vm_size
  }

  identity {
    type = "SystemAssigned"
  }
}

# --------------------------
# ACR (optional - for image pushing)
# --------------------------
resource "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

# --------------------------
# Output kubeconfig
# --------------------------
output "kubeconfig" {
  value     = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive = true
}

# --------------------------
# Helm & Kubernetes Providers
# --------------------------
provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  }
}

# --------------------------
# Kubernetes Provider
# --------------------------
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

# --------------------------
# Argo CD Installation
# --------------------------
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "5.0.0"

  depends_on = [
    azurerm_kubernetes_cluster.aks
  ]
}

resource "kubernetes_service" "argocd_server" {
  metadata {
    name      = "argocd-server"
    namespace = "argocd"
    labels = {
      app.kubernetes.io/name = "argocd-server"
    }
  }

  spec {
    type = "LoadBalancer"

    selector = {
      app.kubernetes.io/name = "argocd-server"
    }

    port {
      port        = 443
      target_port = 8080
      protocol    = "TCP"
    }
  }
}

# --------------------------
# Backstage Installation
# --------------------------
resource "helm_release" "backstage" {
  name       = "backstage"
  chart      = "backstage"
  repository = "https://backstage.github.io/charts"
  namespace  = "backstage"
  version    = "1.0.0"
  create_namespace = true

  values = [
    file("${path.module}/../helm-chart/values.yaml")
  ]
    depends_on = [
    azurerm_kubernetes_cluster.aks
  ]
}
