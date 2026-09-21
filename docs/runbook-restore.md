# Restore Runbook

Пошаговая процедура восстановления критичных данных homelab: MinIO (object storage, включая Terraform state) и OpenBao (секреты).

Обе процедуры проверены реальными прогонами: OpenBao — 02–03.07.2026; MinIO в текущем объектном формате — 21.09.2026 на свежем production-бэкапе. Рабочие сервисы не использовались как цели восстановления.

Цель документа: восстановление должно быть повторяемо без героизма — уставшим человеком, по шагам, с проверкой результата после каждого шага.

**Когда применять:** потеря данных MinIO/OpenBao — отказ SD-карты или диска Pi5, выход из строя VM104, случайное удаление, повреждение данных.

---

## Перед стартом — общие правила

1. **Найди самый свежий архив и его checksum:**

   ```bash
   mc ls homelab/backups/minio-self/                     # если production MinIO доступен
   export OFFSITE_BACKUP_DIR='/путь/к/offsite-копии'
   find "${OFFSITE_BACKUP_DIR}" -path '*/backups/minio-self/*' -type f
   ```

   Данные в архиве соответствуют моменту снятия backup. Всё, что менялось
   после, при restore теряется — прими это решение осознанно до начала.

2. **Скопируй архив в рабочий каталог и проверь checksum до распаковки.**
   Файл `.sha256` содержит только hash, без имени файла:

   ```bash
   export ARCHIVE='minio-backup-YYYY-MM-DD_HHMMSS.tar.gz'
   mkdir -p ~/minio-restore-lab/{archive,source,minio-data}
   mc cp "homelab/backups/minio-self/${ARCHIVE}" ~/minio-restore-lab/archive/
   mc cp "homelab/backups/minio-self/${ARCHIVE}.sha256" ~/minio-restore-lab/archive/

   expected=$(tr -d '[:space:]' < "$HOME/minio-restore-lab/archive/${ARCHIVE}.sha256")
   actual=$(sha256sum "$HOME/minio-restore-lab/archive/${ARCHIVE}" | awk '{print $1}')
   test "${actual}" = "${expected}" && echo "checksum OK"
   ```

   Если production MinIO недоступен, скопируй оба файла из offsite-копии,
   затем выполни ту же проверку.

3. **Проверь структуру и распакуй архив:**

   ```bash
   tar -tzf "$HOME/minio-restore-lab/archive/${ARCHIVE}"
   tar -xzf "$HOME/minio-restore-lab/archive/${ARCHIVE}" \
     -C ~/minio-restore-lab/source
   ```

   Ожидаемо — логическая структура `<бакет>/<объект>`, например:

   ```
   ./terraform-state/homelab/terraform.tfstate
   ```

   В архиве не должно быть `.minio.sys` и `xl.meta`: это признаки старого
   сырого формата. Текущий архив содержит объекты, снятые через S3 API.

4. **OpenBao snapshot хранится отдельно.** `backup-minio.sh` исключает весь
   bucket `backups`, чтобы не архивировать backup внутри backup. Для полного
   восстановления нужны два набора: `backups/minio-self/` и
   `backups/openbao/` из MinIO либо offsite-копии.

5. **Ключи — до начала, не после.** Restore OpenBao без продовых
   unseal-ключей и root token НЕВОЗМОЖЕН: снапшот зашифрован продовой
   печатью, сам бэкап ключей не содержит и не заменяет.
   Где лежат: полный комплект (5 unseal-ключей + Initial Root Token) —
   в менеджере паролей; три ключа — в `/usr/local/bin/openbao-unseal.sh`
   на VM104 (auto-unseal, threshold 3 из 5).

6. **Хосты.** Проверочный restore выполняется на отдельном хосте, не на Pi5.
   Проверенный 21.09.2026 вариант — VM103 (`clai@woodpecker`), loopback-порты
   `19000/19001`, лимиты 1 CPU / 512 MiB. Перед каждой командой смотри на
   prompt: production и test должны оставаться разными целями.

