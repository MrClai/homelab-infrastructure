# Restore Runbook

Пошаговая процедура восстановления критичных данных homelab: MinIO (object storage, включая Terraform state) и OpenBao (секреты).

Обе процедуры проверены реальными прогонами: MinIO — 02.07.2026, OpenBao — 02–03.07.2026. Все команды в проверочных сценариях выполнялись дословно.

Цель документа: восстановление должно быть повторяемо без героизма — уставшим человеком, по шагам, с проверкой результата после каждого шага.

**Когда применять:** потеря данных MinIO/OpenBao — отказ SD-карты или диска Pi5, выход из строя VM104, случайное удаление, повреждение данных.

---

## Перед стартом — общие правила

1. **Найди самый свежий архив:**

   ```bash
   ls -lh ~/homelab/backups/minio-self/                 # на Pi5
   ls -lh ~/homelab-backups/*/backups/minio-self/       # offsite, WSL на ноутбуке
   ```

   Данные в архиве соответствуют моменту снятия backup. Всё, что менялось
   после, при restore теряется — прими это решение осознанно до начала.

2. **Проверь, что архив содержит данные бакетов, а не только служебные файлы:**

   ```bash
   tar -tzf <архив> | grep -v '.minio.sys'
   ```

   Ожидаемо — бакеты верхнего уровня, минимум:

   ```
   ./terraform-state/homelab/terraform.tfstate/xl.meta
   ./backups/openbao/openbao-snapshot-<дата>.snap/xl.meta
   ```

   Если этого нет — архив неполноценный: возьми более ранний и разберись
   с backup-скриптом ДО restore.

3. **Порядок backup имеет значение:** OpenBao-снапшот попадает внутрь
   MinIO-архива, только если `backup-minio.sh` запущен ПОСЛЕ
   `backup-openbao.sh`. Свежесть снапшота видна по его имени в выводе шага 2.

4. **Ключи — до начала, не после.** Restore OpenBao без продовых
   unseal-ключей и root token НЕВОЗМОЖЕН: снапшот зашифрован продовой
   печатью, сам бэкап ключей не содержит и не заменяет.
   Где лежат: полный комплект (5 unseal-ключей + Initial Root Token) —
   в менеджере паролей; три ключа — в `/usr/local/bin/openbao-unseal.sh`
   на VM104 (auto-unseal, threshold 3 из 5).

5. **Хосты.** Тестовые restore выполняются на Pi5 (`clai@homelab`), ключи
   живут на VM104 (`clai@openbao`). Перед каждой командой смотри на промпт —
   команда на «не том» хосте даёт ложные ошибки вида
   `No such container`.

6. **Рабочий каталог — в `~`, не в `/tmp`.** `/tmp` очищается при
   перезагрузке: тест, растянувшийся на два дня, теряет данные, снапшот
   и контейнер остаётся без начинки.

---

## Часть 1 — Restore MinIO

MinIO в single-node режиме хранит объекты как каталоги
`<bucket>/<object>/xl.meta` — данные мелких объектов лежат внутри `xl.meta`.
Restore = распаковка файлового дерева + запуск MinIO поверх него: сервер
сам читает `.minio.sys/` и поднимает бакеты.

### Вариант A — проверочный restore (проверен 02.07.2026)

Регулярная проверка бэкапов. Прод не затрагивает.

1. Распаковать архив в изолированный каталог (пути в архиве относительные,
   `-C` кладёт всё в указанный каталог):

   ```bash
   mkdir -p /tmp/minio-restore-test
   tar -xzf ~/homelab/backups/minio-self/<архив>.tar.gz -C /tmp/minio-restore-test
   ls -la /tmp/minio-restore-test
   ```

   Ожидаемо: `.minio.sys`, `terraform-state`, `backups`, `ci-artifacts`.
   (/tmp здесь допустим: тест MinIO занимает минуты, не дни.)

2. Тестовый MinIO на нестандартных портах:

   ```bash
   docker run -d --name minio-restore-test \
     -p 9500:9000 -p 9501:9001 \
     -v /tmp/minio-restore-test:/data \
     minio/minio server /data --console-address ":9001"
   docker logs minio-restore-test
   ```

   Ожидаемо: строки `API:` и `WebUI:` без фатальных ошибок.
   Предупреждение про `default credentials minioadmin:minioadmin` — норма:
   продовые креды тестовому инстансу не передаются, для чтения достаточно
   дефолтных.

