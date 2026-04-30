#!/usr/bin/env bash
# Copies config files to the Pi and runs the installer via SSH.
# Usage: ./deploy.sh [user@host]   (default: jdn@rpihole.local)
set -euo pipefail

TARGET="${1:-jdn@rpihole.local}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_DIR="~/raspihole-setup"

echo "Deploying to ${TARGET}:${REMOTE_DIR} ..."

ssh "${TARGET}" "mkdir -p ${REMOTE_DIR}"
scp -r \
    "${REPO_DIR}/etc" \
    "${REPO_DIR}/install.sh" \
    "${TARGET}:${REMOTE_DIR}/"

echo "Files copied. Running install.sh on ${TARGET} ..."
ssh_exit=0
ssh -t "${TARGET}" "sudo bash ${REMOTE_DIR}/install.sh" || ssh_exit=$?

if [ "$ssh_exit" -eq 255 ]; then
    echo ""
    echo "==> SSH disconnected (expected after static IP applied)."
    echo "==> Install continues on the Pi. Waiting to reconnect ..."
    sleep 8
    until ssh -o ConnectTimeout=5 -o BatchMode=yes "${TARGET}" true 2>/dev/null; do
        printf "."; sleep 3
    done
    echo " back online."
    echo "==> Tailing install log (Ctrl-C when you see the completion banner) ..."
    ssh "${TARGET}" "tail -f /var/log/raspihole-install.log"
elif [ "$ssh_exit" -ne 0 ]; then
    echo "Install failed (exit ${ssh_exit}). Check the Pi."
    exit "$ssh_exit"
fi