7. **Рабочий каталог — в `~`, не в `/tmp`.** `/tmp` очищается при
   перезагрузке: тест, растянувшийся на два дня, теряет данные, снапшот
   и контейнер остаётся без начинки.

---

## Часть 1 — Restore MinIO

Текущий backup — логический export через S3 API (`mc mirror`). Он содержит
`<bucket>/<object>`, но не внутреннее хранилище MinIO. Поэтому архив нельзя
распаковать прямо в `/data`. Правильный restore: пустой MinIO создаёт свою
служебную структуру, затем бакеты и объекты возвращаются через S3 API.

### Вариант A — проверочный restore (проверен 21.09.2026)

Регулярная проверка бэкапов. Прод не затрагивает.

1. Узнать production-версию MinIO и выбрать доверенный образ с точным тегом:

   ```bash
   docker exec minio minio --version                    # на Pi5, только чтение
   export MINIO_IMAGE='quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z'
   export MC_IMAGE='quay.io/minio/mc:RELEASE.2025-08-13T08-35-41Z'
   ```

   Эти версии использованы в прогоне 21.09.2026 и совпадают с production
   server/client на дату проверки. Перед будущим тестом снова сверить версии.
   Не использовать плавающий `latest`; доступность и источник образа проверить.

2. Запустить пустой тестовый MinIO на loopback-портах:

   ```bash
   export RESTORE_PASSWORD="$(openssl rand -hex 16)"
   docker run -d --name minio-restore-test \
     --restart=no --cpus=1 --memory=512m \
     -p 127.0.0.1:19000:9000 -p 127.0.0.1:19001:9001 \
     -e MINIO_ROOT_USER=restoreadmin \
     -e MINIO_ROOT_PASSWORD="${RESTORE_PASSWORD}" \
     -v "$HOME/minio-restore-lab/minio-data:/data" \
     "${MINIO_IMAGE}" server /data --console-address ':9001'

   docker ps --filter 'name=minio-restore-test' \
     --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
   ```

   Ожидаемо: контейнер `Up`, оба порта привязаны только к `127.0.0.1`.
   Production credentials тестовому инстансу не передаются.

3. Для каждого каталога верхнего уровня создать одноимённый bucket и вернуть
   его содержимое. Пример для `terraform-state`:

   ```bash
   docker run --rm --network host \
     -e "MC_HOST_test=http://restoreadmin:${RESTORE_PASSWORD}@127.0.0.1:19000" \
     "${MC_IMAGE}" mb --ignore-existing test/terraform-state

   docker run --rm --network host \
     -e "MC_HOST_test=http://restoreadmin:${RESTORE_PASSWORD}@127.0.0.1:19000" \
     -v "$HOME/minio-restore-lab/source/terraform-state:/restore:ro" \
     "${MC_IMAGE}" mirror --overwrite /restore test/terraform-state
   ```

   Повторить для остальных bucket-каталогов из архива. Исходные каталоги
   монтируются read-only.

4. Проверить объект, не выводя содержимое Terraform state:

   ```bash
   source_hash=$(sha256sum \
     ~/minio-restore-lab/source/terraform-state/homelab/terraform.tfstate | awk '{print $1}')

   restored_hash=$(docker run --rm --network host \
     -e "MC_HOST_test=http://restoreadmin:${RESTORE_PASSWORD}@127.0.0.1:19000" \
     "${MC_IMAGE}" cat test/terraform-state/homelab/terraform.tfstate | \
     sha256sum | awk '{print $1}')

   test "${source_hash}" = "${restored_hash}" && echo "object hash OK"
   python3 -m json.tool \
     ~/minio-restore-lab/source/terraform-state/homelab/terraform.tfstate \
     >/dev/null && echo "JSON valid"
   ```

   В проверенном прогоне оба SHA-256 равны
   `b5f29ef1efe2eb683be3d7bb4c6e5bbe08abf6b4af6301ea4d76149e9f48d23a`.

