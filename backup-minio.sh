#!/bin/bash
# backup-minio.sh
# Делает локальный архив всех bucket'ов MinIO (включая terraform-state) на Pi5
# и кладёт его в отдельный backup-bucket, чтобы потом забрать на ноут через scp.
#
# Запускать на Pi5, где установлен MinIO client (mc) и настроен alias на локальный MinIO

set -euo pipefail

DATE=$(date +%F_%H%M%S)
ARCHIVE_DIR="/tmp/minio-backups"
ARCHIVE_FILE="${ARCHIVE_DIR}/minio-backup-${DATE}.tar.gz"
MINIO_ALIAS="homelab"          # имя алиаса в mc config
MINIO_DATA_PATH="/mnt/minio"   # реальный путь к данным MinIO на диске Pi5
BACKUP_BUCKET="backups/minio-self"

mkdir -p "${ARCHIVE_DIR}"

echo "[1/3] Архивирую содержимое MinIO (${MINIO_DATA_PATH})..."
# lost+found — служебная директория ext4, не данные MinIO, исключаем
tar czf "${ARCHIVE_FILE}" -C "${MINIO_DATA_PATH}" --exclude='./lost+found' .

if [ ! -s "${ARCHIVE_FILE}" ]; then
    echo "ОШИБКА: архив пустой или не создан" >&2
    exit 1
fi

echo "[2/3] Архив создан: ${ARCHIVE_FILE} ($(du -h "${ARCHIVE_FILE}" | cut -f1))"

echo "[3/3] Загружаю архив в bucket ${BACKUP_BUCKET}..."
mc cp "${ARCHIVE_FILE}" "${MINIO_ALIAS}/${BACKUP_BUCKET}/"

# Чистим локальные архивы старше 7 дней
find "${ARCHIVE_DIR}" -name "minio-backup-*.tar.gz" -mtime +7 -delete

echo "Готово. Архив загружен: ${BACKUP_BUCKET}/$(basename "${ARCHIVE_FILE}")"
