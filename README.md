# Homelab Infrastructure

Домашняя инфраструктура для практики Linux, Kubernetes, сетей, GitOps, мониторинга и self-hosted сервисов.

Это не production-кластер и не попытка изобразить enterprise на коленке. Это живой homelab на реальном железе, где я разбираю, как связаны сервисы, как идёт трафик, как работает DNS, где появляются точки отказа и что нужно улучшать.

## Что внутри

- k3s-кластер из control-plane-ноды и двух worker-нод;
- Proxmox VE host для виртуальных машин;
- Terraform для управления VM в Proxmox (IaC);
- шаблон Windows Server 2025 с Cloudbase-Init (учебная проверка guest customization);
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
| [docs/decisions.md](docs/decisions.md) | Почему выбраны эти решения (12 ADR) |
| [docs/operations.md](docs/operations.md) | Что проверять при эксплуатации |
| [docs/ops/k3s-upgrade.md](docs/ops/k3s-upgrade.md) | Апгрейд k3s-кластера 1.32 → 1.35 |
| [docs/ops/woodpecker-upgrade.md](docs/ops/woodpecker-upgrade.md) | Мажорное обновление Woodpecker CI 2.8.3 → 3.18.1: миграция БД, права volume, инструкция для следующих обновлений |
| [docs/land-delivery.md](docs/land-delivery.md) | Архитектура доставки land: конфигурация, зависимости, выпуск версии и откат |
| [examples/land/](examples/land/README.md) | Dockerfile, Woodpecker pipeline и Kubernetes-манифесты land |
| [docs/ops/land-gitops-delivery.md](docs/ops/land-gitops-delivery.md) | Доставка land через Woodpecker и ArgoCD: сборка образа, диагностика DNS/LVM, неудачный rollout и возврат через Git |
| [docs/ops/minio-tls-internal-ca.md](docs/ops/minio-tls-internal-ca.md) | Internal CA и TLS для MinIO: openssl, раздача доверия, инциденты |
| [docs/ops/registry-tls-auth.md](docs/ops/registry-tls-auth.md) | TLS и htpasswd для Docker Registry, переход на docker-compose |
| [docs/ops/ansible-ssh-auth-incident.md](docs/ops/ansible-ssh-auth-incident.md) | Инцидент: SSH-аутентификация Ansible под `ansible` не применялась |
| [docs/ops/infrastructure-change-validation.md](docs/ops/infrastructure-change-validation.md) | Порядок проверки изменений Terraform, Ansible и Kubernetes |
| [docs/ops/security-baseline.md](docs/ops/security-baseline.md) | Применённые настройки безопасности и отложенные hardening-задачи |
| [docs/roadmap.md](docs/roadmap.md) | Что уже сделано и что планируется дальше |
| [docs/runbook-restore.md](docs/runbook-restore.md) | Пошаговая инструкция по восстановлению backups |
| [terraform/](terraform/) | Terraform-код для VM в Proxmox |
| [ansible/README.md](ansible/README.md) | Ansible control node, inventory, playbooks |
| [scripts/README.md](scripts/README.md) | Backup-скрипты для OpenBao и MinIO |

## Лабораторные эксперименты

Проверки идей вне основной инфраструктуры: результат и границы описаны, но в рабочий flow они не встроены.

| Файл | Что внутри |
|---|---|
| [docs/labs/windows-proxmox-template.md](docs/labs/windows-proxmox-template.md) | Windows Server 2025 шаблон для Proxmox: Cloudbase-Init, Sysprep, ConfigDrive2; пробный клон получает hostname, DHCP и пароль из Proxmox. Журнал, 4 инцидента, инструкция для повторения |

## Текущее состояние

Основная часть инфраструктуры собрана и работает: Kubernetes, GitOps, мониторинг, сеть через GL-MT6000, NFS storage, MinIO, OpenBao, Ansible и удалённый доступ через FRP. VM в Proxmox описаны через Terraform. Архитектурные решения задокументированы как ADR. Internal CA и TLS для MinIO, TLS и auth для Docker Registry — закрыты. Backup для OpenBao и MinIO реализован, restore проверен в изолированном окружении; runbook также описывает процедуру для реального отказа, но она пока не прогонялась на практике.

## Открытые задачи

- автоматизация offsite-копирования backup;
- firewall zones.

## Ограничения

- Один control-plane в k3s не даёт отказоустойчивости control-plane.
- NFS является точкой отказа для stateful workload.
- Backup реализован для OpenBao и MinIO, restore проверен в изолированном окружении; процедура для реального отказа задокументирована в runbook, но не проверена на практике; offsite-копия пока не автоматизирована.

## Зачем этот репозиторий

Репозиторий нужен не для хранения секретов или полной приватной конфигурации. Его задача — показать архитектуру, принятые решения, текущие ограничения и план улучшений homelab-инфраструктуры.
