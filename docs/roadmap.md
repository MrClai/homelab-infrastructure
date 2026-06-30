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
- Secrets — подключены OpenBao и Vault Agent Injector; Grafana получает пароль через Injector. Все пароли вынесены из values.yaml и Git.
- Storage — используются NFS persistent volumes и MinIO.
- Network — GL-MT6000 настроен как основной роутер, DHCP, DNS и firewall.
- Remote access — настроен доступ через VPS и FRP.
- Ansible — control node на VM105, healthcheck playbook, create-ansible-user, update-linux.
- Kubernetes cleanup — тестовые workloads и namespace удалены.
- Monitoring fix — Loki isDefault зафиксирован постоянно в values.yaml, подтверждён в Helm-управляемом ConfigMap.
- Architecture decisions — 7 ADR опубликованы в docs/decisions.md (k3s, Proxmox, OpenBao, ArgoCD, Terraform, MinIO, GL-MT6000).
- Backup — реализован backup для OpenBao (Raft snapshot) и MinIO (self-archive), оба загружаются в MinIO bucket с offsite-копией на отдельной машине. Restore проверен в изолированном окружении: snapshot успешно восстанавливается, init и unseal проходят корректно.

## Next

- Security — firewall rules, Registry auth/TLS, Portainer docker.sock risk.

## Later

- Restore runbook — оформить пошаговую инструкцию на основе уже проверенного restore-сценария.
