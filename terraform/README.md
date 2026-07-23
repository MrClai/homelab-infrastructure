# homelab-terraform

Terraform-конфигурация для управления виртуальными машинами на Proxmox VE.

## Что это

Terraform запускается с control node внутри homelab:

- VM: `101` (k3s-worker-01 используется как рабочая машина для Terraform)
- Proxmox host: `192.168.1.20`
- Провайдер: [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest) `~> 0.100.0`
- Terraform: `>= 1.14.0`
- State: MinIO S3 backend — `terraform-state/homelab/terraform.tfstate`

State хранится локально в MinIO на Pi5 (`pi5.homelab.local:9002`). Внешние сервисы не используются.

## Структура проекта

```
terraform/
├── backend.tf      # S3 backend (MinIO)
├── providers.tf    # bpg/proxmox провайдер
├── versions.tf     # версии Terraform и провайдера
├── variables.tf    # переменные: пароли, SSH-ключи, CPU, сеть
├── vms.tf          # описание всех VM
├── outputs.tf      # output: id и name каждой VM
└── .gitignore      # исключает .terraform/, *.tfvars, terraform.tfstate
```

## Что управляется

| VM ID | Имя | Назначение | RAM | Диск |
|-------|-----|-----------|-----|------|
| 101 | k3s-worker-01 | k3s worker node | 4096 MB | 40 GB (local-lvm, raw) |
| 102 | Gitea | Self-hosted Git | 2048 MB | 20 GB (data, qcow2) |
| 103 | woodpecker | Woodpecker CI | 2048 MB | 20 GB (data, qcow2) |
| 104 | openbao | Secrets manager | 2048 MB | 20 GB (local-lvm, raw) |
| 105 | ansible-control | Ansible control node | 1024 MB | 20 GB (local-lvm, raw) |

VM 101–103 существовали до введения IaC — добавлены в state через `terraform import`.  
VM 104 и 105 созданы через Terraform с cloud-init: статический IP, пользователь, SSH-ключи.

## Конфигурация

### Backend

`backend.tf` подключает MinIO как S3-совместимый backend:

```hcl
terraform {
  backend "s3" {
    bucket    = "terraform-state"
    key       = "homelab/terraform.tfstate"
    endpoints = { s3 = "http://192.168.1.10:9002" }
    ...
  }
}
```

`skip_credentials_validation`, `use_path_style` и другие флаги нужны потому что MinIO — не настоящий AWS S3, и без них Terraform падает на validation шагах.

### Провайдер

`providers.tf` использует `insecure = false`. Самоподписанный сертификат Proxmox добавлен в доверенное хранилище на машине, с которой запускается Terraform. Отключение проверки TLS не используется.

### Автозапуск VM

Для VM101–VM104 задано `on_boot = true`: Proxmox запускает их после старта гипервизора. Для VM105 (`ansible-control`) задано `on_boot = false`, потому что control node не требуется поднимать автоматически.

Параметр `started = true` отвечает за состояние VM после применения Terraform. Блок `startup` намеренно не используется: настройка порядка запуска требует расширенного права `Sys.Modify` на корне Proxmox (`/`), что нарушает выбранную модель least privilege для Terraform-токена.

### Переменные

Чувствительные переменные (`sensitive = true`) не попадают в вывод `plan` и `apply`.  
Передаются через `terraform.tfvars` (не коммитится, в `.gitignore`) или через env:

```bash
export TF_VAR_proxmox_password="..."
export TF_VAR_vm_password="..."
```

Пример `terraform.tfvars`:

```hcl
proxmox_password       = "..."
vm_password            = "..."
vm_openbao_password    = "..."
ssh_public_key         = "ssh-ed25519 ..."
ssh_public_key_windows = "ssh-ed25519 ..."
```

## Использование

Инициализация backend и провайдера:

```bash
terraform init
```

Проверить что изменится:

```bash
terraform plan
```

Ожидаемый результат для уже настроенной инфраструктуры:

```text
No changes. Your infrastructure matches the configuration.
```

Применить изменения:

```bash
terraform apply
```

## Текущее состояние

На 2026-06-14 выполнено:

- Terraform установлен на VM101, провайдер `bpg/proxmox` v0.100.0
- S3 backend в MinIO настроен, state хранится в `terraform-state/homelab/terraform.tfstate`
- VM101, VM102, VM103 импортированы через `terraform import`
- `terraform plan` = No changes для всех трёх VM
- VM104 (openbao) и VM105 (ansible-control) созданы через Terraform с cloud-init
- SSH-ключи прокинуты через cloud-init, не через `ssh-copy-id`
- VM101–VM104 настроены с `on_boot = true`, VM105 — с `on_boot = false`; порядок запуска через `startup` не используется
- Проверка TLS Proxmox включена (`insecure = false`); CA доверена на control node
- `terraform plan` после изменений подтвердил ожидаемый in-place update без создания или удаления VM
- Код в Gitea: `http://gitea.homelab.local:3000/igor/homelab-terraform`
