#!/bin/bash
# backup-minio.sh
# Снимает бэкап всех bucket'ов MinIO (включая terraform-state) ЧЕРЕЗ S3 API (mc mirror),
# а не сырым чтением файлов с диска — так же, как backup-openbao.sh использует
# встроенный snapshot-механизм OpenBao вместо копирования файлов Raft-журнала.
# Архив кладётся в отдельный backup-bucket, чтобы потом забрать на ноут через mc/offsite-fetch.
#
# Запускать на Pi5, где установлен MinIO client (mc) и настроен alias на локальный MinIO

set -euo pipefail

DATE=$(date +%F_%H%M%S)
ARCHIVE_DIR="/tmp/minio-backups"
STAGE_DIR="${ARCHIVE_DIR}/stage-${DATE}"
ARCHIVE_FILE="${ARCHIVE_DIR}/minio-backup-${DATE}.tar.gz"
CHECKSUM_FILE="${ARCHIVE_FILE}.sha256"
MINIO_ALIAS="homelab"          # имя алиаса в mc config
BACKUP_BUCKET="backups/minio-self"
BACKUP_BUCKET_ROOT="${BACKUP_BUCKET%%/*}"   # "backups" — этот бакет исключаем из mirror,
                                             # чтобы не архивировать бэкапы бэкапом (рекурсия)

RETENTION_DAYS_LOCAL=7
RETENTION_DAYS_REMOTE=30

STATUS_DIR="/var/log/homelab-backups"
STATUS_FILE="${STATUS_DIR}/minio.status"

mkdir -p "${ARCHIVE_DIR}" "${STAGE_DIR}" "${STATUS_DIR}"

write_status() {
    local result="$1"
    local detail="$2"
    {
        printf 'timestamp=%s\n' "$(date -Iseconds)"
        printf 'result=%s\n' "${result}"
        printf 'detail=%s\n' "${detail}"
    } > "${STATUS_FILE}"
}

cleanup_stage() {
    rm -rf "${STAGE_DIR}"
}
trap 'cleanup_stage; write_status "FAIL" "скрипт прерван на строке ${LINENO}"' ERR

echo "[1/6] Определяю список бакетов через API..."
# mc ls в текстовом режиме выводит имена бакетов последним полем с завершающим "/"
BUCKETS=$(mc ls "${MINIO_ALIAS}" | awk '{print $NF}' | sed 's#/$##')

if [ -z "${BUCKETS}" ]; then
    write_status "FAIL" "mc ls ${MINIO_ALIAS} не вернул ни одного бакета"
    echo "ОШИБКА: не удалось получить список бакетов из ${MINIO_ALIAS}" >&2
    exit 1
fi

echo "[2/6] Снимаю данные через mc mirror (consistent read через S3 API, не сырые файлы с диска)..."
for bucket in ${BUCKETS}; do
    if [ "${bucket}" = "${BACKUP_BUCKET_ROOT}" ]; then
        echo "    пропускаю ${bucket} (сам backup-бакет)"
        continue
    fi
    echo "    mirror ${bucket}..."
    mc mirror --quiet --preserve "${MINIO_ALIAS}/${bucket}" "${STAGE_DIR}/${bucket}"
done

echo "[3/6] Архивирую снятые данные..."
tar czf "${ARCHIVE_FILE}" -C "${STAGE_DIR}" .
cleanup_stage

if [ ! -s "${ARCHIVE_FILE}" ]; then
    write_status "FAIL" "архив пустой или не создан: ${ARCHIVE_FILE}"
    echo "ОШИБКА: архив пустой или не создан" >&2
    exit 1
fi

echo "[4/6] Архив создан: ${ARCHIVE_FILE} ($(du -h "${ARCHIVE_FILE}" | cut -f1))"

echo "[5/6] Считаю checksum и загружаю архив + checksum в bucket ${BACKUP_BUCKET}..."
sha256sum "${ARCHIVE_FILE}" | awk '{print $1}' > "${CHECKSUM_FILE}"
echo "    checksum: $(cat "${CHECKSUM_FILE}")"
mc cp "${ARCHIVE_FILE}" "${MINIO_ALIAS}/${BACKUP_BUCKET}/"
mc cp "${CHECKSUM_FILE}" "${MINIO_ALIAS}/${BACKUP_BUCKET}/"

echo "[6/6] Retention..."
find "${ARCHIVE_DIR}" -maxdepth 1 -name "minio-backup-*.tar.gz" -mtime "+${RETENTION_DAYS_LOCAL}" -delete
find "${ARCHIVE_DIR}" -maxdepth 1 -name "minio-backup-*.tar.gz.sha256" -mtime "+${RETENTION_DAYS_LOCAL}" -delete

if ! mc rm --recursive --force --older-than "${RETENTION_DAYS_REMOTE}d" "${MINIO_ALIAS}/${BACKUP_BUCKET}/"; then
    echo "ПРЕДУПРЕЖДЕНИЕ: не удалось прочистить старые копии в ${BACKUP_BUCKET} (retention) — сам бэкап это не отменяет, но стоит проверить вручную" >&2
fi

write_status "OK" "archive $(basename "${ARCHIVE_FILE}"), checksum $(cat "${CHECKSUM_FILE}"), bucket ${BACKUP_BUCKET}"
echo "Готово. Архив загружен: ${BACKUP_BUCKET}/$(basename "${ARCHIVE_FILE}")"
