# Operations

Практические проверки, которые помогают понять, что homelab работает ожидаемо.

## Kubernetes

Что проверять:

- состояние нод;
- namespace и лишние тестовые workloads;
- Service и Ingress;
- CoreDNS и разрешение Service DNS;
- Helm releases;
- состояние ArgoCD applications.

Примеры команд:

```bash
kubectl get nodes -o wide
kubectl get ns
kubectl get ingress -A
kubectl get svc -A
helm list -A
```

## DNS

Что проверять:

- локальные DNS-записи для сервисов;
- Kubernetes Service DNS внутри кластера;
- отсутствие зависимости от ручного обращения по IP там, где можно использовать DNS.

Примеры команд:

```bash
dig service.example.local
kubectl exec dns-debug -- nslookup service.namespace.svc.cluster.local
```

## Remote Access

Что проверять:

- работает ли FRP client;
- какие сервисы опубликованы через VPS;
- нет ли лишних открытых портов;
- не лежат ли токены и пароли в публичных файлах.

Примеры команд:

```bash
systemctl status frpc --no-pager
ss -lntup
```

## Storage

Что проверять:

- NFS export;
- Kubernetes StorageClass;
- PVC/PV;
- свободное место на дисках;
- состояние MinIO и Registry.

Примеры команд:

```bash
kubectl get storageclass
kubectl get pvc -A
kubectl get pv
df -h
```

## Ansible

Healthcheck playbook запускается с VM105 (ansible-control) и проверяет все ноды.

```bash
ansible all -m ping
ansible-playbook playbooks/healthcheck.yml
```

Ожидаемый результат: все 6 хостов отвечают, uptime / disk / memory в норме.

## Backup / Restore

Backup считается полезным только после проверки restore.

Минимальный план:

- определить критичные данные по каждому сервису;
- сделать backup в MinIO или на внешнее хранилище;
- восстановить один сервис в тестовом сценарии (кандидат — Gitea);
- описать restore runbook.
