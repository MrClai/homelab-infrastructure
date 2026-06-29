# Roadmap

Короткий план развития homelab. Файл нужен, чтобы отделить уже собранные части инфраструктуры от задач, которые ещё нужно довести до нормального состояния.

## Done

- Kubernetes cluster — собран k3s-кластер из control-plane-ноды и двух worker-нод.
- Virtualization — настроен Proxmox VE host для виртуальных машин (VM101–VM105).
- IaC — все VM созданы и управляются через Terraform, state в MinIO.
- Git/CI flow — подняты Gitea, Woodpecker CI и локальный Docker Registry.
- GitOps — подключен ArgoCD для доставки Kubernetes workload.
- Ingress and DNS — настроены Traefik Ingress, CoreDNS и Kubernetes Service DNS.
- Monitoring — подняты Prometheus, Grafana, Loki и Alertmanager.
- Secrets — подключены OpenBao и Vault Agent Injector; Grafana получает пароль через Injector.
- Storage — используются NFS persistent volumes и MinIO.
- Network — GL-MT6000 настроен как основной роутер, DHCP, DNS и firewall.
- Remote access — настроен доступ через VPS и FRP.
- Ansible — control node на VM105, healthcheck playbook, create-ansible-user, update-linux.
- Kubernetes cleanup — тестовые workloads и namespace удалены.
- Portfolio — репо homelab-infrastructure опубликовано на GitHub с docs/, terraform/, ansible/.

## Next

- Backup/restore — проверить восстановление хотя бы одного сервиса (кандидат — Gitea), написать restore runbook.
- Monitoring debt — Loki isDefault постоянный фикс через values.yaml в Git; сейчас только kubectl patch.
- Secrets end-to-end — Alertmanager SMTP через OpenBao Injector.
- Security — firewall rules, Registry auth/TLS, Portainer docker.sock risk.

## Later

- Добавить restore runbook после первой успешной проверки восстановления.
- GitOps expansion — перенести monitoring stack под управление ArgoCD.
- HA k3s — три server nodes с embedded etcd.
- Longhorn — distributed storage вместо NFS SPOF.
- SSO — Authentik или Keycloak.
