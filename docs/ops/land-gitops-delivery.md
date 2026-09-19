# Ops: доставка land через Woodpecker и ArgoCD, диагностика и откат (2026-09-17 — 2026-09-19)


Настройка Registry описана в [registry-tls-auth.md](registry-tls-auth.md),
обновление самого Woodpecker — в [woodpecker-upgrade.md](woodpecker-upgrade.md).

---

## Контекст и цель

Gitea, Woodpecker CI, Registry и ArgoCD уже работали, но законченного сценария
доставки приложения не было. Старый тестовый workload ArgoCD был удалён;
подключение к его репозиторию осталось в настройках.

Для проверки выбран `land` — статический сайт на Hugo, который раздаёт Caddy.
Исходники оставлены в приватном Gitea. Git и сборка — на VM103 (`woodpecker`),
Registry — на Pi5, приложение запускается в k3s.

**Цель:** провести изменение текста от коммита до работающего сайта, затем
намеренно сломать обновление и вернуть рабочее состояние через Git.

## Схема доставки

```text
Gitea: Igor/land
  ├─ исходники + Dockerfile + .woodpecker.yml
  │    └─ push → Woodpecker на VM103 → образ с тегом SHA коммита → Registry на Pi5
  └─ deploy/deployment.yaml + deploy/service.yaml
       └─ изменение тега в Git → Sync ArgoCD → Deployment и Service в k3s
```

Исходники и манифесты находятся в одном репозитории. ArgoCD читает только
`deploy/`; старый тестовый `homelab-gitops` в этой доставке не используется.

**Граница автоматизации:** push автоматически запускает CI. Тег готового образа
в Deployment меняется вручную, применение выполняется кнопкой Sync в ArgoCD.
Коммиты только с изменением манифестов содержат `[skip ci]`, чтобы повторно
не собирать уже опубликованный образ.

## Шаг 1 — ручная сборка перед подключением CI

Dockerfile собирает HTML через `klakegg/hugo:0.111.3-ext-alpine`, итоговый
образ использует `caddy:2-alpine`.

```bash
# На VM103, из ~/land
docker build -t land:test .
docker run -d --name land-test -p 127.0.0.1:8080:80 land:test
curl -i http://127.0.0.1:8080/
```

**Первая проверка:** HTTP 200, но заголовок страницы — `Caddy works!`.
Сборка прошла, однако сервер отдавал стандартную страницу.

**Причина:** Dockerfile копировал `/out` в `/var/www/html`, а встроенный
Caddyfile содержал `root * /usr/share/caddy`.

**Фикс в Dockerfile:**

```dockerfile
COPY --from=builder /out /usr/share/caddy
```

После пересборки образа и пересоздания контейнера получен HTML сайта.
Следующая находка — ссылки на CSS в HTML вели на внешний домен из `baseURL`.
Наличие этих файлов в образе не заставляло браузер использовать их локальную копию.

**Фикс в `site/config.toml`:**

```toml
baseURL = "/"
```

Проверены ссылка `/css/style.css` в HTML и HTTP 200 при запросе этого файла
у контейнера. Полный аудит остальных внешних ссылок не выполнялся.

## Шаг 2 — автоматический запуск CI и публикация образа

Создан приватный репозиторий `Igor/land` и подключён к Woodpecker.
Первый ручной pipeline проверил clone, сборку Hugo и наличие непустого
`index.html`. После исправления webhook настоящий push автоматически запустил
pipeline №4 — ручной запуск не считался подтверждением этой цепочки.

В pipeline добавлены:

- `build-site`: сборка Hugo и `test -s /tmp/land-public/index.html`;
- `build-and-push`: `docker:28-cli`, сборка Dockerfile и отправка образа
  `registry.homelab.local:5000/land:<полный-SHA-коммита>`;
- фильтр событий `push` в ветку `main`;
- секреты `registry_username` и `registry_password`, доступные только для push.

Docker CLI в шаге обращается к Docker на VM103 через подключённый socket.
Для репозитория разрешён Trusted-режим. Это даёт pipeline широкие права на
хосте сборки; вариант используется для контролируемого приватного репозитория,
а не для изоляции недоверенного кода.

Пароль передаётся в `docker login` через stdin. Docker-конфигурация шага
размещается в `/tmp/docker-auth` внутри контейнера задания. В `.dockerignore`
исключены `.git`, `site/public`, `site/.hugo_build.lock` и `**/.DS_Store`.