3. Проверка, что объекты видны и читаются (`mc` встроен в образ):

   ```bash
   docker exec minio-restore-test mc alias set local http://127.0.0.1:9000 minioadmin minioadmin
   docker exec minio-restore-test mc ls --recursive local/
   docker exec minio-restore-test mc cat local/terraform-state/homelab/terraform.tfstate | head -20
   ```

   Ожидаемо: список объектов с размерами; `mc cat` выводит валидный JSON,
   начинающийся с `"version": 4` и `"terraform_version"`.

4. Уборка (обязательно):

   ```bash
   docker stop minio-restore-test && docker rm minio-restore-test
   rm -rf /tmp/minio-restore-test
   docker ps -a | grep minio    # тестового контейнера быть не должно
   ```

### Вариант B — аварийный restore (на реальном отказе НЕ прогонялся)

Прод MinIO: контейнер на Pi5, API на `:9002`, данные в `/mnt/minio`.

1. Остановить продовый контейнер (имя уточнить: `docker ps`):

   ```bash
   docker stop <прод-контейнер-minio>
   ```

2. Убрать повреждённые данные В СТОРОНУ, не удаляя:

   ```bash
   sudo mv /mnt/minio /mnt/minio.broken.$(date +%F)
   sudo mkdir -p /mnt/minio
   ```

3. Распаковать архив на продовое место и вернуть владельца
   (uid:gid сверить с `/mnt/minio.broken.*`):

   ```bash
   sudo tar -xzf <архив> -C /mnt/minio
   sudo chown -R <uid:gid> /mnt/minio
   ```

4. Запустить прод и проверить: `docker start`, `docker logs`,
   затем критерии успеха (ниже).

---

## Часть 2 — Restore OpenBao

Снапшот OpenBao — Raft snapshot (`bao operator raft snapshot save`),
восстанавливается штатным `bao operator raft snapshot restore`.

Откуда взять снапшот:
- бакет `backups/openbao/` в MinIO (если MinIO жив или восстановлен — Часть 1);
- изнутри offsite-архива MinIO: развернуть архив по Части 1 / Вариант A
  и вытащить: `mc cp local/backups/openbao/<снапшот>.snap ...`;
- `/tmp/openbao-snapshots/` на VM104 — НЕНАДЁЖНО: каталог эфемерный,
  пропадает при перезагрузке VM104.

### Ключевая механика (понять до начала)

Raft snapshot несёт всё состояние кластера, включая конфигурацию печати
(seal) и шифрование. После restore инстанс становится криптографической
копией прода:

- открывается только ПРОДОВЫМИ unseal-ключами (тестовые перестают подходить);
- продовый root token подходит к восстановленному инстансу;
- конфигурация печати перечитывается ТОЛЬКО при старте процесса —
  после restore обязателен restart, иначе unseal падает с
  `invalid key size 33`.

### Вариант A — проверочный restore (проверен 02–03.07.2026)

1. Подготовка: каталог в `~`, снапшот, файл с ключами:

   ```bash
   mkdir -p ~/openbao-restore-test/data
   mc cp homelab/backups/openbao/<снапшот>.snap ~/openbao-restore-test/
   scp clai@192.168.1.60:/usr/local/bin/openbao-unseal.sh ~/openbao-restore-test/unseal-src.sh
   ```

2. Конфиг сервера (dev-режим не годится — raft restore требует
   raft-хранилища):

   ```bash
   cat > ~/openbao-restore-test/config.hcl <<'EOF'
   ui = false
   disable_mlock = true
   listener "tcp" {
     address     = "0.0.0.0:8200"
     tls_disable = true
   }
   storage "raft" {
     path    = "/openbao/data"
     node_id = "restore-test"
   }
   api_addr     = "http://127.0.0.1:8200"
   cluster_addr = "http://127.0.0.1:8201"
   EOF
   ```

