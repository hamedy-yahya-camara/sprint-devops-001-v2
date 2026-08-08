#!/usr/bin/env bash
# Durcissement de mon serveur — défi-001, Promo 001
# Usage : sudo bash durcir.sh
set -euo pipefail

echo "== 1. Le pare-feu, dans le bon ordre =="
sudo apt install -y ufw
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw --force enable
sudo ufw status verbose

echo "== 2. SSH, mot de passe et root =="
sudo sed -i -E 's/^#?\s*PasswordAuthentication\s+.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i -E 's/^#?\s*PermitRootLogin\s+.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl reload ssh

echo "== 3. Les mises à jour =="
sudo apt update
sudo apt upgrade -y

echo "== 4. Vérification finale =="
curl -I http://localhost
echo "Durcissement terminé."
