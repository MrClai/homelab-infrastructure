# Homelab Infrastructure

Домашняя инфраструктура для практики Linux, Kubernetes, сетей, GitOps, мониторинга и self-hosted сервисов.

Это не production-кластер и не попытка изобразить enterprise на коленке. Это живой homelab на реальном железе, где я разбираю, как связаны сервисы, как идет трафик, как работает DNS, где появляются точки отказа и что нужно улучшать.

## Что внутри

- k3s-кластер из control-plane-ноды и двух worker-нод;
- Proxmox VE host для виртуальных машин;
- Terraform для управления VM в Proxmox (IaC);
- Ansible для проверки состояния нод (control node + inventory);
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
- AdGuard Home для локального DNS;
- FRP через VPS для удаленного доступа.

## Основная идея

Инфраструктура собирается вокруг простого flow:

```
Git -> CI -> Registry -> ArgoCD -> Kubernetes
                         |
                         +-> OpenBao / secrets
```

Git хранит желаемое состояние, CI собирает контейнерные образы, Registry хранит образы, ArgoCD синхронизирует Kubernetes, а OpenBao используется для работы с секретами.

VM в Proxmox описаны через Terraform, базовая проверка состояния нод — через Ansible.

## Документы

| Файл | Что внутри |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Как связаны основные компоненты |
| [docs/operations.md](docs/operations.md) | Что проверять при эксплуатации |
| [docs/decisions.md](docs/decisions.md) | Почему выбраны эти решения |
| [docs/roadmap.md](docs/roadmap.md) | Что уже сделано и что планируется дальше |
| [terraform/](terraform/) | Terraform-код для VM в Proxmox |
| [ansible/README.md](ansible/README.md) | Ansible control node, inventory, текущее состояние |

## Текущее состояние

Рабочая часть инфраструктуры уже собрана: Kubernetes, GitOps, мониторинг, локальный DNS, NFS storage, MinIO, OpenBao и удаленный доступ через FRP. VM в Proxmox описаны через Terraform.

При этом проект еще требует уборки и доработки:

- перенести DNS/DHCP/Firewall на OpenWRT;
- описать и проверить backup/restore;
- написать первый Ansible playbook (сейчас готовы control node и inventory);
- привести GitOps к более полному состоянию.

## Ограничения

- Один control-plane в k3s не дает отказоустойчивости control-plane.
- NFS является важной точкой отказа для stateful workload.
- Backup без проверенного restore пока не считается завершенным.
- Часть сервисов настроена вручную и должна быть перенесена в управляемый вид.

## Зачем этот репозиторий

Репозиторий нужен не для хранения секретов или полной приватной конфигурации. Его задача — показать архитектуру, принятые решения, текущие ограничения и план улучшений homelab-инфраструктуры.
