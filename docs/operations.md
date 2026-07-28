# Operations

Практические проверки, которые помогают понять, что homelab работает ожидаемо.

Этот документ описывает проверки текущего состояния. Для безопасного внесения изменений используется отдельный порядок [Infrastructure Change Validation](ops/infrastructure-change-validation.md).

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

Что бэкапится: OpenBao (Raft snapshot) и MinIO (self-archive, включая Terraform state). Gitea исключена из scope — репозитории дублируются на локальной машине и на GitHub, поэтому не является точкой отказа.
Restore проверен для обоих сервисов в изолированном окружении и на фактическом сценарии отказа:

- OpenBao: snapshot восстановлен в отдельный Docker-инстанс — init, unseal
  и Raft committed index подтверждают целостность данных.
- MinIO: архив распакован в отдельный каталог, тестовый контейнер поднят
  на портах 9500/9501, `terraform.tfstate` прочитан через `mc cat` —
  валидный JSON, version 4.

Backup: MinIO-архив содержит и OpenBao-снапшот (bucket `backups/`), то есть один архив покрывает оба критичных актива.

```bash
# На VM104 (OpenBao)
./scripts/backup-openbao.sh

# На Pi5 (MinIO)
./scripts/backup-minio.sh

# На локальной машине, при подключении к домашней сети
./scripts/fetch-backups-to-laptop.sh
```

Restore также тестировался в изолированном Docker-инстансе на отдельной машине. Snapshot OpenBao успешно восстанавливается: после restore инстанс проходит init и unseal, Raft committed index подтверждает наличие реальных данных.
