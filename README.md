# 🛠️ Backstage IDP PoC on Minikube (with GitHub Actions + Argo CD)

This project sets up a local **Internal Developer Platform** using **Backstage**, deployed to **Minikube**, with **GitHub Actions** building service images and **Argo CD** handling GitOps deployments. It includes a **scaffolder template** that generates a FastAPI microservice with Dockerfile, Helm chart, TechDocs, a Backstage catalog entity, a GitHub Actions CI workflow, and an Argo CD `Application`.

## Repo Layout

backstage/ # project root
├── app-config.yaml # Backstage config (uses env vars for secrets)
├── k8s.yaml # Backstage Deployment/Service/Ingress/RBAC for Minikube
└── templates/
└── microservice-fastapi/
├── template.yaml # Backstage Scaffolder template
└── skeleton/ # What the template generates into a new repo
├── app/main.py # FastAPI app
├── Dockerfile
├── chart/ # Helm chart (Deployment/Service/Ingress)
├── environments/dev/argocd/application.yaml
├── catalog-info.yaml # Backstage entity
├── mkdocs.yml + docs/ # TechDocs
├── .github/workflows/ci.yaml # GitHub Actions CI (build/push GHCR)
└── README.md

##  Prerequisites

- **Docker** and **kubectl**
- **Minikube** (with the Docker driver recommended)
- **Helm**
- **GitHub account**
- (Optional) **Argo CD CLI** (`argocd`) for token creation

> You do **not** need Node/Yarn locally unless you plan to run Backstage in dev mode; we deploy Backstage as a container to Minikube.

## 1) Start Minikube + Ingress

minikube start --driver=docker
minikube addons enable ingress
2) Install PostgreSQL (Backstage DB)
kubectl create ns backstage
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install postgresql bitnami/postgresql -n backstage \
  --set auth.username=backstage,auth.password=changeme,auth.database=backstage
Use changeme for PoC; you’ll store this in a K8s Secret for Backstage.

3) Create a GitHub OAuth App (for Backstage sign-in)
GitHub → Settings → Developer settings → OAuth Apps → New OAuth App

Application name: Backstage IDP

Homepage URL: http://backstage.local

Authorization callback URL:
http://backstage.local/api/auth/github/handler/frame

Register → copy Client ID → Generate new client secret → copy Client Secret.

Create a Kubernetes Secret so Backstage can read these at runtime:

kubectl create secret generic github-oauth -n backstage \
  --from-literal=clientId=Iv1_xxxxxxxxxxxxx \
  --from-literal=clientSecret=xxxxxxxxxxxxxxxxxxxxxxxx
4) (Optional) Create a GitHub PAT for Scaffolder
If you want the Scaffolder to create repos and push code automatically, create a PAT with scopes:

repo, workflow, and (for GHCR) write:packages.

Store it in Kubernetes:

kubectl create secret generic github-pat -n backstage \
  --from-literal=token=ghp_xxxxxxxxxxxxxxxxxxxxx
If you skip this, the Scaffolder’s “Publish to GitHub” step will fail; you can still manually create repos.

5) (Optional) Create an Argo CD read-only token
If you want the Argo CD plugin in Backstage to display app health:

Install Argo CD:

kubectl create ns argocd
kubectl -n argocd apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server
Create a token (via UI or CLI). With the CLI:

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo

# Port-forward temporarily to login
kubectl -n argocd port-forward svc/argocd-server 8080:80
# In another terminal:
argocd login localhost:8080 --username admin --password <the-password> --insecure
argocd account generate-token --account admin
Store the token:

kubectl create secret generic argocd-token -n backstage \
  --from-literal=token=argo.xxxxxxxxxxxxxxxxx
You can skip this entire step if you don’t need the Argo CD plugin yet.

6) Pass secrets to Backstage via env vars
Your backstage/app-config.yaml uses environment variable substitution:

${GITHUB_CLIENT_ID}, ${GITHUB_CLIENT_SECRET}

${GITHUB_PERSONAL_ACCESS_TOKEN} (optional)

${BACKSTAGE_DB_PASSWORD}

${ARGOCD_TOKEN} (optional)

The provided backstage/k8s.yaml Deployment reads those from the K8s Secrets you created. If you need to adjust, edit the env section of the Deployment to match your Secret names/keys:

env:
  - name: GITHUB_CLIENT_ID
    valueFrom: { secretKeyRef: { name: github-oauth, key: clientId } }
  - name: GITHUB_CLIENT_SECRET
    valueFrom: { secretKeyRef: { name: github-oauth, key: clientSecret } }
  - name: GITHUB_PERSONAL_ACCESS_TOKEN
    valueFrom: { secretKeyRef: { name: github-pat, key: token } }            # optional
  - name: BACKSTAGE_DB_PASSWORD
    valueFrom: { secretKeyRef: { name: backstage-db, key: password } }
  - name: ARGOCD_TOKEN
    valueFrom: { secretKeyRef: { name: argocd-token, key: token } }          # optional
