#!/usr/bin/env bash
# Copies config files to the Pi and runs the installer via SSH.
# Usage: ./deploy.sh [user@host]   (default: jdn@pihole.local)
set -euo pipefail

TARGET="${1:-jdn@pihole.local}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_DIR="~/raspihole-setup"

echo "Deploying to ${TARGET}:${REMOTE_DIR} ..."

ssh "${TARGET}" "mkdir -p ${REMOTE_DIR}"
scp -r \
    "${REPO_DIR}/etc" \
    "${REPO_DIR}/install.sh" \
    "${TARGET}:${REMOTE_DIR}/"

echo "Files copied. Running install.sh on ${TARGET} ..."
ssh -t "${TARGET}" "sudo bash ${REMOTE_DIR}/install.sh"
