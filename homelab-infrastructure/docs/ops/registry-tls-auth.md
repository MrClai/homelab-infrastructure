# Ops: TLS и auth для Docker Registry (2026-07-28)

Журнал операции: сертификат от уже существующего internal CA, `htpasswd`, перевод с голого `docker run` на `docker-compose`. Формат тот же, что в [k3s-upgrade.md](k3s-upgrade.md) и [minio-tls-internal-ca.md](minio-tls-internal-ca.md).

Решение и альтернативы — в [ADR-011](../decisions.md#adr-011-tls-и-basic-auth-для-docker-registry). Этот документ — «как именно», не «почему».

---

## Контекст и цель

Registry (`registry:2`, Pi5, `:5000`) работал без TLS и без auth — открыт `0.0.0.0:5000` в локальной сети без единого ограничения на push/pull.

**Цель:** TLS от уже существующего internal CA (ADR-010), basic auth через `htpasswd`, без нового корня и без отдельного auth-сервера.

## Диагностика: два расхождения найдены до начала работы

**Расхождение 1 — ADR-006 был неверным.** Документ утверждал, что Registry использует MinIO как S3-backend. Проверка фактом:

```bash
docker exec registry cat /etc/docker/registry/config.yml
```

```yaml
storage:
  filesystem:
    rootdirectory: /var/lib/registry
```

Registry пишет на локальный диск (`/mnt/registry` через bind-mount), MinIO вообще не задействован. ADR-006 исправлен — это меняло объём работы: не нужно готовить Registry как S3-клиента MinIO, TLS для него полностью независим.

**Расхождение 2 — конфига на диске не было вовсе.**

```bash
docker inspect registry --format '{{json .HostConfig.Binds}}'
# ["/mnt/registry:/var/lib/registry"]

docker inspect registry --format '{{.Path}} {{json .Args}}'
# /entrypoint.sh ["/etc/docker/registry/config.yml"]
```

Единственный volume — данные. `config.yml`, который отдавал `docker exec ... cat`, — дефолт, встроенный в сам образ `registry:2`, не смонтированный файл. Значит, чтобы добавить TLS/auth, нужно завести свой `config.yml` и примонтировать его новым volume — редактировать было нечего.

**Проверка, чем контейнер вообще держится:**

```bash
docker inspect registry --format '{{.HostConfig.RestartPolicy.Name}}'   # always
sudo find / -iname "*registry*.service" 2>/dev/null                     # только systemd-fsck по метке ФС, не про контейнер
find ~ -iname "*.sh" | xargs grep -l "registry" 2>/dev/null             # пусто
```

Никакого стороннего юнита или скрипта — только флаг `--restart always` у самого Docker, поставленный при разовом `docker run`. Ничего не конфликтует с переходом на `docker-compose`.

## Подготовка (удалённо, VM105 + Pi5)

**Сертификат** — тот же CA, что и у MinIO, просто новый лист:

```bash
sudo openssl genrsa -out /opt/homelab-ca/private/registry.key 2048
sudo openssl req -new -key /opt/homelab-ca/private/registry.key \
  -out /opt/homelab-ca/csr/registry.csr \
  -subj "/C=RU/O=Homelab/CN=registry.homelab.local" \
  -addext "subjectAltName=DNS:registry.homelab.local,IP:192.168.1.10"
sudo openssl x509 -req \
  -in /opt/homelab-ca/csr/registry.csr \
  -CA /opt/homelab-ca/certs/ca.crt -CAkey /opt/homelab-ca/private/ca.key \
  -CAcreateserial \
  -out /opt/homelab-ca/certs/registry.crt \
  -days 365 -sha256 -copy_extensions copy
```

SAN сразу с DNS-именем и IP — фактический способ обращения к Registry (по имени или по IP) не удалось восстановить из истории команд и конфигов в репозитории, поэтому подстраховались обоими, как и с MinIO.

**htpasswd** — обязательно bcrypt, иначе Registry не примет:

```bash
htpasswd -Bbn ci '<пароль>' > /opt/homelab-ca/registry_htpasswd
```

Споткнулись на `Permission denied` — `/opt/homelab-ca` целиком принадлежит `root` (создавался через `sudo mkdir` в фазах A7). Фикс: `sudo htpasswd ... | sudo tee файл`. Отдельно проверили, что `sudo tee` не оставил лишнюю пустую строку в файле (`awk -F: '{print length($2)}'` вернул два значения вместо одного — `60` и `0`); почищено `sed -i '/^$/d'`.

**`config.yml`** — дефолтный из образа плюс секции `tls` и `auth`:

```yaml
version: 0.1
log:
  fields:
    service: registry
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
  tls:
    certificate: /certs/registry.crt
    key: /certs/registry.key
auth:
  htpasswd:
    realm: homelab-registry
    path: /auth/registry_htpasswd
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
```

**`docker-compose.yaml`** — перенос существующей конфигурации в декларативный вид, `restart: always` сохранён без изменений:

```yaml
services:
    registry:
        image: registry:2
        container_name: registry
        ports:
            - "5000:5000"
        volumes:
            - /mnt/registry:/var/lib/registry
            - /home/clai/registry/config.yml:/etc/docker/registry/config.yml
            - /home/clai/registry/certs:/certs
            - /home/clai/registry/auth:/auth
        restart: always
```

**Перенос сертификата и ключа с VM105 на Pi5** — тем же способом, что вчера с MinIO: приватный ключ лежит под root, забирается через временную читаемую копию, которая сразу затирается:

```bash
scp clai@192.168.1.80:/opt/homelab-ca/certs/registry.crt ~/registry/certs/registry.crt
ssh clai@192.168.1.80 "sudo install -m 644 -o clai /opt/homelab-ca/private/registry.key /tmp/registry.key"
scp clai@192.168.1.80:/tmp/registry.key ~/registry/certs/registry.key
ssh clai@192.168.1.80 "shred -u /tmp/registry.key"
scp clai@192.168.1.80:/opt/homelab-ca/registry_htpasswd ~/registry/auth/registry_htpasswd
chmod 644 ~/registry/certs/registry.crt ~/registry/auth/registry_htpasswd
chmod 600 ~/registry/certs/registry.key
```

**Итог подготовки (28.07.2026, удалённо):**

```
-rw------- registry.key         (600, приватный ключ)
-rw-r--r-- registry.crt         (644)
-rw-r--r-- registry_htpasswd    (644, bcrypt-хеш, 64 байта — сошлось точно: "ci:" + 60 символов хеша)
-rw-rw-r-- config.yml
-rw-rw-r-- docker-compose.yaml
```

## Cutover (локально, вечер 28.07.2026)

> Раздел заполняется после выполнения — тот же принцип, что и с MinIO: рестарт сервиса на Pi5 только при физическом доступе, `frpc` живёт на том же хосте.

```bash
docker stop registry && docker rm registry
cd ~/registry
docker compose up -d
docker logs registry --tail 30
```

**Ожидаемая проверка:**

```bash
docker login registry.homelab.local:5000   # креды из registry_htpasswd
docker pull <существующий образ из /mnt/registry>
```

**Откат при проблеме:** старый образ `registry:2` тот же самый — убрать секции `tls`/`auth` из `config.yml`, `docker compose up -d` заново. Данные в `/mnt/registry` не затрагиваются ни при переходе, ни при откате.

## Результат (28.07.2026, вечер)

`docker logs registry --tail 30` — чисто, без единой ошибки про сертификат или конфиг:

```
level=info msg="listening on [::]:5000, tls" ... version=2.8.3
```

DNS-запись `registry.homelab.local → 192.168.1.10` уже резолвилась на момент проверки — добавлена заранее, отдельного шага не потребовалось.

Цепочка доверия — с самого Pi5, где корень уже стоит в системном trust store (раздан в A7):

```bash
openssl s_client -connect 192.168.1.10:5000 -CAfile /usr/local/share/ca-certificates/homelab-root-ca.crt </dev/null
# Verify return code: 0 (ok)
```

Аутентификация и реальная передача данных — разными путями, оба проверены:

```bash
docker login registry.homelab.local:5000        # Login Succeeded
docker pull alpine:latest
docker tag alpine:latest registry.homelab.local:5000/test-alpine:latest
docker push registry.homelab.local:5000/test-alpine:latest   # Pushed
docker pull registry.homelab.local:5000/test-alpine:latest   # Downloaded
```

**Побочная находка:** `docker login` предупредил, что креды в `~/.docker/config.json` хранятся не в зашифрованном виде (base64, не plaintext, но и не шифрование). Для homelab не критично — принято как известный мелкий долг, не блокирует закрытие задачи. Решение при желании: credential helper (`pass`, `secretservice`) на клиентских машинах.

**Cleanup:** тестовый образ `test-alpine` в Registry — не production-нагрузка, можно удалить через `registry` garbage collection при следующем плановом обслуживании; оставлен как есть, не блокирует закрытие A3.

## Известные грабли

| Симптом | Причина | Диагностика |
|---|---|---|
| `Permission denied` при попытке записать файл в `/opt/homelab-ca/` не под root | Каталог создавался через `sudo mkdir`, принадлежит `root`, не текущему пользователю | `sudo <команда> \| sudo tee файл` вместо прямого `>` |
| `docker exec <container> cat /etc/docker/registry/config.yml` показывает валидный конфиг, а `docker inspect` не показывает mount для этого пути | Конфиг — дефолт, встроенный в образ, а не смонтированный файл | Сверять `docker inspect --format '{{json .HostConfig.Binds}}'` с тем, что реально хочется редактировать, а не полагаться на то, что видно через `exec cat` |
