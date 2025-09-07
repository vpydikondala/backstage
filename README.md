# Backstage AKS + ACR + GitOps PoC

## Goals
Deploy Backstage on AKS exposed via LoadBalancer public IP, using ACR for images, GitHub Actions for CI/CD, and Argo CD for GitOps.


## Prerequisites

- Azure subscription
- AKS + ACR permissions
- `az` CLI installed locally
- GitHub repo with Actions enabled


## Setup Steps

### 1. Azure Service Principal & ACR Credentials
Run locally:

az ad sp create-for-rbac --name sp-backstage --role contributor \
  --scopes /subscriptions/<SUB_ID>/resourceGroups/<RESOURCE_GROUP> \
  --sdk-auth
