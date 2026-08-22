# Ops: инцидент — SSH-аутентификация Ansible под `ansible` не работала, хотя выглядела настроенной (2026-07-23)

Журнал операции на control node `ansible-control` (VM105). Формат тот же, что в
[k3s-upgrade.md](k3s-upgrade.md): контекст → диагностика → root cause → фикс → урок.

---

## Контекст

`ansible.cfg` заявлял, что подключение выполняется отдельным
сервисным пользователем `ansible` (создан `create-ansible-user.yml`),
а `clai` остаётся только для ручной админки. Ранее это отмечалось как
проверенное: `host_key_checking = True` включён, fingerprints
сверены, `ansible all -m ping` успешен.

При сверке репозитория с реальным хостом выяснилось, что это было проверено
только частично: команда `ansible -m ping` действительно проходила, но не под
тем пользователем и не тем путём, который описан в документации.

## Симптом

После приведения `inventories/homelab/hosts.ini` в соответствие с `ansible.cfg`
(`ansible_user=clai` → `ansible_user=ansible`) все 6 хостов стали `UNREACHABLE`:

```
"msg": "Data could not be sent to remote host \"192.168.1.40\". Make sure this host can be reached over ssh: ansible@192.168.1.40: Permission denied (publickey,password).\r\n"
```

## Диагностика

**Шаг 1 — исключить проблему на стороне ключа/хоста.** Ручное подключение с явно
указанным ключом в обход Ansible:

```bash
ssh -v -i ~/.ssh/ansible_id ansible@192.168.1.40 echo ok
```

Результат: `Authenticated ... using "publickey"`, `ok`. Ключ верный, права на
файл верные, `authorized_keys` пользователя `ansible` на удалённом хосте
содержит нужный публичный ключ. Проблема не в ключе как таковом — она в том,
что Ansible этот ключ не использует.

**Шаг 2 — проверить, что Ansible реально применяет из конфига**, а не что
написано в файле:

```bash
ansible-config dump --only-changed
```

`PRIVATE_KEY_FILE` в выводе отсутствовал полностью, хотя в `ansible.cfg` строка
`private_key_file = ~/.ssh/ansible_id` присутствовала. Настройка задана, но
Ansible её не видит — значит, дело не в значении, а в том, что она не
распознаётся как эта настройка вообще.

**Шаг 3 — root cause №1.** `private_key_file` в конфиге стоял под секцией
`[ssh_connection]`:

```ini
[ssh_connection]
pipelining = True
private_key_file = ~/.ssh/ansible_id   # неверная секция
```

Ansible матчит ini-настройки по паре **(секция, ключ)**, а не по имени ключа
отдельно. `private_key_file` зарегистрирован в `config.yml` как настройка
секции `[defaults]`. В `[ssh_connection]` эта строка не ошибка и не warning —
она просто никем не подхватывается. Симптом («работает вручную, не работает
через Ansible») — прямое следствие: Ansible SSH-плагин собирает команду без
`-i`, откатывается на default identity files, для `clai` их для доступа под
`ansible` нет.

**Фикс шага 3:**

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

Проверка: `ansible-config dump --only-changed | grep PRIVATE_KEY_FILE` →
`DEFAULT_PRIVATE_KEY_FILE(...) = /home/clai/.ssh/ansible_id`. Настройка
подхватилась.

**Шаг 4 — ошибка осталась, но сменился её смысл.** `ansible all -m ping` всё
ещё падал, но уже под другим пользователем: `clai@192.168.1.40: Permission
denied`, хотя `ansible.cfg` определяет `remote_user = ansible`.

**Root cause №2.** `inventories/homelab/hosts.ini` на реальном хосте по-прежнему
содержал:

```ini
[all:vars]
ansible_user=clai
```

Переменные inventory имеют приоритет выше, чем `ansible.cfg`: порядок —
host vars > group vars > `[all:vars]` > `ansible.cfg` > дефолты плейбука.
Пока `ansible_user=clai` жил в `[all:vars]`, он тихо перебивал
`remote_user = ansible` из конфига на каждом запуске — вне зависимости от
того, что было исправлено в `ansible.cfg` на шаге 3.

**Фикс шага 4:**

```ini
[all:vars]
ansible_user=ansible
```

**Итоговая проверка:**

```bash
ansible all -m ping
```

`pong` на всех 6 хостах: `homelab`, `k3s-worker-01`, `k3-worker-2`, `gitea`,
`woodpecker`, `openbao`.

## Root cause — сводка

Два независимых бага маскировали друг друга:

1. `private_key_file` в неверной ini-секции → Ansible не подключает нужный
   ключ, откатывается на дефолтные identity files.
2. `ansible_user` в `[all:vars]` перебивает `remote_user` из `ansible.cfg` →
   даже без бага №1 подключение шло бы под `clai`, а не под сервисным
   `ansible`.

Ни один из них не выдавал ошибку при чтении конфига — оба проявлялись только
на реальном SSH-подключении. Поэтому `ansible -m ping`, отмеченный ранее как
рабочий, был пройден — но под `clai` с оверрайдом из inventory,
а не под сервисным `ansible`, который документация называла источником
правды.

## Урок

«Команда выполнилась без ошибок» и «система работает так, как задокументировано»
— разные утверждения. `ansible -m ping` возвращал `pong` до этого разбора —
но проверял не тот путь, который считался проверенным. Тот же паттерн, что
и в инциденте с DNS при апгрейде k3s (`k3s-upgrade.md`): задача была закрыта
по факту «работает у меня», а не по факту «настроено так, как описано».

Практическое следствие: после любого изменения в `ansible.cfg` или inventory,
которое касается подключения (`remote_user`, `ansible_user`,
`private_key_file`, ключи), проверка — не «файл сохранён», а
`ansible-config dump --only-changed` + `ansible all -m ping` с чистого листа.

## Чем это отличалось бы в production

Тест конфигурации подключения был бы частью CI (линтинг и smoke-test
Ansible в Woodpecker), а не ручной проверкой после факта. Изменение
`ansible.cfg`/inventory ревьюилось бы отдельно от logic-плейбуков именно
потому, что ошибки в нём не ловятся синтаксической проверкой YAML.

## Известные грабли

| Симптом | Причина | Диагностика |
|---|---|---|
| Ключ работает через `ssh -i` вручную, но не через Ansible | `private_key_file` в неверной ini-секции (`[ssh_connection]` вместо `[defaults]`) | `ansible-config dump --only-changed \| grep PRIVATE_KEY_FILE` — если пусто, конфиг не читается |
| `ansible.cfg` говорит один `remote_user`, а в логах ошибка под другим юзером | `ansible_user` задан в inventory (`[all:vars]` / group / host) и перебивает `ansible.cfg` | `ansible-inventory --host <host>` покажет эффективное значение `ansible_user` |
| Задача помечена ✅ Done, но конкретный путь не воспроизводится с нуля | Проверка была частичной (например, тестировали `-u ansible` вручную, а не дефолтный запуск) | Пересобрать сценарий с нуля: чистая сессия, без ручных `-u`/`-i` в командной строке |
