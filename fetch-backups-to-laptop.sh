#!/bin/bash
# fetch-backups-to-laptop.sh
# Запускать ВРУЧНУЮ в WSL на ноутбуке, когда хочешь обновить offsite-копию бэкапов.
# Скачивает все бэкапы (OpenBao snapshots + MinIO self-backup) из MinIO на локальный диск.
#
# Примечание про WSL: $HOME по умолчанию указывает на домашнюю папку ВНУТРИ WSL
# (/home/<user>), а не на Windows-диск. Это нормально и достаточно для бэкапа —
# файлы физически лежат на том же SSD/диске ноутбука, просто в файловой системе WSL.
# Если хочешь видеть бэкапы из проводника Windows напрямую, замени LOCAL_BACKUP_DIR
# на путь вида /mnt/c/Users/<TvoeImya>/homelab-backups вместо ${HOME}/homelab-backups.

set -euo pipefail

PI5_HOST="${PI5_HOST:-user@pi5.homelab.local}"   # переопредели через переменную окружения
                                                   # или впиши свой реальный хост/IP перед запуском
REMOTE_BACKUP_PATH="/mnt/minio/backups"
LOCAL_BACKUP_DIR="${HOME}/homelab-backups/$(date +%F)"

mkdir -p "${LOCAL_BACKUP_DIR}"

echo "Скачиваю бэкапы с ${PI5_HOST}:${REMOTE_BACKUP_PATH} ..."
scp -r "${PI5_HOST}:${REMOTE_BACKUP_PATH}" "${LOCAL_BACKUP_DIR}/"

echo "Готово. Бэкапы сохранены локально: ${LOCAL_BACKUP_DIR}"
echo "Содержимое:"
find "${LOCAL_BACKUP_DIR}" -type f -exec du -h {} \;