3. Права и запуск. `chown 100:100` — ДО запуска (контейнер работает от
   uid 100, иначе `permission denied` на `vault.db`). `--network none` —
   обязательно: снапшот приносит адреса продового кластера, и контейнер
   с доступом в LAN сам присоединяется к живому проду как standby-нода
   (проверено на собственном опыте 02.07). Порты наружу не нужны — всё
   через `docker exec`:

   ```bash
   sudo chown -R 100:100 ~/openbao-restore-test/data

   docker run -d --name openbao-restore-test --network none \
     -v ~/openbao-restore-test/config.hcl:/openbao/config/config.hcl \
     -v ~/openbao-restore-test/data:/openbao/data \
     openbao/openbao server -config=/openbao/config/config.hcl

   docker logs openbao-restore-test
   ```

   Ожидаемо: `OpenBao server started!`.
   `WARNING: ignoring duplicate configuration` — безобидно (образ сам
   подхватывает конфиг из каталога, а мы ещё и флагом указали).

4. Init и unseal ПУСТОГО инстанса (тестовые ключи, 1/1 — осознанное
   упрощение для одноразового теста). Unseal Key и Root Token из вывода —
   сохранить, понадобятся на шагах 5–6:

   ```bash
   docker exec -e BAO_ADDR=http://127.0.0.1:8200 openbao-restore-test \
     bao operator init -key-shares=1 -key-threshold=1

   docker exec -e BAO_ADDR=http://127.0.0.1:8200 openbao-restore-test \
     bao operator unseal ТЕСТОВЫЙ_UNSEAL_KEY
   ```

   Без unseal restore падает с `503 Vault is sealed`.
   Контроль: `bao status` → `Sealed: false`, Raft Committed Index
   маленький (~26–29) — это пустой инстанс, запомнить для сравнения.

5. Снапшот — внутрь смонтированного каталога, затем restore:

   ```bash
   sudo mv ~/openbao-restore-test/<снапшот>.snap ~/openbao-restore-test/data/snap
   sudo chown 100:100 ~/openbao-restore-test/data/snap

   docker exec -e BAO_ADDR=http://127.0.0.1:8200 -e BAO_TOKEN=ТЕСТОВЫЙ_ROOT_TOKEN \
     openbao-restore-test bao operator raft snapshot restore -force /openbao/data/snap
   ```

   `-force` обязателен (затираем состояние инстанса чужим снапшотом).
   Успех выглядит буднично: команда завершается молча, без слова error.

6. Restart и unseal ПРОДОВЫМИ ключами. Ключи не копировать руками —
   доставать из файла машиной (ручной копипаст даёт лишние байты и
   `invalid key size`):

   ```bash
   docker restart openbao-restore-test

   docker exec -e BAO_ADDR=http://127.0.0.1:8200 openbao-restore-test \
     bao operator unseal "$(grep "^KEY1=" ~/openbao-restore-test/unseal-src.sh | cut -d"'" -f2)"
   docker exec -e BAO_ADDR=http://127.0.0.1:8200 openbao-restore-test \
     bao operator unseal "$(grep "^KEY2=" ~/openbao-restore-test/unseal-src.sh | cut -d"'" -f2)"
   docker exec -e BAO_ADDR=http://127.0.0.1:8200 openbao-restore-test \
     bao operator unseal "$(grep "^KEY3=" ~/openbao-restore-test/unseal-src.sh | cut -d"'" -f2)"

   docker exec -e BAO_ADDR=http://127.0.0.1:8200 openbao-restore-test bao status
   ```

   Контрольные точки: `Total Shares: 5, Threshold: 3` (продовая печать),
   `Sealed: false`, Raft Committed Index — продовый (сотни, не десятки),
   `HA Mode: active` при `HA Cluster: 127.0.0.1` — лидер сам себе.

