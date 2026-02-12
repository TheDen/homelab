#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

SRC="/mnt/ssd"
DEST_ROOT="/mnt/Backup/thinkcentre"
HOSTNAME_SHORT="$(hostname -s)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
DEST_DIR="${DEST_ROOT}/${HOSTNAME_SHORT}"
ARCHIVE_NAME="ssd-${HOSTNAME_SHORT}-${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="${DEST_DIR}/${ARCHIVE_NAME}"

echo "Source:      ${SRC}"
echo "Destination: ${ARCHIVE_PATH}"
echo

if [ ! -d "${SRC}" ]; then
  echo "ERROR: Source directory '${SRC}' does not exist." >&2
  exit 1
fi

mkdir -p "${DEST_DIR}"

# Choose compressor: pigz if available, otherwise gzip -1
if command -v pigz > /dev/null 2>&1; then
  COMPRESSOR="pigz -1"
  echo "Using pigz (parallel gzip) for compression..."
else
  COMPRESSOR="gzip -1"
  echo "pigz not found, using gzip -1..."
fi

echo "=== Creating compressed tar archive ==="

tar --acls \
  --xattrs --xattrs-include='*' \
  --selinux \
  --numeric-owner \
  --one-file-system \
  -cpf - \
  -C "${SRC}" . |
  ${COMPRESSOR} > "${ARCHIVE_PATH}"

echo
echo "Backup complete:"
echo "${ARCHIVE_PATH}"