После расширения диска VM103 pipeline №6 успешно опубликовал первый образ:

```text
Тег:    d219cb422cb55ad1f973a033068de8a4a1eca845
Digest: sha256:90da21fbc6e4e14bd567b994ec5c170047157f03a70f17600c533666deb787c9
```

## Инцидент 1 — OAuth callback и DNS внутри Gitea

**Симптом при входе:** Gitea возвращала `Unregistered Redirect URI`.
В OAuth-приложении был разрешён доменный callback, но `WOODPECKER_HOST`
указывал IP. Открытие UI по имени не меняло адрес возврата, заданный серверу.

**Фикс:** в Compose сервера установлен
`WOODPECKER_HOST=http://woodpecker.homelab.local:8000`; в Gitea разрешён
соответствующий `/authorize`. Сервер пересоздан с сохранением volume и
существующих ключей. Вход по доменному имени подтверждён.

**Следующий симптом:** сборка запускалась вручную, но не после push.
В истории доставки webhook:

```text
lookup woodpecker.homelab.local on 127.0.0.11:53: server misbehaving
```

Контейнер Gitea не разрешал имя Woodpecker. В Compose сервиса Gitea добавлено:

```yaml
extra_hosts:
  - "woodpecker.homelab.local:192.168.1.50"
```

После пересоздания контейнера `getent hosts` вернул нужный IP.
Тестовый webhook создал событие с фиктивным коммитом `0000000000` —
это не проверка сборки. Приёмка выполнена настоящим пустым коммитом и push:
новый pipeline запустился автоматически и завершился успешно.

## Инцидент 2 — сборка заполнила корневой раздел VM103

**Симптом:** Hugo внутри Docker build завершился с ошибкой:

```text
Error copying static files: write /out/images/p9.jpg: no space left on device
```

**Диагностика на VM103:**

```bash
df -h
df -i
docker system df
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
sudo vgs
sudo lvs
```

Корневой раздел заполнен на 100%, inode заняты лишь на 30%.
Виртуальный диск — 20 GiB, корневой LV — 10 GiB, внутри VG свободны 8.22 GiB.
Проблема решалась расширением существующего LV, без увеличения диска в Proxmox
и без удаления Docker volumes.

**Фикс после проверки свободного места в VG:**

```bash
sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
df -h /
```

LV вырос до 18.22 GiB, ext4 расширена online. Проверка показала 7.5 GiB
свободного места. Повторный запуск того же pipeline завершил build и push.

## Шаг 3 — развёртывание через ArgoCD

Проверены три Ready-ноды и компоненты ArgoCD. Pi5 — `arm64`, оба воркера —
`amd64`; образ собран на VM103 под `amd64`. В Deployment задан
`nodeSelector: kubernetes.io/arch: amd64`.

Подготовлены namespace `land` и Secret `registry-credentials` типа
`kubernetes.io/dockerconfigjson`. Secret создавался отдельно от Git;
Deployment ссылается на него через `imagePullSecrets`.

| Параметр | Значение |
|---|---|
| Repository | `Igor/land` в Gitea |
| Revision / Path | `main` / `deploy` |
| ArgoCD Project / Application | `default` / `land` |
| Destination | текущий кластер, namespace `land` |
| Sync | Manual |
| Deployment | одна реплика, HTTP readiness probe на `/`, порт 80 |
| Resources | requests `50m` CPU / `32Mi`; limits `500m` / `128Mi` |
| Service | ClusterIP, порт 80, selector `app: land` |

ArgoCD прочитал коммит манифестов и показал `Missing` / `OutOfSync`:
объекты были описаны в Git, но отсутствовали в кластере. После Sync созданы
Deployment и Service. Первый pod не смог скачать образ из-за DNS воркера.

## Инцидент 3 — запись на роутере есть, но воркер не разрешает Registry

**Симптом:** pod на `k3-worker-2` перешёл в `ImagePullBackOff`.
Events содержали конкретную причину:

```text
Head https://registry.homelab.local:5000/v2/land/manifests/<tag>:
dial tcp: lookup registry.homelab.local: Try again
```

**Диагностика на `k3-worker-2`:**

```bash
getent hosts registry.homelab.local
resolvectl status
resolvectl query registry.homelab.local
dig @192.168.1.1 registry.homelab.local A
```

`getent` не вернул адрес; `resolvectl query` сообщил
`No appropriate name servers or networks for name found`.
При этом прямой запрос роутеру вернул `192.168.1.10`.

