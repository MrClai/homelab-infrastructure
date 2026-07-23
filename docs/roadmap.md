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
- Architecture decisions — 8 ADR опубликованы в docs/decisions.md (k3s, Proxmox, OpenBao, ArgoCD, Terraform, MinIO, GL-MT6000, политика прав Terraform и автозапуска VM).
- Backup — реализован backup для OpenBao (Raft snapshot) и MinIO (self-archive), оба загружаются в MinIO bucket с offsite-копией на отдельной машине. Restore проверен в изолированном окружении и на фактическом сценарии отказа: snapshot успешно восстанавливается, init и unseal проходят корректно.
- Restore runbook — оформлена пошаговая инструкция по восстановлению бекапов 
## Закрытые изменения после базовой версии

- VM autostart — `on_boot = true` для VM101–VM104, `on_boot = false` для VM105; `startup` не используется из-за расширенного права `Sys.Modify` на `/`.
- Proxmox TLS — проверка сертификата включена (`insecure = false`), CA доверена на Terraform control node.
- SSH host keys — `host_key_checking = True`, fingerprints узлов проверены до рабочего подключения.
- Restore after failure — фактический сценарий отказа проверен, результат занесён в runbook.

## Next

- Backup hardening — автоматизировать offsite-копирование и добавить контроль свежести backup.
- Registry hardening — auth/TLS и ограничение доступа к локальному Registry.
- MinIO PKI — Internal CA и TLS для S3 API; текущий HTTP backend оставлен осознанно для внутренней сети.
- Network hardening — описать и применить firewall zones без изменения уже проверенного FRP-доступа.