5. Уборка после фиксации результата:

   ```bash
   docker rm -f minio-restore-test
   unset RESTORE_PASSWORD MINIO_IMAGE MC_IMAGE ARCHIVE OFFSITE_BACKUP_DIR
   docker ps -a --filter 'name=minio-restore-test'
   # После проверки, что доказательства больше не нужны:
   rm -rf ~/minio-restore-lab
   ```

### Вариант B — аварийный restore (процедура задокументирована, на реальном отказе не прогонялась)

Текущий архив не является копией `/mnt/minio`, поэтому распаковывать его прямо
в production data directory нельзя.

1. Зафиксировать причину отказа и выбрать точку восстановления по дате.
2. Сохранить повреждённый data directory в стороне; не удалять до завершения
   проверки и принятия нового состояния.
3. Поднять новый пустой MinIO совместимой фиксированной версии с production
   TLS и отдельным пустым data directory.
4. Выполнить шаги Варианта A: checksum → распаковка → создание bucket →
   `mc mirror` через S3 API.
5. Проверить список и hash критичных объектов, затем доступ Terraform backend
   и остальных клиентов.
6. Только после проверки переключить клиентов/DNS на восстановленный MinIO.
   Rollback — вернуть прежний endpoint и сохранённый data directory.

Аварийное переключение production не проверялось; выполняющий должен заранее
уточнить актуальный compose, TLS paths, UID/GID и endpoint на Pi5.

---

## Часть 2 — Restore OpenBao

Снапшот OpenBao — Raft snapshot (`bao operator raft snapshot save`),
восстанавливается штатным `bao operator raft snapshot restore`.

Откуда взять снапшот:
- бакет `backups/openbao/`, только если исходный MinIO ещё доступен;
- из отдельной offsite-копии `backups/openbao/` (MinIO self-backup намеренно
  не включает bucket `backups`);
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

### Вариант B — аварийный restore (процедура задокументирована, на реальном отказе не прогонялась)

Сценарий: VM104 умерла.

1. Пересоздать VM104 через Terraform (`terraform apply` — VM описана в vms.tf).
2. Установить OpenBao, поднять пустой инстанс с raft-хранилищем, init.
3. Snapshot restore (шаги 4–5 Варианта A, адаптировать пути под systemd-установку).
4. Restart сервиса, unseal продовыми ключами из менеджера паролей.
5. Восстановить `/usr/local/bin/openbao-unseal.sh` и unit auto-unseal.
6. Проверить Kubernetes auth: Vault Agent Injector доставляет секреты в поды
   (перезапустить тестовый pod).

---

## Критерии успеха

**MinIO восстановлен:**
- `mc ls` показывает все непустые бакеты, присутствовавшие в self-backup
  (в проверенном архиве — `terraform-state`; bucket `backups` намеренно исключён);
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
| `apt install mc` предлагает пакет, но MinIO-команды не работают | в Ubuntu пакет `mc` — Midnight Commander, не MinIO Client | использовать официальный MinIO Client или его контейнер |
| `pull access denied for minio/minio` | исторический образ недоступен по старому адресу Docker Hub | использовать проверенный официальный источник и точный тег; 21.09.2026 сработал `quay.io/minio/*` |
| после монтирования распакованного архива как `/data` бакеты не видны | текущий архив — логические объекты, а не внутреннее хранилище MinIO | поднять пустой MinIO, создать bucket и загрузить объекты через `mc mirror` |
| `bao operator generate-root` → `405 unsupported operation` | НЕ УСТАНОВЛЕНА (инстанс active, unsealed; по документации должно работать) | открытый вопрос; обходной путь — продовый root token из менеджера паролей |

## Известные ограничения

- Restore возвращает данные на момент снятия backup.
- Расписания backup нет: свежесть архива = дисциплина ручных запусков.
- Аварийный сценарий (Вариант B) задокументирован, но на реальном отказе
  не прогонялся; изолированный restore (Вариант A) — единственная часть,
  реально проверенная, сохранён как безопасная регулярная проверка.
- Restore OpenBao невозможен без продовых ключей: комплект должен
  существовать вне VM104, под отдельным управлением ключами.
