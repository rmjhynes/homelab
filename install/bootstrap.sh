# Create namespace
kubectl create ns argocd

# Install Helm chart
helm install argocd argo/argo-cd --namespace argocd

# Apply Argo Helm AppProject resource
kubectl apply -f project.yaml
# Apply Argo Helm Application resource
kubectl apply -f applications.yaml
