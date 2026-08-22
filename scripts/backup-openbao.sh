#!/bin/bash
# backup-openbao.sh
# Снимает Raft snapshot OpenBao и заливает его (вместе с checksum) в MinIO bucket backups/openbao/
#
# Запускать на VM104 (openbao), где установлен bao CLI и настроен mc (MinIO client)
# Требует: переменная окружения BAO_TOKEN с правами на snapshot, либо запуск из-под root/уже авторизованной сессии
#
# Перед первым запуском настрой mc alias:
#   mc alias set homelab http://<MINIO_HOST>:<API_PORT> <ACCESS_KEY> <SECRET_KEY>
# Важно: уточни реальный API-порт MinIO через `docker ps` — он может отличаться
# от дефолтного 9000, если MinIO запущен в Docker с нестандартным маппингом портов.

set -euo pipefail

# TLS отключен в конфиге OpenBao (tls_disable = true), поэтому явно говорим
# CLI использовать HTTP, иначе bao по умолчанию пытается HTTPS и падает с ошибкой
export BAO_ADDR="http://127.0.0.1:8200"

DATE=$(date +%F_%H%M%S)
SNAPSHOT_DIR="/tmp/openbao-snapshots"
SNAPSHOT_FILE="${SNAPSHOT_DIR}/openbao-snapshot-${DATE}.snap"
CHECKSUM_FILE="${SNAPSHOT_FILE}.sha256"
MINIO_ALIAS="homelab"  # имя алиаса в mc config, см. примечание ниже
MINIO_BUCKET="backups/openbao"

# Retention: сколько хранить локальные snapshot на VM104 и копии в самом MinIO.
# Локально держим меньше — это просто буфер перед загрузкой, не источник правды.
# В MinIO держим дольше — это и есть фактическое хранилище бэкапов до offsite-копии.
RETENTION_DAYS_LOCAL=7
RETENTION_DAYS_REMOTE=30

# Куда пишем статус последнего запуска — простой машинно-читаемый файл,
# чтобы можно было опереться на него при переходе на запуск по расписанию
# (cron не покажет тебе упавший запуск сам по себе). Формат нарочно плоский
# (key=value построчно), чтобы его легко было распарсить хоть в node_exporter
# textfile collector, хоть в простом мониторящем скрипте, хоть руками через cat.
STATUS_DIR="/var/log/homelab-backups"
STATUS_FILE="${STATUS_DIR}/openbao.status"

mkdir -p "${SNAPSHOT_DIR}" "${STATUS_DIR}"

write_status() {
    # $1 = OK|FAIL, $2 = произвольная деталь
    local result="$1"
    local detail="$2"
    {
        printf 'timestamp=%s\n' "$(date -Iseconds)"
        printf 'result=%s\n' "${result}"
        printf 'detail=%s\n' "${detail}"
    } > "${STATUS_FILE}"
}

# Если что-то упадёт неожиданно (а не через наш явный exit 1 с сообщением),
# ERR trap всё равно оставит машинно-читаемый след падения в STATUS_FILE.
trap 'write_status "FAIL" "скрипт прерван на строке ${LINENO}"' ERR

echo "[1/5] Снимаю Raft snapshot..."
bao operator raft snapshot save "${SNAPSHOT_FILE}"

if [ ! -s "${SNAPSHOT_FILE}" ]; then
    write_status "FAIL" "snapshot файл пустой или не создан: ${SNAPSHOT_FILE}"
    echo "ОШИБКА: snapshot файл пустой или не создан" >&2
    exit 1
fi

echo "[2/5] Snapshot создан: ${SNAPSHOT_FILE} ($(du -h "${SNAPSHOT_FILE}" | cut -f1))"

echo "[3/5] Считаю checksum..."
# sha256sum пишет "хэш  имя_файла" — берём только хэш, чтобы при restore можно
# было переименовать файл и всё равно проверить его командой:
#   sha256sum -c openbao-snapshot-*.snap.sha256
sha256sum "${SNAPSHOT_FILE}" | awk '{print $1}' > "${CHECKSUM_FILE}"
echo "    checksum: $(cat "${CHECKSUM_FILE}")"

echo "[4/5] Загружаю snapshot и checksum в MinIO (${MINIO_ALIAS}/${MINIO_BUCKET})..."
mc cp "${SNAPSHOT_FILE}" "${MINIO_ALIAS}/${MINIO_BUCKET}/"
mc cp "${CHECKSUM_FILE}" "${MINIO_ALIAS}/${MINIO_BUCKET}/"

echo "[5/5] Retention..."
# Локальные файлы старше RETENTION_DAYS_LOCAL дней — это просто буфер, чистим агрессивнее
find "${SNAPSHOT_DIR}" -name "openbao-snapshot-*.snap" -mtime "+${RETENTION_DAYS_LOCAL}" -delete
find "${SNAPSHOT_DIR}" -name "openbao-snapshot-*.snap.sha256" -mtime "+${RETENTION_DAYS_LOCAL}" -delete

# Копии в самом MinIO бакете — без этого они копились бы там бесконечно.
# Не даём сбою retention завалить весь скрипт через set -e/ERR trap: сам бэкап
# уже успешно загружен, поэтому пишем предупреждение, а не FAIL.
if ! mc rm --recursive --force --older-than "${RETENTION_DAYS_REMOTE}d" "${MINIO_ALIAS}/${MINIO_BUCKET}/"; then
    echo "ПРЕДУПРЕЖДЕНИЕ: не удалось прочистить старые копии в ${MINIO_BUCKET} (retention) — сам бэкап это не отменяет, но стоит проверить вручную" >&2
fi

write_status "OK" "snapshot $(basename "${SNAPSHOT_FILE}"), checksum $(cat "${CHECKSUM_FILE}"), bucket ${MINIO_BUCKET}"
echo "Готово. Snapshot загружен в MinIO: ${MINIO_BUCKET}/$(basename "${SNAPSHOT_FILE}")"
