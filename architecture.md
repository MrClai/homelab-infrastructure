# Architecture

Краткое описание того, как устроен homelab и как связаны основные компоненты.

## Hardware Layer

Инфраструктура построена на нескольких физических узлах:

- Raspberry Pi 5 — k3s control-plane и часть локальных сервисов;
- Digma PRO #1 — Proxmox VE host;
- Digma PRO #2 — k3s worker;
- VPS — внешняя точка для удаленного доступа через FRP;
- OpenWRT gateway — планируется для DNS, DHCP, firewall и VPN gateway.

## Kubernetes Layer

k3s используется как легкий Kubernetes-кластер для homelab.

Основные компоненты:

- CoreDNS — DNS внутри Kubernetes;
- Traefik — Ingress controller;
- ArgoCD — GitOps-доставка;
- Prometheus / Grafana / Loki / Alertmanager — мониторинг и логи;
- Vault Agent Injector — доставка секретов из OpenBao в workloads;
- NFS StorageClass — persistent volumes для stateful workload.

## Delivery Flow

```text
Developer
  -> Gitea
  -> Woodpecker CI
  -> Docker Registry
  -> ArgoCD
  -> k3s workloads
```

OpenBao подключается отдельно как источник секретов для приложений.

## DNS And Access

В инфраструктуре есть два уровня DNS:

- LAN DNS — локальные имена для доступа из домашней сети;
- Kubernetes Service DNS — имена сервисов внутри кластера.

Удаленный доступ реализован через FRP и VPS, потому что домашняя сеть находится за NAT.

## Storage

Используются несколько типов хранения:

- NFS для Kubernetes persistent volumes;
- MinIO как S3-compatible storage;
- локальный Docker Registry для контейнерных образов.

## Что еще нужно уточнить

- целевая схема сети после перехода на OpenWRT;
- какие сервисы должны быть доступны только из LAN;
- какие сервисы должны иметь удаленный доступ;
- какие данные нужно бэкапить в первую очередь.
