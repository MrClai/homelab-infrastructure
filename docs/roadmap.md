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
- Architecture decisions — 12 ADR опубликованы в docs/decisions.md (k3s, Proxmox, OpenBao, ArgoCD, Terraform, MinIO, GL-MT6000, политика прав Terraform и автозапуска VM, размещение MinIO вне кластера, internal CA для TLS, TLS и auth для Docker Registry, reclaim policy для критичных PV мониторинга).
- Backup — реализован backup для OpenBao (Raft snapshot) и MinIO (self-archive), оба загружаются в MinIO bucket с offsite-копией на отдельной машине. Restore OpenBao проверен в отдельном Docker-инстансе. Свежий production-архив MinIO восстановлен 21.09.2026 в отдельный пустой MinIO через S3 API; SHA-256 объекта до и после совпал. Аварийная замена production-инстанса не прогонялась.
- Restore runbook — оформлена пошаговая инструкция по восстановлению бекапов.
- Windows on Proxmox (учебный эксперимент) — шаблон Windows Server 2025 (VirtIO, QEMU Guest Agent, Cloudbase-Init 1.1.8, Sysprep); пробный клон получил hostname, DHCP и пароль администратора через ConfigDrive2. Terraform для Windows-клонов и конвертация в Proxmox template сознательно не делались.

## Закрытые изменения после базовой версии

- VM autostart — `on_boot = true` для VM101–VM104, `on_boot = false` для VM105; `startup` не используется из-за расширенного права `Sys.Modify` на `/`.
- Proxmox TLS — проверка сертификата включена (`insecure = false`), CA доверена на Terraform control node.
- SSH host keys — `host_key_checking = True`, fingerprints узлов проверены до рабочего подключения.
- Restore after failure — проверочный restore production-бэкапа MinIO выполнен в изолированной цели; аварийное переключение production-инстанса задокументировано, но не прогонялось при реальном отказе.
- MinIO PKI — развёрнут собственный internal CA, MinIO переведён на HTTPS-only с сертификатом от него; Terraform backend и оба backup-скрипта переключены и проверены.
- Registry hardening — TLS (тот же internal CA) и basic auth (bcrypt) для локального Docker Registry; заодно сервис переведён с голого `docker run` на `docker-compose.yaml`.
- PV reclaim policy — критичные PersistentVolume мониторинга (Prometheus, Grafana, Loki, Alertmanager) переведены на `Retain`; заведён отдельный StorageClass для будущих критичных сервисов, чтобы не менять поведение по умолчанию для временных нагрузок.

## Next

- Backup hardening — автоматизировать offsite-копирование, добавить контроль свежести backup и покрыть backup'ом критичные PersistentVolume (сейчас есть только для OpenBao и MinIO).
- Network hardening — описать и применить firewall zones без изменения уже проверенного FRP-доступа; пересмотреть широкие firewall-правила и список открытых портов.
- CI checks — добавить в существующий CI (Gitea + Woodpecker) линтеры для Terraform, Ansible, YAML и shell-скриптов.
- GitOps hygiene — зафиксировать единый источник правды для ArgoCD values (правки через Helm/Git, не руками).
