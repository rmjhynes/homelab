# Homelab 🧪
My homelab config.

## Background
Having no experience managing a production grade Kubernetes platform, setting up a homelab is allowing me to get familiar with popular industry tools and experiment in a safe environment. I am using this as an opportunity to build something different to what I manage professionally so I can build new skills and become a more well-rounded engineer.

## Hardware
- Beelink S12 Mini Pro (16 GB RAM, 500GB SSD)

## OS
For ease of reproducability and decalarative configuration, NixOS is my distro of choice for my homelab. The actual configuration can be found in my [nixos-config](https://github.com/rmjhynes/nixos-config) repo.

## Infrastructure / Tools
- k3s - A lightweight k8s distribution for container orchestration.
- ArgoCD - A continuous delivery tool following declarative, GitOps principles.
- Prometheus / Grafana - For cluster monitoring and visualisation.

## Cluster
For simplicity whilst I am starting out, the cluster is made up of a single node. I will be looking to use a multi-node architecture when I am more confident.
