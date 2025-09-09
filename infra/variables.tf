variable "resource_group_name" { type = string }
variable "location"            { type = string  default = "westeurope" }
variable "aks_cluster_name"    { type = string }
variable "dns_prefix"          { type = string  default = "backstageaks" }
variable "node_count"          { type = number  default = 2 }
variable "vm_size"             { type = string  default = "Standard_DS3_v2" }

variable "acr_name"            { type = string }                 # e.g. "myacr"
variable "backstage_image_tag" { type = string  default = "latest" }
variable "postgres_password"   { type = string  sensitive = true }
