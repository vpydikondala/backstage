location            = "uksouth"
resource_group_name = "rg-backstage"
aks_cluster_name    = "aks-backstage"
node_count          = 2
vm_size             = "Standard_D2s_v5"
acr_name            = "backstageacrpoc12345"  # Replace with your unique ACR name
dns_prefix          = "backstageaks"
postgres_password   = "ChangeMe_SuperStrong!"
backstage_image_tag = "latest"   # or set to your commit SHA tag from CI

