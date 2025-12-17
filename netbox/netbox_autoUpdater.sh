#!/bin/bash
# netbox-check-update.sh — verifica se há nova versão do NetBox no GitHub com base no link simbólico

set -euo pipefail

NETBOX_DIR="/opt/netbox"
GITHUB_API="https://api.github.com/repos/netbox-community/netbox/releases/latest"

# Verifica se o link simbólico existe
if [ ! -L "$NETBOX_DIR" ]; then
  echo "Erro: $NETBOX_DIR não é um link simbólico."
  exit 1
fi

# Extrai versão do link simbólico
REAL_PATH=$(readlink -f "$NETBOX_DIR")
CURRENT_VERSION=$(basename "$REAL_PATH" | sed 's/^netbox-//')

# Obtém a versão mais recente do GitHub
LATEST_VERSION=$(curl -s "$GITHUB_API" | grep '"tag_name":' | head -n 1 | cut -d '"' -f4 | sed 's/^v//')

echo "Versão instalada: $CURRENT_VERSION"
echo "Última versão disponível: $LATEST_VERSION"

if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
    echo "🔔 Uma nova versão do NetBox está disponível!" 
    NETBOX_UPDATERLOG="/var/log/NetboxUpdateLog"
    TODAY="$(date '+%Y-%m-%d_%H-%M-%S')"
    mkdir -p "$NETBOX_UPDATERLOG"
    echo "🔔 Uma nova versão do NetBox está disponível!" >> "$NETBOX_UPDATERLOG/Netbox_update.log"
    echo "Iniciando o UPGRADE ⬆️" >> "$NETBOX_UPDATERLOG/Netbox_update.log"
    FROM="$CURRENT_VERSION"
    TO="$LATEST_VERSION"
    NETBOX_DIR="/opt/netbox"
    BACKUP_DIR="/opt/netbox-backups/$(date +%F_%T)$LATEST_VERSION"
    mkdir -p "$BACKUP_DIR"
    
    echo "Iniciando upgrade de NetBox $FROM para $TO..." >> "$NETBOX_UPDATERLOG/Netbox_update.log"
    echo "⭐ Fazendo backup em $BACKUP_DIR..." >> "$NETBOX_UPDATERLOG/Netbox_update.log"
    pg_dump -U netbox -h localhost -Fc netbox >> "$BACKUP_DIR/netbox_$FROM.dump"

    mkdir -p "$NETBOX_DIR/netbox/media"
    cp -pr "$NETBOX_DIR/netbox/media" "$BACKUP_DIR/"
    cp -r "$NETBOX_DIR/netbox/scripts" "$BACKUP_DIR/"
    cp -r "$NETBOX_DIR/netbox/reports" "$BACKUP_DIR/"
    echo "✅ Backup concluído com sucesso!" >> "$NETBOX_UPDATERLOG/Netbox_update.log"
    

    echo "⭐ Baixando NetBox v$TO..." >> "$NETBOX_UPDATERLOG/Netbox_update.log"
    wget -q "https://github.com/netbox-community/netbox/archive/v$TO.tar.gz" -O "/tmp/netbox-$TO.tar.gz"
    sudo tar -xzf "/tmp/netbox-$TO.tar.gz" -C /opt
    sudo ln -sfn "/opt/netbox-$TO" "$NETBOX_DIR"
    echo "✅ Baixado com sucesso!" >> "$NETBOX_UPDATERLOG/Netbox_update.log"

    echo "⭐ Migrando configurações e dados customizados..." >> "$NETBOX_UPDATERLOG/Netbox_update.log"
    sudo cp "/opt/netbox-$FROM/local_requirements.txt" "$NETBOX_DIR/"
    sudo cp "/opt/netbox-$FROM/netbox/netbox/configuration.py" "$NETBOX_DIR/netbox/netbox/"
    sudo cp "/opt/netbox-$FROM/netbox/netbox/ldap_config.py" "$NETBOX_DIR/netbox/netbox/"
    sudo cp "/opt/netbox-$FROM/gunicorn.py" "$NETBOX_DIR/"
    sudo cp -r "/opt/netbox-$FROM/netbox/scripts" "$NETBOX_DIR/netbox/"
    sudo cp -r "/opt/netbox-$FROM/netbox/reports" "$NETBOX_DIR/netbox/"
    sudo cp -r "/opt/netbox-$FROM/local" "$NETBOX_DIR/"
    sudo cp -pr "/opt/netbox-$FROM/netbox/media" "$NETBOX_DIR/netbox/"
    sudo rm -rf "$NETBOX_DIR/netbox/static/netbox_topology_views/" && cp -r "/opt/netbox-$FROM/netbox/static/netbox_topology_views" "$NETBOX_DIR/netbox/static/" 
    sudo chown netbox:netbox -R /opt/netbox
    echo "✅ Migrado com sucesso!" >> "$NETBOX_UPDATERLOG/Netbox_update.log"

    echo "⭐ Executando upgrade.sh..." >> "$NETBOX_UPDATERLOG/Netbox_update.log"
    cd "$NETBOX_DIR"
    sudo ./upgrade.sh
    echo "Reiniciando serviços NetBox..." >> "$NETBOX_UPDATERLOG/Netbox_update.log"
    sudo systemctl restart netbox netbox-rq
    sudo chown netbox:netbox -R /opt/netbox/
    echo "✅ Upgrade concluído com sucesso!" >> "$NETBOX_UPDATERLOG/Netbox_update.log"

else
    NETBOX_UPDATERLOG="/var/log/NetboxUpdateLog"
    TODAY="$(date '+%Y-%m-%d_%H-%M-%S')"
    echo "✅ NetBox está atualizado." >> "$NETBOX_UPDATERLOG/Netbox_update.log"
    exit 0
fi

