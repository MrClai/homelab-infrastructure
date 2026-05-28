# Operations

Практические проверки, которые помогают понять, что homelab работает ожидаемо.

## Kubernetes

Что проверять:

- состояние нод;
- namespace и лишние тестовые workload;
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

## Backup / Restore

Backup считается полезным только после проверки restore.

Минимальный план:

- определить критичные данные;
- сделать backup;
- восстановить один сервис в тестовом сценарии;
- описать restore runbook.

Пока этот блок находится в работе.
