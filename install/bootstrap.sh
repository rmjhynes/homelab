# Create namespaces
kubectl create ns argocd
kubectl create ns monitoring

# Install Helm charts
helm install argocd argo/argo-cd --namespace argocd
helm install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring

# Apply Argo Helm AppProject resource
kubectl apply -f project.yaml
# Apply Argo Helm Application resource
kubectl apply -f applications.yaml
