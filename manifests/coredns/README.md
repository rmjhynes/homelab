# WIP
## Approach to DNS Configuration
- Previously, I had been forwarding any requests to my local domains to
Traefik in the CoreDNS corefile (inside `coredns-configmap.yaml`). I haven't
worked out how to persist this configuration between machine restarts with
ArgoCD (as CoreDNS comes with k3s) and was applying this manifest manually.
- I am now wanting to use [Pi-hole](https://pi-hole.net/) and have changed my
approach to forward all DNS queries to Pi-hole via CoreDNS. I have created
`coredns-pihole-configmap.yaml` to achieve this.

## Next Steps
- Figure out how to use Pi-hole as the standard cluster DNS or apply CoreDNS
config declaratively via ArgoCD.
