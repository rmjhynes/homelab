# Homelab 🧪
My homelab config. This README is the map — start here when coming back after time away.

## Background
Having no experience managing a production grade Kubernetes platform, setting up a homelab is allowing me to get familiar with popular industry tools and experiment in a safe environment. I am using this as an opportunity to build something different to what I manage professionally so I can build new skills and become a more well-rounded engineer.

## Hardware
- Beelink S12 Mini Pro (16 GB RAM, 500GB SSD)

## OS
Fedora is my distro of choice for my homelab; it offers stability and ease of use out of the box, and being Red Hat-based makes it a great way to build familiarity with enterprise Linux environments. The machine configuration is managed with [Ansible](https://github.com/rmjhynes/ansible-homelab-setup).

## Cluster
For simplicity whilst I am starting out, the k3s cluster is made up of a single node. I will be looking to use a multi-node architecture when I am more confident.

## How it all works

Terraform bootstraps ArgoCD **once**; after that everything is GitOps — ArgoCD watches this repo and syncs the cluster to match it (including managing itself).

```
bootstrap.sh (once)                    every change after that
┌──────────────┐                       ┌──────────────────────────────┐
│  Terraform   │──deploys ArgoCD──▶   │  push to main                │
│              │──applies root app──▶ │    └─▶ ArgoCD auto-syncs     │
└──────────────┘                       │          └─▶ cluster updated │
                                       └──────────────────────────────┘
```

The **app of apps pattern**: the root Application ([bootstrap/applications.yaml](bootstrap/applications.yaml)) points at the `applications/` directory and recurses. Every `application.yaml` found there becomes a deployed app.

**Lifecycle of a change:** edit YAML → (optionally test on a local k3d cluster with [bootstrap/test_local.sh](bootstrap/TESTING.md)) → push to `main` → ArgoCD auto-syncs within a few minutes. No `kubectl apply` needed for anything ArgoCD manages.

## Repository map

| Directory | What it is |
|---|---|
| `bootstrap/` | One-time cluster bootstrap (Terraform + ArgoCD root app) and local k3d testing. See [BOOTSTRAP.md](bootstrap/BOOTSTRAP.md) / [TESTING.md](bootstrap/TESTING.md) |
| `applications/` | One ArgoCD `Application` per app — this directory *is* the list of what ArgoCD deploys |
| `manifests/` | Raw Kubernetes YAML for apps that don't use a Helm chart |
| `host-setup/` | Idempotent script for host-OS config the cluster depends on (DNS, firewalld, systemd service). See [README](host-setup/README.md) |
| `systemd-services/` | systemd units that run on the host, currently the [AdGuard DNS restore service](systemd-services/adguard-dns-restore/README.md) |
| `grafana-dashboards/` | Dashboard JSON exports |

## The `applications/` vs `manifests/` rule

Every app has an `Application` in `applications/<app>/`, but its *content* comes from one of two places:

- **Helm-based**: the `Application` references an external Helm chart, with custom values in `applications/<app>/values.yaml`. Nothing in `manifests/`.
- **Manifest-based**: the `Application` is just a pointer at `manifests/<app>/`, where the raw YAML lives.

So to find an app's config: check `applications/<app>/` first — either the values are right there (Helm), or it tells you it's deploying `manifests/<app>` (raw YAML).

## What's deployed

**Platform** (mostly Helm-based):

| Component | Deployed via | Purpose |
|---|---|---|
| [ArgoCD](applications/argocd/) | Helm | GitOps engine, manages everything including itself |
| [kube-prometheus-stack](applications/kube-prometheus-stack/) | Helm | Prometheus + Grafana monitoring |
| [Sealed Secrets](applications/sealed-secrets/) | Helm | Encrypt secrets so they can live in git |
| [Reloader](applications/reloader/) | Helm | Restart pods when their ConfigMaps/Secrets change |
| [Homepage](applications/homepage/) | Helm | Dashboard / landing page |
| [AdGuard Home](manifests/adguard/) | manifests | DNS for machine + cluster: ad blocking and `.homelab` rewrites. See its [README](manifests/adguard/README.md) |
| [Traefik config](manifests/traefik/) | manifests | Metrics config for the Traefik ingress built into k3s |
| [Ingress](manifests/ingress/) | manifests | `*.homelab` ingress routes |
| [Monitoring extras](manifests/monitoring/) | manifests | Golden signals Grafana dashboard |

**Apps**:

| App | Deployed via | Purpose |
|---|---|---|
| [FreshRSS](manifests/freshrss/) | manifests | Self-hosted RSS feed aggregator (with rclone backup CronJob) |
| [Excalidraw](manifests/excalidraw/) | manifests | Virtual whiteboard |
| [Ollama + Open WebUI](manifests/ollama/) | manifests | Local LLMs |
| [Wireshark](manifests/wireshark/) | manifests | Network traffic analysis |
| [linkding](manifests/linkding/) | ⚠️ manual | Self-hosted bookmark manager |
| [qBittorrent](manifests/qbittorrent/) | ⚠️ manual | Torrent client |
| [scratch-map](manifests/scratch-map/) | ⚠️ manual | Scratch-off style map to track my travels |
| [rclone secret](manifests/rclone/) | ⚠️ manual | Sealed secret for Google Drive backups |

> [!WARNING]
> Entries marked **manual** have manifests in this repo but **no ArgoCD Application** pointing at them — they were `kubectl apply`-ed by hand and ArgoCD will not sync changes to them. To bring one under GitOps, add an `applications/<app>/application.yaml` pointer (copy an existing manifest-based one, e.g. [excalidraw](applications/excalidraw/application.yaml)).

## Host-level config (not GitOps)

Some things live on the host OS and can't be managed by ArgoCD. The split:

- **[ansible-homelab-setup](https://github.com/rmjhynes/ansible-homelab-setup)** (separate repo): general machine provisioning.
- **This repo**: host config that exists *because of* the cluster — NetworkManager DNS pointing at AdGuard, firewalld rules for CNI interfaces, and the systemd service that restores AdGuard as DNS after reboots. All applied by one idempotent script: `sudo ./host-setup/setup.sh` ([docs](host-setup/README.md)).

## Docs index

- [bootstrap/BOOTSTRAP.md](bootstrap/BOOTSTRAP.md) — self-managed ArgoCD, why Terraform applies incrementally, bootstrap → GitOps handoff
- [bootstrap/TESTING.md](bootstrap/TESTING.md) — testing changes on a local k3d cluster before merging
- [manifests/adguard/README.md](manifests/adguard/README.md) — AdGuard setup, hostNetwork architecture, DNS policy
- [manifests/adguard/ISSUES.md](manifests/adguard/ISSUES.md) — fixes needed to get `.homelab` DNS rewrites working
- [host-setup/README.md](host-setup/README.md) — the idempotent host setup script
- [systemd-services/adguard-dns-restore/README.md](systemd-services/adguard-dns-restore/README.md) — why DNS needs restoring after every boot and how the service does it
