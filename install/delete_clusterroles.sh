# A script to delete clusterrole resources whenever I blowup my ArgoCD apps

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
