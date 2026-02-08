# Homelab 🧪
My homelab config.

## Background
Having no experience managing a production grade Kubernetes platform, setting up a homelab is allowing me to get familiar with popular industry tools and experiment in a safe environment. I am using this as an opportunity to build something different to what I manage professionally so I can build new skills and become a more well-rounded engineer.

## Hardware
- Beelink S12 Mini Pro (16 GB RAM, 500GB SSD)

## OS
Fedora is my distro of choice for my homelab; it offers stability and ease of use out of the box, and being Red Hat-based makes it a great way to build familiarity with enterprise Linux environments. The machine configuration is managed with [Ansible](https://github.com/rmjhynes/ansible-homelab-setup).

## Cluster
For simplicity whilst I am starting out, the k3s cluster is made up of a single node. I will be looking to use a multi-node architecture when I am more confident.

## Infrastructure / Tools
- k3s - A lightweight k8s distribution for container orchestration.
- ArgoCD - A continuous delivery tool following declarative, GitOps principles.
- Prometheus / Grafana - For cluster monitoring and visualisation.
- AdGuard Home - DNS server for both the physical machine and the cluster, providing ad blocking and local DNS rewrites (`.homelab` domains).
- Sealed Secrets - Encrypt kubernetes secret manifests allowing them to be securely pushed to version control.
- rclone - A command-line program to sync files and directories to and from different cloud storage providers.

## Applications
- [freshrss](https://github.com/FreshRSS/FreshRSS) - A self-hosted RSS feed aggregator.
- [excalidraw](https://github.com/excalidraw/excalidraw) - A virtual whiteboard.
- [linkding](https://github.com/sissbruecker/linkding) - A self-hosted bookmark manager.
- [scratch-map](https://github.com/ad3m3r5/scratch-map) - A scratch-off style map to track my travels.
