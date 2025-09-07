variable "location" {
  description = "Azure region"
  type        = string
  default     = "uksouth"
}

variable "resource_group_name" {
  description = "Resource group for AKS"
  type        = string
  default     = "rg-backstage"
}

variable "aks_cluster_name" {
  description = "AKS cluster name"
  type        = string
  default     = "aks-backstage"
}

variable "node_count" {
  description = "Number of AKS worker nodes"
  type        = number
  default     = 2
}

variable "vm_size" {
  description = "Size of AKS VMs"
  type        = string
  default     = "Standard_DS2_v2"
}

variable "acr_name" {
  description = "Azure Container Registry name (must be globally unique)"
  type        = string
}
