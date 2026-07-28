#!/bin/bash
# backup-openbao.sh
# Снимает Raft snapshot OpenBao и заливает его в MinIO bucket backups/openbao/
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
MINIO_ALIAS="homelab"  # имя алиаса в mc config, см. примечание ниже
MINIO_BUCKET="backups/openbao"

mkdir -p "${SNAPSHOT_DIR}"

echo "[1/3] Снимаю Raft snapshot..."
bao operator raft snapshot save "${SNAPSHOT_FILE}"

if [ ! -s "${SNAPSHOT_FILE}" ]; then
    echo "ОШИБКА: snapshot файл пустой или не создан" >&2
    exit 1
fi

echo "[2/3] Snapshot создан: ${SNAPSHOT_FILE} ($(du -h "${SNAPSHOT_FILE}" | cut -f1))"

echo "[3/3] Загружаю в MinIO (${MINIO_ALIAS}/${MINIO_BUCKET})..."
mc cp "${SNAPSHOT_FILE}" "${MINIO_ALIAS}/${MINIO_BUCKET}/"

# Чистим локальные snapshot старше 7 дней, чтобы не копить мусор на VM104
find "${SNAPSHOT_DIR}" -name "openbao-snapshot-*.snap" -mtime +7 -delete

echo "Готово. Snapshot загружен в MinIO: ${MINIO_BUCKET}/$(basename "${SNAPSHOT_FILE}")"
