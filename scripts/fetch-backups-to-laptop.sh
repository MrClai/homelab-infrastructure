#!/bin/bash
# fetch-backups-to-laptop.sh
# Запускать ВРУЧНУЮ на ноутбуке, когда хочешь обновить offsite-копию бэкапов.
# Скачивает все бэкапы (OpenBao snapshots + MinIO self-backup, включая checksum-файлы)
# из MinIO через mc mirror (S3 API) и проверяет checksum каждого скачанного файла.
#
# ПОЧЕМУ mc mirror, а не scp: раньше скрипт делал scp с пути на диске Pi5
# (/home/clai/homelab/backups), который физически не совпадал с тем, куда
# backup-скрипты реально кладут файлы (bucket "backups" внутри MinIO, чей
# физический путь на диске — MINIO_DATA_PATH из backup-minio.sh, т.е. /mnt/minio/...).
# mc mirror забирает файлы через тот же API, которым их туда и заливали —
# не нужно угадывать реальный путь на диске Pi5 и не нужен SSH-доступ вообще,
# достаточно mc alias с доверием к homelab-root-ca.crt (см. README).
#
# Требует: mc установлен на ноутбуке, alias настроен так же, как описано в README
#   mc alias set homelab https://<MINIO_HOST>:<API_PORT> <ACCESS_KEY> <SECRET_KEY>

set -euo pipefail

MINIO_ALIAS="homelab"
REMOTE_BUCKET="backups"   # тот же бакет, куда пишут backup-openbao.sh и backup-minio.sh
LOCAL_BACKUP_DIR="${HOME}/homelab-backups/$(date +%F)"

# Сколько хранить датированные папки на ноуте. Это offsite-копия — держим дольше,
# чем на самих серверах, но не бесконечно, иначе диск ноута тоже забьётся.
RETENTION_DAYS_LOCAL="${RETENTION_DAYS_LOCAL:-90}"

mkdir -p "${LOCAL_BACKUP_DIR}"

echo "Скачиваю бэкапы из ${MINIO_ALIAS}/${REMOTE_BUCKET} ..."
mc mirror --quiet --overwrite "${MINIO_ALIAS}/${REMOTE_BUCKET}" "${LOCAL_BACKUP_DIR}"

echo "Проверяю checksum скачанных файлов..."
VERIFY_FAILED=0
CHECKED=0
while IFS= read -r -d '' sumfile; do
    target="${sumfile%.sha256}"
    CHECKED=$((CHECKED + 1))
    if [ ! -f "${target}" ]; then
        echo "  WARN  $(basename "${sumfile}") — файл для проверки не найден: ${target}" >&2
        VERIFY_FAILED=1
        continue
    fi
    expected=$(cat "${sumfile}")
    actual=$(sha256sum "${target}" | awk '{print $1}')
    if [ "${expected}" = "${actual}" ]; then
        echo "  OK    $(basename "${target}")"
    else
        echo "  FAIL  $(basename "${target}") — checksum не совпадает (ожидался ${expected}, получен ${actual})" >&2
        VERIFY_FAILED=1
    fi
done < <(find "${LOCAL_BACKUP_DIR}" -name "*.sha256" -print0)

if [ "${CHECKED}" -eq 0 ]; then
    echo "ПРЕДУПРЕЖДЕНИЕ: не найдено ни одного .sha256 файла — проверить целостность нечем. Это ожидаемо только если backup-скрипты ещё не обновлены на генерацию checksum." >&2
fi

if [ "${VERIFY_FAILED}" -eq 1 ]; then
    echo "ВНИМАНИЕ: минимум один файл не прошёл проверку checksum — offsite-копия может быть повреждена или неполна." >&2
    exit 1
fi

echo "Чищу локальные датированные копии старше ${RETENTION_DAYS_LOCAL} дней..."
find "${HOME}/homelab-backups" -maxdepth 1 -mindepth 1 -type d -mtime "+${RETENTION_DAYS_LOCAL}" -exec rm -rf {} +

echo "Готово. Бэкапы сохранены локально: ${LOCAL_BACKUP_DIR}"
echo "Содержимое:"
find "${LOCAL_BACKUP_DIR}" -type f -exec du -h {} \;
