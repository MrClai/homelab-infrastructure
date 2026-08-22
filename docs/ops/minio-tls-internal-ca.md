# Ops: Internal CA и TLS для MinIO (2026-07-27)

Журнал операции: собственный CA через openssl, сертификат MinIO, раздача доверия, переключение TLS. Формат тот же, что в [k3s-upgrade.md](k3s-upgrade.md) и [ansible-ssh-auth-incident.md](ansible-ssh-auth-incident.md): контекст → план → исполнение → инциденты → итог.

Решение и альтернативы — в [ADR-009](../decisions.md#adr-009-minio-остаётся-вне-кластера-k3s) и [ADR-010](../decisions.md#adr-010-internal-ca-для-tls-внутренних-сервисов). Этот документ — не «почему», а «как именно» и «что пошло не так».

---

## Контекст и цель

MinIO обслуживал клиентов по HTTP: `terraform.tfstate` и Raft-снапшоты OpenBao ходили по локальной сети открытым текстом, без шифрования и без доказательства, что клиент вообще говорит с настоящим MinIO. Подтверждённые клиенты на момент старта: VM101 (Terraform S3 backend), Pi5 сам (`backup-minio.sh`), VM104/openbao (`backup-openbao.sh`), VM105 (хост будущего CA).

**Цель:** свой internal CA, TLS-сертификат для MinIO, доверие роздано всем клиентам, MinIO переключён на HTTPS, все потребители (Terraform, оба бэкап-скрипта) продолжают работать.

## План по фазам

| Фаза | Что | Где |
|---|---|---|
| 0 | Страховочная копия `terraform.tfstate` | VM101 |
| 1 | Корневой CA: ключ 4096 + самоподпись на 10 лет | VM105 |
| 2 | Сертификат MinIO: CSR с SAN (DNS+IP) → подпись | VM105 |
| 3 | Раздача корня клиентам через Ansible | все 6 хостов |
| 4 | Включить TLS в MinIO | Pi5, только локально |
| 5 | Terraform backend http → https | VM101 |
| 6 | `mc alias` в бэкап-скриптах, документация | Pi5, VM104 |

Фазы 1–3 выполнены удалённо, фаза 4 намеренно отложена до физического присутствия у Pi5: узел одновременно хостит `frpc`, и рестарт сервиса, сломавший сеть, обрубил бы и путь для отката.

## Фаза 0 — страховка

```bash
cd ~/terraform/homelab
terraform state pull > terraform.tfstate.backup-$(date +%Y%m%d)
```

Важно: `.terraform/terraform.tfstate` — это **не** state, а служебный указатель на backend (несколько КБ). Реальный state вытягивается только через `terraform state pull`, независимо от того, локальный backend или S3.

## Фазы 1–2 — корневой CA и сертификат MinIO

```bash
# корень — на VM105, не на Pi5: приватный ключ не должен жить на узле, обслуживающем трафик
sudo mkdir -p /opt/homelab-ca/{private,certs,csr}
sudo chmod 700 /opt/homelab-ca/private
sudo openssl genrsa -aes256 -out /opt/homelab-ca/private/ca.key 4096
sudo chmod 400 /opt/homelab-ca/private/ca.key

sudo openssl req -x509 -new -key /opt/homelab-ca/private/ca.key \
  -sha256 -days 3650 \
  -out /opt/homelab-ca/certs/ca.crt \
  -subj "/C=RU/O=Homelab/CN=Homelab Root CA"
sudo chmod 644 /opt/homelab-ca/certs/ca.crt

# лист — 2048 бит, год жизни: короткий срок ограничивает окно ущерба при компрометации,
# отзыва (CRL/OCSP) в этом контуре нет, поэтому единственный реальный механизм — истечение
sudo openssl genrsa -out /opt/homelab-ca/private/minio.key 2048
sudo openssl req -new -key /opt/homelab-ca/private/minio.key \
  -out /opt/homelab-ca/csr/minio.csr \
  -subj "/C=RU/O=Homelab/CN=minio.homelab.local" \
  -addext "subjectAltName=DNS:minio.homelab.local,IP:192.168.1.10"

sudo openssl x509 -req \
  -in /opt/homelab-ca/csr/minio.csr \
  -CA /opt/homelab-ca/certs/ca.crt -CAkey /opt/homelab-ca/private/ca.key \
  -CAcreateserial \
  -out /opt/homelab-ca/certs/minio.crt \
  -days 365 -sha256 \
  -copy_extensions copy
```

`-copy_extensions copy` обязателен: без него SAN из CSR не переносится в готовый сертификат при подписи через `x509 -req`, и вся работа с SAN пропадает впустую молча, без ошибки.

DNS-запись `minio.homelab.local → 192.168.1.10` добавлена на GL-MT6000 отдельно, вечером — днём роутер был недоступен из текущей сессии.

## Фаза 3 — раздача доверия

Плейбук `playbooks/distribute-ca.yml`, `hosts: all` — копирует `ca.crt` в `/usr/local/share/ca-certificates/` и вызывает `update-ca-certificates`.

## Инцидент 1: у `ansible` не было пути стать root

**Симптом:** первый же прогон плейбука с `become: true` — `Missing sudo password` на всех шести хостах.

**Диагностика:** `create-ansible-user.yml` создаёт пользователя и кладёт SSH-ключ, но нигде не выдаёт sudo. `healthcheck.yml` — единственный плейбук, работавший с этой учёткой раньше, — стоит с `become: false`. `ansible.builtin.user` без `password:` создаёт аккаунт без пароля вообще (`!` в shadow) — `--ask-become-pass` был обречён по конструкции, вводить нечего.

**Фикс:** bootstrap от `clai` (единственной учётки с рабочим sudo), один раз:

```bash
# playbooks/grant-ansible-sudo.yml
- hosts: all
  remote_user: clai
  become: true
  tasks:
    - name: Allow ansible user passwordless sudo
      ansible.builtin.copy:
        dest: /etc/sudoers.d/ansible-nopasswd
        content: "ansible ALL=(ALL) NOPASSWD:ALL\n"
        owner: root
        group: root
        mode: '0440'
        validate: 'visudo -cf %s'
```

`validate: 'visudo -cf %s'` — без него синтаксическая ошибка в sudoers способна отключить sudo на хосте целиком.

## Инцидент 2: та же ловушка `ansible_user`, что и 23.07 — просто в другую сторону

**Симптом:** `grant-ansible-sudo.yml` с `--ask-become-pass` под `clai` падал с `Incorrect sudo password` на всех шести хостах одновременно, при заведомо верном пароле.

**Диагностика:** `[all:vars] ansible_user=ansible` в inventory. Один пароль, введённый один раз в `--ask-become-pass`, применяется сразу ко всем хостам плея — но `remote_user: clai`, заданный как ключевое слово плейбука, действительно перебивает inventory-переменную для подключения. Проблема была не в этом. Проблема вскрылась на следующем шаге: ad-hoc команда с `--user=clai` (CLI-флаг, не ключевое слово плейбука) **inventory не перебивает** — `ansible_user` из `[all:vars]` оказывается сильнее `-u`/`--user`. Подтверждено через `whoami` внутри самой ad-hoc команды: реально подключались под `ansible`, а не под `clai`, хотя флаг был указан явно.

Это тот же класс бага, что зафиксирован в [ansible-ssh-auth-incident.md](ansible-ssh-auth-incident.md) («известные грабли», строка 2) — 23.07 `ansible_user` в inventory перебивал `ansible.cfg`; 27.07 та же переменная перебила уже CLI-флаг. Один и тот же механизм приоритета, два разных симптома.

**Фикс:** единственное, что реально стоит выше inventory — `-e` (extra-vars):

```bash
ansible all -m shell -a "whoami" -o -e ansible_user=clai
```

Но и это уперлось в третье: SSH-ключ, авторизованный для `ansible` (`~/.ssh/ansible_id`), не подходит для входа под `clai` — `Permission denied`. У `clai` свой ключ (человеческий, из Terraform `user_account.keys`), и в контексте ad-hoc/Ansible-SSH он не резолвился так же чисто, как в интерактивном `ssh clai@host`.

**Итоговое решение — не долблить Ansible-SSH дальше, а закрыть задачу напрямую:** раз ручной `ssh clai@host` уже работал без пароля, bootstrap sudoers сделан простым shell-циклом в обход Ansible:

```bash
for host in 192.168.1.10 192.168.1.21 192.168.1.30 192.168.1.40 192.168.1.50 192.168.1.60; do
  ssh clai@$host \
    "echo 'ansible ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/ansible-nopasswd \
     && sudo visudo -cf /etc/sudoers.d/ansible-nopasswd && echo OK"
done
```

После этого `ansible all -m command -a "whoami" -b` вернул `root` на всех шести — штатный путь через `ansible` восстановлен, к `clai` внутри Ansible больше возвращаться не пришлось.

## Фаза 4 — включить TLS в MinIO

MinIO развёрнут через `docker-compose`, не systemd напрямую — предположение про unit-файл оказалось неверным ещё до начала фазы. Официальный образ работает от `root` внутри контейнера и сам включает TLS, если находит `/root/.minio/certs/public.crt` и `private.key` — файлы должны называться ровно так, без вариантов.

```bash
# перенос с VM105 на Pi5: приватный ключ лежит под root, забираем через временную копию
mkdir -p ~/minio/certs
scp clai@192.168.1.80:/opt/homelab-ca/certs/minio.crt ~/minio/certs/public.crt
ssh clai@192.168.1.80 "sudo install -m 644 -o clai /opt/homelab-ca/private/minio.key /tmp/minio.key"
scp clai@192.168.1.80:/tmp/minio.key ~/minio/certs/private.key
ssh clai@192.168.1.80 "shred -u /tmp/minio.key"
chmod 644 ~/minio/certs/public.crt
chmod 600 ~/minio/certs/private.key
```

`shred -u` вместо `rm` — временная читаемая копия ключа на VM105 не должна остаться восстановимой на диске.

```yaml
# docker-compose.yaml — добавлена одна строка
volumes:
    - /mnt/minio:/data
    - /home/clai/minio/certs:/root/.minio/certs
```

```bash
docker compose down && docker compose up -d
docker logs minio --tail 30
```

Подтверждение — в самом логе, без дополнительных проверок: `API: https://...` вместо `http://`. MinIO не поддерживает одновременно оба протокола — как только нашёл сертификаты, HTTP перестаёт обслуживаться полностью. Это значит, что с этой секунды все старые HTTP-клиенты уже не работают, включая Terraform и оба бэкап-скрипта — окно между «сервер переключился» и «клиенты переключены» лучше не растягивать.

Проверка цепочки:

```bash
openssl s_client -connect minio.homelab.local:9002 -CAfile /opt/homelab-ca/certs/ca.crt </dev/null
# Verify return code: 0 (ok)
```

## Фаза 5 — Terraform backend

```bash
cd ~/terraform/homelab
sed -i 's#s3 = "http://192.168.1.10:9002"#s3 = "https://192.168.1.10:9002"#' backend.tf
terraform init -reconfigure
terraform plan
```

## Инцидент 3: credentials пропали при `-reconfigure`

**Симптом:** `terraform init -reconfigure` → `No valid credential sources found`, следом ошибка про EC2 IMDS — хотя `terraform state pull` в этой же директории отрабатывал минуты назад без проблем.

**Диагностика:** `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` в `~/.bashrc`, но объявлены без `export` — видны через `echo $VAR` в интерактивном шелле (builtin видит все shell-переменные), но не наследуются дочерним процессом `terraform`, которому передаются только экспортированные переменные окружения.

**Фикс:** добавить `export` перед обеими строками в `.bashrc`, `source ~/.bashrc`, проверять не через `echo`, а через `env | grep AWS_ACCESS_KEY_ID` — эта команда показывает только то, что реально попадёт в окружение дочерних процессов.

**Итог:** `terraform plan` → `No changes. Your infrastructure matches the configuration.`

## Фаза 6 — бэкап-скрипты

```bash
# на Pi5 и на VM104 отдельно — у каждого свой mc config
mc alias set homelab https://192.168.1.10:9002 <ACCESS_KEY> <SECRET_KEY>
mc ls homelab   # ожидаемо: backups/ ci-artifacts/ terraform-state/, без ошибок цепочки
```

Ключи брались из уже существующего `~/.mc/config.json` (alias `homelab` был настроен раньше под HTTP) — не нужно было ничего вспоминать заново, конфиг уже их хранил.

## Побочная находка: credentials засветились в переписке

При диагностике инцидента 3 значения `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` были вставлены в рабочий чат в открытом виде. Для homelab не критично, но по тому же принципу, что применялся к `gitlab-ci-key.json` — растрата в чате считается компрометацией. Ключ подлежит ротации через `mc admin accesskey`, независимо от вероятности реального использования.

## Итог

- MinIO — TLS-only, HTTP не обслуживается вообще.
- Terraform backend, `backup-minio.sh`, `backup-openbao.sh` — переведены и подтверждены.
- Корень CA живёт до 2036 года, лист MinIO — до **27.07.2027**; перевыпуск листа не требует пересборки корня.
- Побочно закрыт реальный пробел: учётка `ansible` не имела root ни разу с момента создания — до сегодняшнего дня это было не нужно ни одному плейбуку.
- Обнаружено и не является блокером: расхождение `host_key_checking` между `security-baseline.md` (заявлено `True`) и фактическим `ansible.cfg` (`False`).

## Чем это отличалось бы в production

Ротация листовых сертификатов — через ACME (step-ca), а не вручную; корневой CA — офлайн, подписывает промежуточный, не выдаёт листовые сертификаты напрямую; sudoers для сервисных учёток — через configuration management с самого создания аккаунта, а не отдельным bootstrap постфактум; credentials — только через secrets manager (OpenBao уже есть в стеке), никогда не в `.bashrc` и тем более не в переписке; переключение backend — с проверкой в CI, а не вручную с `-reconfigure` на боевом хосте.

## Известные грабли

| Симптом | Причина | Диагностика |
|---|---|---|
| `Missing sudo password` у сервисной учётки, которая вроде бы «настроена» | Аккаунт создан только с SSH-ключом, `become` никогда не тестировался | Проверить сам плейбук создания учётки на предмет sudoers, не полагаться на факт существования аккаунта |
| Один и тот же пароль в `--ask-become-pass` не подходит сразу нескольким хостам | Пароли `clai`/root разные на разных хостах (проверить `terraform/vms.tf`: не у всех VM единый `user_account.password`) | Не гонять bootstrap-пароль через Ansible на несколько хостов разом — тестировать по одному |
| `--user=X` в ad-hoc команде не подключает под X | `ansible_user` в inventory (`[all:vars]`) перебивает CLI-флаг `-u`/`--user` — но не ключевое слово `remote_user:` внутри плейбука | `whoami` первой задачей в самой команде/плейбуке; либо `-e ansible_user=X` (extra-vars — единственное, что реально выше inventory) |
| `echo $VAR` показывает значение, но дочерний процесс (terraform, любой бинарник) его не видит | Переменная объявлена в `.bashrc` без `export` | `env \| grep VAR` вместо `echo $VAR` — `env` показывает только то, что уйдёт в окружение дочерних процессов |
| MinIO Docker вдруг перестал отвечать по `http://` без единой строки в логе про ошибку | Так и задумано: MinIO переходит в TLS-only режим сразу, как только находит сертификаты в `/root/.minio/certs/` — HTTP не остаётся как fallback | Проверять `docker logs` на `https://` в строке `API:` сразу после рестарта, до того как трогать клиентов |