Create the DB secret to match:

kubectl create secret generic backstage-db -n backstage \
  --from-literal=password=changeme
7) Build the Backstage image in Minikube & deploy
Build against Minikube’s Docker daemon (so you don’t need a registry):

cd backstage
eval $(minikube -p minikube docker-env)
docker build -t backstage-poc:latest .
Apply the manifests:

kubectl apply -f k8s.yaml
kubectl -n backstage rollout status deploy/backstage
Add hosts entry for your machine:

minikube ip
Append this to your OS hosts file:

<MINIKUBE_IP> backstage.local
Windows: C:\Windows\System32\drivers\etc\hosts (editor as Administrator)

Linux/macOS: /etc/hosts

Open http://backstage.local and sign in with GitHub.

8) Register the Scaffolder Template
In Backstage:

Create → Register existing template, target:
file:./templates/microservice-fastapi/template.yaml
(Backstage container sees these files because they’re part of the image.)

Now you can Create → Microservice (FastAPI + Helm + Argo CD).

9) Generate a Microservice (end-to-end)
In Backstage, fill the form:

name: product-api-2

owner: team-product (or any Backstage Group)

system: core

namespace: default

host: product2.local

ghOrg: your GitHub username/org (e.g., vpydikondala)

Click Create:

A GitHub repo is created with Dockerfile, Helm chart, TechDocs, catalog entity, CI workflow.

The CI workflow builds/pushes to GHCR and bumps the chart image tag.

If your repo is private and your cluster must pull from GHCR, create a pull secret in the target namespace and reference it in the chart values:

kubectl create secret docker-registry ghcr-creds -n default \
  --docker-server=ghcr.io \
  --docker-username=<GITHUB_USER> \
  --docker-password=<PAT_with_write:packages>
Then set in chart/values.yaml of the generated repo:

imagePullSecrets:
  - name: ghcr-creds
10) Deploy via Argo CD
The generated repo contains environments/dev/argocd/application.yaml. For the PoC, you can apply it directly:

kubectl -n argocd apply -f environments/dev/argocd/application.yaml
Argo CD will sync the app into default namespace. Add a host entry for the service:

<MINIKUBE_IP> product2.local
Test:

curl -H "Host: product2.local" http://$(minikube ip)/
# or in a browser: http://product2.local/
Backstage → Catalog → your new component page:

Kubernetes tab shows Pods/Services

Argo CD card shows health/sync (if token configured)

Docs tab renders MkDocs (TechDocs local builder)

11) Troubleshooting
Can’t reach Backstage UI

kubectl -n backstage get pods

kubectl -n backstage logs deploy/backstage --tail=200

Confirm hosts entry for backstage.local points to minikube ip.

OAuth callback error

Check the OAuth App Authorization callback URL:
http://backstage.local/api/auth/github/handler/frame (exact path).

Scaffolder publish step fails

Ensure GITHUB_PERSONAL_ACCESS_TOKEN set and has repo + workflow scopes.

Argo CD card empty

Ensure ARGOCD_TOKEN present and argocd.baseUrl reachable (in-cluster address).

Service not responding

kubectl -n default get deploy,svc,ingress -l app=<service-name> -o wide

Pods ready? Ingress host mapped in hosts file?

12) Cleanup
Remove generated app:

kubectl -n argocd delete application product-api-2-app --ignore-not-found
kubectl -n default delete deploy,svc,ingress -l app=product-api-2 --ignore-not-found
Remove Backstage & DB:

kubectl delete ns backstage
Remove Argo CD:

kubectl delete ns argocd
Reset Minikube completely:

minikube delete
13) Notes on Secrets (how they’re referenced)
In app-config.yaml, secrets are referred to as ${ENV_VAR}:

${GITHUB_CLIENT_ID}, ${GITHUB_CLIENT_SECRET}

${GITHUB_PERSONAL_ACCESS_TOKEN}

${BACKSTAGE_DB_PASSWORD}

${ARGOCD_TOKEN}

In k8s.yaml, those env vars are wired from K8s Secrets (secretKeyRef).

You never commit raw secrets to Git.

14) What’s next?
Add more templates (Node/Spring) under templates/.

Introduce Sealed Secrets or External Secrets for production-grade secret handling.

Add Tech Insights/Scorecards for standards (docs, owners, CI checks).

Hook to Grafana/Prometheus for service-level dashboards.