#!/bin/bash
# netbox-check-update.sh — verifica se há nova versão do NetBox no GitHub com base no link simbólico

set -euo pipefail

NETBOX_DIR="/opt/netbox"
GITHUB_API="https://api.github.com/repos/netbox-community/netbox/releases/latest"


LOG_FOLDER="/var/log/NetboxUpdateLog"
LOG_FILE="$LOG_FOLDER/Netbox_update.log"
mkdir -p "$LOG_FOLDER"

# Extrai versão do link simbólico
REAL_PATH=$(readlink -f "$NETBOX_DIR")
CURRENT_VERSION=$(basename "$REAL_PATH" | sed 's/^netbox-//')

# Obtém a versão mais recente do GitHub
LATEST_VERSION=$(curl -s "$GITHUB_API" | grep '"tag_name":' | head -n 1 | cut -d '"' -f4 | sed 's/^v//')


# --- Functions ---
# Logging function
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_FILE"
}

# Verifica se o link simbólico existe
if [ ! -L "$NETBOX_DIR" ]; then
  log_message "Erro: $NETBOX_DIR não é um link simbólico."
  exit 1
fi

log_message "Versão instalada: $CURRENT_VERSION"
log_message "Última versão disponível: $LATEST_VERSION"

if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
    log_message "🔔 Uma nova versão do NetBox está disponível!" 
    
    log_message "🔔 Uma nova versão do NetBox está disponível!"
    log_message "Iniciando o UPGRADE ⬆️"
    FROM="$CURRENT_VERSION"
    TO="$LATEST_VERSION"
    NETBOX_DIR="/opt/netbox"
    BACKUP_DIR="/opt/netbox-backups/$(date +%F_%T)$LATEST_VERSION"
    mkdir -p "$BACKUP_DIR"
    
    log_message "Iniciando upgrade de NetBox $FROM para $TO..."
    log_message "⭐ Fazendo backup em $BACKUP_DIR..."
    pg_dump -U netbox -h localhost -Fc netbox >> "$BACKUP_DIR/netbox_$FROM.dump"

    mkdir -p "$NETBOX_DIR/netbox/media"
    cp -pr "$NETBOX_DIR/netbox/media" "$BACKUP_DIR/"
    cp -r "$NETBOX_DIR/netbox/scripts" "$BACKUP_DIR/"
    cp -r "$NETBOX_DIR/netbox/reports" "$BACKUP_DIR/"
    log_message "✅ Backup concluído com sucesso!"

    log_message "⭐ Baixando NetBox v$TO..."
    wget -q "https://github.com/netbox-community/netbox/archive/v$TO.tar.gz" -O "/tmp/netbox-$TO.tar.gz"
    sudo tar -xzf "/tmp/netbox-$TO.tar.gz" -C /opt
    sudo ln -sfn "/opt/netbox-$TO" "$NETBOX_DIR"
    log_message "✅ Baixado com sucesso!"

    log_message "⭐ Migrando configurações e dados customizados..."
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
    log_message "✅ Migrado com sucesso!"

    log_message "⭐ Executando upgrade.sh..."
    cd "$NETBOX_DIR"
    sudo ./upgrade.sh
    log_message "Reiniciando serviços NetBox..."
    sudo systemctl restart netbox netbox-rq
    sudo chown netbox:netbox -R /opt/netbox/
    log_message "✅ Upgrade concluído com sucesso!"

else
    log_message "✅ NetBox está atualizado."
    exit 0
fi

