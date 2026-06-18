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

## Inventory

Основной inventory:

```bash
inventories/homelab/hosts.ini
```

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

После этого inventory можно будет перевести на:

```ini
ansible_user=ansible
```

## Проверка inventory

Проверить синтаксис inventory:

```bash
ansible-inventory -i inventories/homelab/hosts.ini --list
```

Проверить SSH + Python + выполнение Ansible-модуля:

```bash
ansible all -i inventories/homelab/hosts.ini -m ping
```

Ожидаемый результат:

```text
ping: pong
```

Важно: `ansible -m ping` — это не ICMP ping. Он проверяет, что Ansible может подключиться по SSH и выполнить модуль на удаленной машине.

## Текущее состояние

На 2026-06-01 Ansible `ping` успешно проверен для:

- `homelab`
- `k3s-worker-01`
- `k3-worker-2`
- `gitea`
- `woodpecker`
- `openbao`

## Следующие шаги

- добавить `ansible.cfg`;
- сделать первый read-only healthcheck playbook;
- создать отдельного пользователя `ansible` на managed nodes;
- позже перенести проект в Git/Gitea и запускать с `ansible-control`.
