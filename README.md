# Homelab Infrastructure

Домашняя инфраструктура для практики Linux, Kubernetes, сетей, GitOps, мониторинга и self-hosted сервисов.

Это не production-кластер и не попытка изобразить enterprise на коленке. Это живой homelab на реальном железе, где я разбираю, как связаны сервисы, как идёт трафик, как работает DNS, где появляются точки отказа и что нужно улучшать.

## Что внутри

- k3s-кластер из control-plane-ноды и двух worker-нод;
- Proxmox VE host для виртуальных машин;
- Terraform для управления VM в Proxmox (IaC);
- Ansible для автоматизации Linux-нод (control node, inventory, playbooks);
- Gitea как self-hosted Git;
- Woodpecker CI для pipeline;
- локальный Docker Registry;
- ArgoCD для GitOps-доставки в Kubernetes;
- Traefik Ingress;
- CoreDNS и Kubernetes Service DNS;
- Prometheus, Grafana, Loki и Alertmanager;
- OpenBao и Vault Agent Injector;
- NFS persistent volumes;
- MinIO как S3-compatible storage;
- GL-MT6000 как основной роутер — DHCP, DNS, Firewall;
- FRP через VPS для удалённого доступа.

## Основная идея

Инфраструктура собирается вокруг простого flow:

```
Gitea -> Woodpecker CI -> Registry -> ArgoCD -> Kubernetes
                                        |
                                        +-> OpenBao / secrets
```

Git хранит желаемое состояние, CI собирает контейнерные образы, Registry хранит образы, ArgoCD синхронизирует Kubernetes, а OpenBao используется для работы с секретами.

VM в Proxmox описаны через Terraform, базовая автоматизация Linux-нод — через Ansible.

## Документы

| Файл | Что внутри |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Как связаны основные компоненты |
| [docs/decisions.md](docs/decisions.md) | Почему выбраны эти решения |
| [docs/operations.md](docs/operations.md) | Что проверять при эксплуатации |
| [docs/roadmap.md](docs/roadmap.md) | Что уже сделано и что планируется дальше |
| [terraform/](terraform/) | Terraform-код для VM в Proxmox |
| [ansible/README.md](ansible/README.md) | Ansible control node, inventory, playbooks |

## Текущее состояние

Основная часть инфраструктуры собрана и работает: Kubernetes, GitOps, мониторинг, сеть через GL-MT6000, NFS storage, MinIO, OpenBao, Ansible и удалённый доступ через FRP. VM в Proxmox описаны через Terraform.

Открытые задачи:

- backup/restore — проверить восстановление хотя бы одного сервиса;
- monitoring debt — Loki isDefault постоянный фикс через Git;
- secrets — Alertmanager SMTP через OpenBao Injector;
- security — firewall rules, Registry auth/TLS.

## Ограничения

- Один control-plane в k3s не даёт отказоустойчивости control-plane.
- NFS является точкой отказа для stateful workload — нужен проверенный backup/restore.
- Backup без проверенного restore не считается завершённым.

## Зачем этот репозиторий

Репозиторий нужен не для хранения секретов или полной приватной конфигурации. Его задача — показать архитектуру, принятые решения, текущие ограничения и план улучшений homelab-инфраструктуры.
