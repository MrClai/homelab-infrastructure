# Architecture

Краткое описание того, как устроен homelab и как связаны основные компоненты.

![Homelab architecture](homelab_diagram_v3.png)

## Hardware Layer

Инфраструктура построена на нескольких физических узлах:

- Raspberry Pi 5 — k3s control-plane, NFS, MinIO, Docker Registry;
- Digma PRO #1 — Proxmox VE host, VM101–VM105;
- Digma PRO #2 — k3s worker;
- GL-MT6000 — основной роутер, DHCP, DNS, Firewall;
- VPS (Germany) — внешняя точка для удалённого доступа через FRP.

## VM Layer (Proxmox)

Все VM созданы и управляются через Terraform:

| VM | Назначение | RAM | IP |
|----|-----------|-----|----|
| VM101 | k3s worker | 4GB | 192.168.1.21 |
| VM102 | Gitea | 2GB | 192.168.1.40 |
| VM103 | Woodpecker CI | 2GB | 192.168.1.50 |
| VM104 | OpenBao | 2GB | 192.168.1.60 |
| VM105 | Ansible control node | 1GB | 192.168.1.80 |

## Kubernetes Layer

k3s используется как лёгкий Kubernetes-кластер.

- master: Raspberry Pi 5
- workers: VM101, Digma PRO #2
- CoreDNS — DNS внутри кластера
- Traefik — Ingress controller
- ArgoCD — GitOps-доставка
- Prometheus / Grafana / Loki / Alertmanager — мониторинг и логи
- Vault Agent Injector — доставка секретов из OpenBao в workloads
- NFS StorageClass — persistent volumes для stateful workloads

Ingress endpoints:

- `argocd.homelab.local`
- `grafana.homelab.local`

## Delivery Flow

```
Gitea → Woodpecker CI → Docker Registry (:5000) → ArgoCD → k3s
```

OpenBao (VM104) подключается отдельно как источник секретов — Vault Agent Injector внутри k3s забирает секреты и монтирует их в поды.

## Secrets

OpenBao — self-hosted Vault-совместимый secrets manager. Стоит вне k3s на VM104. Workloads получают секреты через Vault Agent Injector (mutating webhook).

Grafana adminPassword — через Injector. Секреты в Git не хранятся.

## Storage

- NFS на Pi5 — Kubernetes PersistentVolumes
- MinIO на Pi5 — S3-compatible storage, используется как Terraform state backend
- Docker Registry на Pi5 (:5000) — локальный registry для контейнерных образов

## Remote Access

Домашняя сеть за NAT. Удалённый доступ через FRP tunnel: frpc на Pi5 подключается к frps на VPS в Германии.
