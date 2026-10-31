# Homelab 🧪
My homelab config.

## Table of contents

- [Getting started](#getting-started)
- [Usage once cluster is provisioned](#usage-once-cluster-is-provisioned)
- [Background](#background)
- [Hardware](#hardware)
- [Cluster](#cluster)
- [How it all works](#how-it-all-works)
- [Repository map](#repository-map)
- [What's deployed to the cluster](#whats-deployed-to-the-cluster)
  - [Platform](#platform)
  - [Applications](#applications)
- [Host-level config (not GitOps)](#host-level-config-not-gitops)
- [Docs index](#docs-index)

## Getting started
1. [General homelab machine setup](https://github.com/rmjhynes/ansible-homelab-setup)
2. [Cluster-related host setup](host-setup/README.md)
3. [Cluster bootstrap](bootstrap/BOOTSTRAP.md)

## Usage once cluster is provisioned

Access ArgoCD UI to check cluster applications sync status one of two ways:

- Port forward to the service with `kubectl -n argocd port-forward svc/argocd-server 8080:80` and go to `http://localhost:8080` in a browser.
- Go to `http://argocd.homelab` in a browser.

ArgoCD login details:
```sh
# Username
admin
# Retrieve password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Links to all other apps can be found on the homepage dashboard: `http://home.homelab`.

## Background
Having no experience managing a production grade Kubernetes platform, setting up a homelab is allowing me to get familiar with popular industry tools and experiment in a safe environment. I am using this as an opportunity to build something different to what I manage professionally so I can build new skills and become a more well-rounded engineer.

## Hardware
- Beelink S12 Mini Pro (16 GB RAM, 500GB SSD)

## Cluster
For simplicity whilst I am starting out, the k3s cluster is made up of a single node. I will be looking to use a multi-node architecture when I am more confident.

## How it all works

Terraform bootstraps ArgoCD **once**; after that everything is GitOps - ArgoCD watches this repo and syncs the cluster to match it (including managing itself).

```
bootstrap.sh (once)                    every change after that
┌──────────────┐                       ┌──────────────────────────────┐
│  Terraform   │──deploys ArgoCD──>    │  push to main                │
│              │──applies root app──>  │    └─>  ArgoCD auto-syncs    │
└──────────────┘                       │          └─>  cluster updated│
                                       └──────────────────────────────┘
```

The **app of apps pattern**: the [root Application](bootstrap/applications.yaml) points at the `applications/` directory and recurses. Every `application.yaml` file in this directory is deployed in the cluster as an app.

**Lifecycle of a change:** edit YAML --> (optionally test on a local k3d cluster with [bootstrap/test_local.sh](bootstrap/TESTING.md)) --> merge to `main` --> ArgoCD auto-syncs within a few minutes and no `kubectl apply` needed for anything ArgoCD manages.

## Repository map

| Directory | Description |
|---|---|
| `bootstrap/` | Initial cluster bootstrap of the ArgoCD root app using Terraform, and local k3d testing. See [BOOTSTRAP.md](bootstrap/BOOTSTRAP.md) / [TESTING.md](bootstrap/TESTING.md). |
| `applications/` | One ArgoCD `Application` per app - this directory is the list of what ArgoCD deploys to the cluster |
| `manifests/` | Raw Kubernetes YAML for apps that don't use a Helm chart |
| `host-setup/` | Idempotent script for host-OS config the cluster depends on (DNS, firewalld, systemd service). See [README](host-setup/README.md). |
| `systemd-services/` | systemd units that run on the host, currently the [AdGuard DNS restore service](systemd-services/adguard-dns-restore/README.md). This is setup by [host-setup/setup.sh](host-setup/setup.sh). |
| `grafana-dashboards/` | JSON exports of Grafana dashboards |

## What's deployed to the cluster

### Platform

| Component | Deployed via | Purpose |
|---|---|---|
| [ArgoCD](applications/argocd/) | Helm | Declarative continuous delivery tool for k8s which manages cluster apps, including itself |
| [kube-prometheus-stack](applications/kube-prometheus-stack/) | Helm | Prometheus and Grafana monitoring |
| [Sealed Secrets](applications/sealed-secrets/) | Helm | Encrypt secrets so they can live in git |
| [Reloader](applications/reloader/) | Helm | Restart pods when their ConfigMaps/Secrets change |
| [Homepage](applications/homepage/) | Helm | Dashboard / landing page |
| [AdGuard Home](manifests/adguard/) | manifests | DNS for machine and cluster: ad blocking and `.homelab` rewrites|
| [Traefik config](manifests/traefik/) | manifests | Metrics config for the Traefik ingress built into k3s |
| [Ingress](manifests/ingress/) | manifests | `*.homelab` ingress routes |
| [Monitoring extras](manifests/monitoring/) | manifests | Grafana dashboard resources|

### Applications

| App | Deployed via | Purpose |
|---|---|---|
| [FreshRSS](manifests/freshrss/) | manifests | Self-hosted RSS feed aggregator (with rclone backup CronJob) |
| [Excalidraw](manifests/excalidraw/) | manifests | Virtual whiteboard |
| [Ollama + Open WebUI](manifests/ollama/) | manifests | Local LLMs |
| [Wireshark](manifests/wireshark/) | manifests | Network traffic analysis |
| [linkding](manifests/linkding/) | manual `kubectl apply` | Self-hosted bookmark manager |
| [qBittorrent](manifests/qbittorrent/) | manual `kubectl apply` | Torrent client |
| [scratch-map](manifests/scratch-map/) | manual `kubectl apply` | Scratch-off style map to track my travels |
| [rclone secret](manifests/rclone/) | manual `kubectl apply` | Sealed secret for Google Drive backups |

## Host-level config (not GitOps)

Fedora is my distro of choice for my homelab; it offers stability and ease of use out of the box, and being Red Hat-based makes it a great way to build familiarity with enterprise Linux environments.

Some things are configured on the host OS and can't be managed by ArgoCD:

- **[ansible-homelab-setup](https://github.com/rmjhynes/ansible-homelab-setup)** - general homelab machine configuration.
- **This repo:** cluster-related host config - see [host-setup/README.md](host-setup/README.md).

## Docs index

- [bootstrap/BOOTSTRAP.md](bootstrap/BOOTSTRAP.md) - self-managed ArgoCD, why Terraform applies incrementally, bootstrap → GitOps handoff
- [bootstrap/TESTING.md](bootstrap/TESTING.md) - testing changes on a local k3d cluster before merging
- [manifests/adguard/README.md](manifests/adguard/README.md) - AdGuard setup, hostNetwork architecture, DNS policy
- [manifests/adguard/ISSUES.md](manifests/adguard/ISSUES.md) - fixes needed to get `.homelab` DNS rewrites working
- [host-setup/README.md](host-setup/README.md) - the idempotent host setup script
- [systemd-services/adguard-dns-restore/README.md](systemd-services/adguard-dns-restore/README.md) - why DNS needs restoring after every boot and how the service does it
