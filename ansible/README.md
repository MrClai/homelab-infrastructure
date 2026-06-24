# homelab-ansible

Ansible-проект для базовой эксплуатации homelab.

## Что это

Ansible запускается с отдельной control node внутри homelab:

- VM: `105`
- Hostname: `ansible-control`
- IP: `192.168.1.80`
- OS: Ubuntu 24.04 LTS
- Создана через Terraform в Proxmox

Ноутбук не является частью homelab automation. Он используется только как рабочий терминал/редактор.

## Структура проекта

```
homelab-ansible/
├── ansible.cfg
└── inventories/
    └── homelab/
        └── hosts.ini
```

## Конфигурация

`ansible.cfg` задаёт дефолты — inventory, пользователь подключения, параметры SSH:

```ini
[defaults]
inventory = inventories/homelab/hosts.ini
remote_user = clai
host_key_checking = False
retry_files_enabled = False

[ssh_connection]
pipelining = True
```

## Inventory

Основной inventory: `inventories/homelab/hosts.ini`

Группы:

- `k3s_masters` — k3s control-plane на Pi5
- `k3s_workers` — worker-ноды k3s
- `services` — отдельные VM с сервисами: Gitea, Woodpecker CI, OpenBao

Текущий пользователь подключения:

```ini
ansible_user=clai
```

Позже нужно создать отдельного service account:

```text
clai    = ручная админка
ansible = automation/service account
```

## Проверка inventory

Проверить синтаксис inventory:

```bash
ansible-inventory --list
```

Проверить SSH + Python + выполнение Ansible-модуля:

```bash
ansible all -m ping
```

Ожидаемый результат:

```text
ping: pong
```

Важно: `ansible -m ping` — это не ICMP ping. Он проверяет, что Ansible может подключиться по SSH и выполнить модуль на удалённой машине.

## Текущее состояние

На 2026-06-14 `ansible.cfg` настроен, `ansible all -m ping` успешно проверен для всех хостов:

- `homelab` — k3s master (Pi5)
- `k3s-worker-01` — k3s worker VM101
- `k3-worker-2` — k3s worker Digma PRO
- `gitea` — Gitea VM102
- `woodpecker` — Woodpecker CI VM103
- `openbao` — OpenBao VM104

## Следующие шаги

- [X] сделать первый read-only healthcheck playbook;
- [ ] создать отдельного пользователя `ansible` на managed nodes;
- [ ] перенести проект в Gitea и запускать с `ansible-control`.