7. Финальная проверка — секреты читаются. Продовый root token положить
   в файл одной строкой (`printf '%s'` — без перевода строки) и подать
   через подстановку:

   ```bash
   printf '%s' 'ПРОДОВЫЙ_ROOT_TOKEN' > ~/openbao-restore-test/root-token

   docker exec -e BAO_ADDR=http://127.0.0.1:8200 \
     -e BAO_TOKEN="$(tr -d '[:space:]' < ~/openbao-restore-test/root-token)" \
     openbao-restore-test bao secrets list

   docker exec -e BAO_ADDR=http://127.0.0.1:8200 \
     -e BAO_TOKEN="$(tr -d '[:space:]' < ~/openbao-restore-test/root-token)" \
     openbao-restore-test bao kv list secret/
   ```

   Ожидаемо: таблица движков (`secret/ kv`, `kubernetes/`, `identity/`,
   `sys/`, `cubbyhole/`) и список секретов (grafana, minio, ...).
   Значения секретов выводить не нужно — имён достаточно.

8. Уборка — немедленно, секретам и ключам на Pi5 не жить:

   ```bash
   rm ~/openbao-restore-test/root-token ~/openbao-restore-test/unseal-src.sh
   docker stop openbao-restore-test && docker rm openbao-restore-test
   sudo rm -rf ~/openbao-restore-test
   docker ps -a | grep openbao    # тестового контейнера быть не должно
   ```

### Вариант B — аварийный restore (на реальном отказе НЕ прогонялся)

Сценарий: VM104 умерла.

1. Пересоздать VM104 через Terraform (`terraform apply` — VM описана в vms.tf).
2. Установить OpenBao, поднять пустой инстанс с raft-хранилищем, init.
3. Snapshot restore (шаги 4–5 Варианта A, адаптировать пути под systemd-установку).
4. Restart сервиса, unseal продовыми ключами из менеджера паролей.
5. Восстановить `/usr/local/bin/openbao-unseal.sh` и unit auto-unseal.
6. Проверить Kubernetes auth: Vault Agent Injector доставляет секреты в поды
   (перезапустить тестовый pod из задачи 6.4).

---

## Критерии успеха

**MinIO восстановлен:**
- `mc ls` показывает бакеты `terraform-state`, `backups`, `ci-artifacts`;
- `terraform.tfstate` читается и является валидным JSON;
- (аварийный сценарий) `terraform plan` из homelab-terraform отрабатывает
  без ошибок доступа к backend.

**OpenBao восстановлен:**
- `bao status`: Sealed false, продовая печать 5/3, продовый Committed Index;
- `bao secrets list` показывает продовые движки, `bao kv list secret/` —
  секреты;
- (аварийный сценарий) auto-unseal работает после перезагрузки VM104,
  Vault Agent Injector доставляет секреты в поды.

---

## Известные грабли (собраны на реальных прогонах)

| Симптом | Причина | Лечение |
|---|---|---|
| `permission denied ... vault.db` при старте контейнера | каталог данных принадлежит не uid 100 | `sudo chown -R 100:100 <data>` ДО запуска |
| `503 Vault is sealed` при restore | пропущен unseal тестовым ключом после init | unseal, потом restore |
| `400 invalid key size 33` при unseal продовым ключом | инстанс не перечитал продовую печать: конфигурация seal читается только при старте | `docker restart` после restore, потом unseal |
| лишний байт в ключе/токене при ручном копипасте | перевод строки / кавычка из буфера | не копировать руками: `grep|cut` из файла, `tr -d '[:space:]'`, `printf '%s'` |
| тестовый инстанс стал standby продового кластера | снапшот принёс адреса кластера, контейнер с LAN-доступом сам присоединился к проду | `--network none` при создании контейнера |
| данные теста исчезли после перезагрузки | рабочий каталог был в `/tmp` | многодневные тесты — в `~` |
| `No such container` | команда ушла в SSH-сессию другого хоста | смотреть на hostname в промпте |
| `bao operator generate-root` → `405 unsupported operation` | НЕ УСТАНОВЛЕНА (инстанс active, unsealed; по документации должно работать) | открытый вопрос; обходной путь — продовый root token из менеджера паролей |

## Известные ограничения

- Restore возвращает данные на момент снятия backup.
- Расписания backup нет: свежесть архива = дисциплина ручных запусков.
- Аварийные сценарии (Вариант B) для обоих сервисов на реальном отказе
  не прогонялись — проверены только изолированные restore данных.
- Restore OpenBao невозможен без продовых ключей: комплект должен
  существовать вне VM104 (см. задачу key management в roadmap).
