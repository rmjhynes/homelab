# A script to delete clusterrole resources whenever I blowup my ArgoCD apps

# Force delete namesapce stuck in terminating
(
NAMESPACE=argocd
kubectl proxy &
kubectl get namespace $NAMESPACE -o json |jq '.spec = {"finalizers":[]}' >temp.json
curl -k -H "Content-Type: application/json" -X PUT --data-binary @temp.json 127.0.0.1:8001/api/v1/namespaces/$NAMESPACE/finalize
)

# Delete Argo clusterrole resources
kubectl delete clusterrole argocd-server
kubectl delete clusterrole argocd-notifications-controller
kubectl delete clusterrole argocd-application-controller
kubectl delete clusterrolebinding argocd-notifications-controller
kubectl delete clusterrolebinding argocd-application-controller
kubectl delete clusterrolebinding argocd-server

# Delete Kube-prom-stack clusterrole resources
kubectl delete clusterrole kube-prometheus-stack-admission
kubectl delete clusterrole kube-prometheus-stack-grafana-clusterrole
kubectl delete clusterrole kube-prometheus-stack-kube-state-metrics
kubectl delete clusterrole kube-prometheus-stack-operator
kubectl delete clusterrole kube-prometheus-stack-prometheus
kubectl delete clusterrole prometheus-grafana-clusterrole
kubectl delete clusterrole prometheus-kube-prometheus-operator
kubectl delete clusterrole prometheus-kube-prometheus-prometheus
kubectl delete clusterrole prometheus-kube-state-metrics
kubectl delete clusterrolebinding kube-prometheus-stack-admission
kubectl delete clusterrolebinding kube-prometheus-stack-grafana-clusterrolebinding
kubectl delete clusterrolebinding kube-prometheus-stack-kube-state-metrics
kubectl delete clusterrolebinding kube-prometheus-stack-operator
kubectl delete clusterrolebinding kube-prometheus-stack-prometheus
kubectl delete clusterrolebinding prometheus-grafana-clusterrolebinding
kubectl delete clusterrolebinding prometheus-kube-prometheus-operator
kubectl delete clusterrolebinding prometheus-kube-prometheus-prometheus
kubectl delete clusterrolebinding prometheus-kube-state-metrics
