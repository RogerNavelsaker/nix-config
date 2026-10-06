# Nanoserver + Miniservers cluster baseline

Flux bootstraps from the public `nix-config` repository and reconciles this directory. The first baseline creates only `platform-system`; application workloads and Kubernetes Secrets are intentionally absent.

The bootstrap API/join address is `miniserver-01.local:6443` (Avahi). The three mini servers provide embedded-etcd quorum, but this hostname is still a single API endpoint. Use a later reserved LAN VIP/load balancer before claiming API endpoint HA.

Host join credentials live in the separate SOPS-encrypted `nix-secrets` repository and are mounted through `sops-nix`; no plaintext token or private age key belongs in this repository. Flux SOPS decryption is not enabled until a Kubernetes-side age identity is provisioned for actual encrypted workload Secrets.
