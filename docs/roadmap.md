# Roadmap

Короткий план развития homelab. Файл нужен, чтобы отделить уже собранные части инфраструктуры от задач, которые еще нужно довести до нормального состояния.

## Done

- Собран k3s-кластер из control-plane-ноды и двух worker-нод.
- Настроен Proxmox VE host для виртуальных машин.
- Подняты Gitea и Woodpecker CI.
- Настроен локальный Docker Registry.
- Подключен ArgoCD для GitOps-доставки.
- Работает Traefik Ingress.
- Проверены CoreDNS и Kubernetes Service DNS.
- Поднят monitoring stack: Prometheus, Grafana, Loki, Alertmanager.
- Подключен OpenBao и Vault Agent Injector.
- Используются NFS persistent volumes.
- Поднят MinIO как S3-compatible storage.
- Настроен локальный DNS через AdGuard Home.
- Настроен удаленный доступ через VPS и FRP.

## Next

- Перенести DNS, DHCP и firewall на OpenWRT.
- Описать целевую схему сети.
- Удалить старые тестовые Kubernetes workloads.
- Проверить backup/restore на практике.
- Добавить Ansible для базовой настройки Linux-нод.
- Расширить GitOps-подход на большее число сервисов.

## Later

- Добавить отдельный документ по сети после настройки OpenWRT.
- Добавить restore runbook после первой успешной проверки восстановления.
- Добавить описание Ansible inventory и healthcheck playbook.
