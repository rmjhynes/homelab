# Create namespace for argo resources
kubectl create ns argocd

# Add Argo Helm repo
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Install Helm chart
helm install argocd argo/argo-cd --namespace argocd

# Apply Argo Helm AppProject resource
kubectl apply -f project.yaml
# Apply Argo Helm Application resource
kubectl apply -f applications.yaml