**Root cause:** DNS-запись была исправна. `systemd-resolved` не направлял
запросы зоны `.local` обычному DNS без явно заданной routing domain;
mDNS был отключён. Проверка DNS с другого хоста не выявляла эту проблему.

**Временный фикс и проверка гипотезы:**

```bash
sudo resolvectl domain enp2s0 '~homelab.local'
resolvectl query registry.homelab.local
getent hosts registry.homelab.local
```

Обе проверки получили `192.168.1.10`.

**Постоянная конфигурация:** интерфейс управляется Netplan через networkd.
В `/etc/netplan/60-homelab-dns.yaml` добавлено:

```yaml
network:
  version: 2
  ethernets:
    enp2s0:
      nameservers:
        search:
          - "~homelab.local"
```

```bash
sudo chmod 600 /etc/netplan/60-homelab-dns.yaml
sudo netplan generate
sudo netplan get ethernets.enp2s0
```

В объединённой конфигурации сохранились IP, шлюз и DNS роутера, появилась
routing domain. Активное правило установлено через `resolvectl`;
повторное применение networkd и проверка после перезагрузки не выполнялись.

Неработающий pod пересоздан. Новый pod на том же воркере получил образ и стал
`1/1 Running`. Запрос через ClusterIP сервиса вернул HTTP 200 и заголовок сайта.

## Шаг 4 — доставка изменения текста

В `site/config.toml` изменён заголовок страницы. Первая попытка сборки упала:
вместо `CI/CD` было записано `CI\CD`. TOML интерпретировал обратный слеш как
начало escape-последовательности и отверг `\C`.

**Проверка:** `sed -n '3p' site/config.toml` показала ошибочную строку.
После исправления pipeline №8 собрал и отправил образ с тегом:

```text
cee7e25dc06e319b248c8deee38554c4564fec19
```

Этот тег указан в `deploy/deployment.yaml`, изменение отправлено отдельным
коммитом с `[skip ci]`, затем выполнен Sync ArgoCD.

**Проверка на Pi5:**

```bash
kubectl -n land rollout status deployment/land --timeout=120s
kubectl -n land get pods -o wide
# На момент проверки Service имел ClusterIP 10.43.228.65
curl -sS http://10.43.228.65/ | grep -o '<title>[^<]*</title>'
```

Результат:

```text
deployment "land" successfully rolled out
land-d785c778b-86774   1/1   Running   0   ...   k3-worker-2
<title>Devops quiz - обновлено через CI/CD</title>
```

Так проверена не только успешность CI, но и выдача новой версии из кластера.

## Шаг 5 — несуществующий тег и возврат через Git

В Deployment намеренно указан `land:does-not-exist-test`.
Изменение сохранено отдельным коммитом и применено через ArgoCD.

```bash
kubectl -n land get pods -o wide
kubectl -n land describe pod -l app=land
```

Новый pod получил `ErrImagePull`, затем `ImagePullBackOff`.
В Events — `NotFound` / `not found` для указанного тега.
В отличие от предыдущего инцидента, имя Registry разрешалось и ответ пришёл
от Registry: отсутствовал именно образ с запрошенным тегом.

Старая реплика осталась `1/1 Running`. Deployment с одной репликой и
стандартным RollingUpdate допускает дополнительный pod при обновлении,
но сохраняет доступную реплику, пока новый pod не готов.

**Откат — через историю Git, не через `kubectl rollout undo`:**

```bash
git revert --no-commit 02a363186940055f95cb8afecb02e3c5e99c25fe
git diff --cached -- deploy/deployment.yaml
git commit -m "Restore working land image [skip ci]"
git push
```

После проверки возврата рабочего тега выполнен Sync ArgoCD.
Повторены rollout status, список pod и HTTP-запрос.

**Результат:** `successfully rolled out`; ошибочный pod исчез;
старый рабочий `land-d785c778b-86774` сохранился и отдавал новый заголовок.
Возврат желаемого состояния не потребовал пересоздавать уже подходящий pod.

## Итог

- Реальный push запускает CI, образ собирается и публикуется с тегом Git SHA.
- ArgoCD применяет манифесты из того же приватного репозитория.
- Изменение текста подтверждено HTTP-ответом сервиса после rollout.
- Намеренная ошибка тега диагностирована по Events, рабочая версия возвращена через Git.
- Во время неудачного обновления старая Ready-реплика сохранилась.
  Непрерывная доступность HTTP отдельным мониторингом не измерялась.
