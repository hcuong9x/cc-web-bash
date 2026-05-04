#!/bin/bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <hostname>"
    echo "Example: $0 Host-Ram-IP"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root (or with sudo)."
    exit 1
fi

HOST_NAME="$1"
ZABBIX_SERVER="zabbix.cd-site.com"
ZABBIX_DEB="zabbix-release_latest_6.0+ubuntu22.04_all.deb"
ZABBIX_DEB_URL="https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/${ZABBIX_DEB}"
ZABBIX_CONF="/etc/zabbix/zabbix_agentd.conf"

echo "=========================================="
echo "Zabbix Agent Installation Script"
echo "Hostname: ${HOST_NAME}"
echo "Server:   ${ZABBIX_SERVER}"
echo "=========================================="

echo "[1/6] Downloading Zabbix release package..."
wget -O "${ZABBIX_DEB}" "${ZABBIX_DEB_URL}"

echo "[2/6] Installing Zabbix release package..."
dpkg -i "${ZABBIX_DEB}"

echo "[3/6] Updating apt cache..."
apt update

echo "[4/6] Installing zabbix-agent..."
DEBIAN_FRONTEND=noninteractive apt install -y zabbix-agent

echo "[5/6] Updating ${ZABBIX_CONF}..."
sed -i \
    -e "s/^Server=.*/Server=${ZABBIX_SERVER}/" \
    -e "s/^ServerActive=.*/ServerActive=${ZABBIX_SERVER}/" \
    -e "s/^Hostname=.*/Hostname=${HOST_NAME}/" \
    "${ZABBIX_CONF}"

echo "[6/6] Restarting and enabling zabbix-agent..."
systemctl restart zabbix-agent
systemctl enable zabbix-agent

echo "Done. zabbix-agent is installed and configured."
echo "Current hostname in config: ${HOST_NAME}"
