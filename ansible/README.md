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
├── inventories
│   └── homelab
│       └── hosts.ini
└── playbooks
    ├── create-ansible-user.yml
    ├── healthcheck.yml
    └── update-linux.yml
```

## Конфигурация

`ansible.cfg` задаёт дефолты — inventory, пользователь подключения, параметры SSH:

```ini
[defaults]
inventory = inventories/homelab/hosts.ini
remote_user = ansible
host_key_checking = True
retry_files_enabled = False
private_key_file = ~/.ssh/ansible_id

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
ansible_user=ansible
```

Service account:

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

Пометка: `ansible -m ping` — это не ICMP ping. Он проверяет, что Ansible может подключиться по SSH и выполнить модуль на удалённой машине.

## Текущее состояние

На 2026-06-14 `ansible.cfg` настроен, `ansible all -m ping` успешно проверен для всех хостов:

- `homelab` — k3s master (Pi5)
- `k3s-worker-01` — k3s worker VM101
- `k3-worker-2` — k3s worker Digma PRO
- `gitea` — Gitea VM102
- `woodpecker` — Woodpecker CI VM103
- `openbao` — OpenBao VM104

На 2026-06-25 выполнено:

- `ansible.cfg` настроен, `ansible all -m ping` работает без флагов
- Все 6 хостов отвечают pong: homelab, k3s-worker-01, k3-worker-2, gitea, woodpecker, openbao
- `playbooks/healthcheck.yml` — read-only проверка uptime, disk, memory на всех нодах
- `playbooks/create-ansible-user.yml` — создан service account `ansible` на всех нодах, SSH-ключ прокинут
- `ansible.cfg` переключён на пользователя `ansible` с отдельным SSH-ключом `~/.ssh/ansible_id`
- `playbooks/update-linux.yml` — обновление apt кэша и пакетов на всех нодах

На 2026-07-27 выполнено (подробности — `docs/ops/security-baseline.md`, раздел «Automation account privileges»):

- `ansible`-учётке выдан `NOPASSWD` sudo на всех управляемых хостах (`/etc/sudoers.d/ansible-nopasswd`), bootstrap выполнен один раз вручную через `clai`
- `private_key_file` перенесён в правильную секцию `[defaults]` — раньше стоял в `[ssh_connection]` и молча игнорировался Ansible (см. `docs/ops/ansible-ssh-auth-incident.md`)
- `host_key_checking = True` подтверждён в рабочем `ansible.cfg`

## Следующие шаги

- [X] сделать первый read-only healthcheck playbook;
- [X] создать отдельного пользователя `ansible` на managed nodes;
- [ ] Расширить base Linux playbook — SSH hardening, firewall, nfs-common
