# Self-managed ArgoCD
In a declarative setup, ArgoCD should pull its own changes in from the Helm repo and update itself.

The App of apps pattern is used to define an app that points to this git repository to deploy _sub_ apps that point to Helm chart repositories (like kube-prometheus stack) to pull down and deploy the respective resources associated with the application.

`bootstrap.sh` boostraps the homelab by installing the [argocd helm chart](https://github.com/argoproj/argo-helm) and creating the main application that pulls everyhting down from this git repository.

## Improvements
Since there is an application that pulls down the ArgoCD helm chart in addition to the initial bootstrap install, there is currently 2 of each argocd resource. This is not ideal but works for now. In the future I will try to seperate them in different namespaces.
