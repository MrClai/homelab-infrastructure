# Roadmap

Короткий план развития homelab. Файл нужен, чтобы отделить уже собранные части инфраструктуры от задач, которые еще нужно довести до нормального состояния.

## Done

- Kubernetes cluster — собран k3s-кластер из control-plane-ноды и двух worker-нод.
- Virtualization — настроен Proxmox VE host для виртуальных машин.
- Git/CI flow — подняты Gitea, Woodpecker CI и локальный Docker Registry.
- GitOps — подключен ArgoCD для доставки Kubernetes workload.
- Ingress and DNS — настроены Traefik Ingress, CoreDNS и Kubernetes Service DNS.
- Monitoring — подняты Prometheus, Grafana, Loki и Alertmanager.
- Secrets — подключены OpenBao и Vault Agent Injector.
- Storage — используются NFS persistent volumes и MinIO.
- LAN DNS — настроен локальный DNS через AdGuard Home.
- Remote access — настроен доступ через VPS и FRP.
- Ansible automation — healthcheck playbook на всех нодах, service account ansible с отдельным SSH-ключом, ansible.cfg настроен.

## Next

- OpenWRT DNS/DHCP/Firewall — перенести сетевую логику в одну точку управления и описать зоны доступа.
- Network documentation — зафиксировать целевую схему сети, роли устройств и правила доступа.
- Backup/restore — проверить восстановление хотя бы одного сервиса, а не только наличие backup.
- GitOps expansion — перенести больше Kubernetes-конфигураций в ArgoCD.

## Later

- Добавить отдельный документ по сети после настройки OpenWRT.
- Добавить restore runbook после первой успешной проверки восстановления.
