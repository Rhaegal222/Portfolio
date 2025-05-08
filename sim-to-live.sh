#!/usr/bin/env bash

# sim-to-live.sh
# Sincronizza la simulazione (deploy/www) con l'ambiente reale (NGINX + codice)
# Uso: ./sim-to-live.sh -dev | -prod

set -euo pipefail
trap 'echo "❌ Errore su comando: $BASH_COMMAND" >&2' ERR

if [[ "${1:-}" != "-dev" && "${1:-}" != "-prod" ]]; then
  echo "❌ Uso: $0 -dev|-prod"
  exit 1
fi
MODE=${1#-}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_BASE="$SCRIPT_DIR/deploy/www"

# === Percorsi simulati ===
CONF_SRC="$DEPLOY_BASE/server/nginx/conf"
WWW_SRC="$DEPLOY_BASE/wwwroot/$MODE"

# === Percorsi reali ===
CONF_DEST="/www/server/nginx/conf"
WWW_DEST="/www/wwwroot/$MODE"
LOGS_DEST="/www/wwwlogs"

# Trova progetto
PROJECT_NAME=$(find "$WWW_SRC" -mindepth 1 -maxdepth 1 -type d | head -n1 | xargs -n1 basename)
if [[ -z "$PROJECT_NAME" ]]; then
  echo "❌ Nessun progetto trovato in $WWW_SRC"
  exit 1
fi

echo "🔁 Sync configurazione NGINX..."
for dir in conf.d snippets "sites-available/$MODE" "sites-enabled/$MODE"; do
  SRC="$CONF_SRC/$dir"
  DEST="$CONF_DEST/$dir"
  sudo mkdir -p "$DEST"
  if [[ -d "$SRC" ]]; then
    sudo rsync -av --delete "$SRC/" "$DEST/"
  fi
done

# Copio nginx.conf principale
if [[ -f "$CONF_SRC/nginx.conf" ]]; then
  echo "📄 Copio nginx.conf"
  sudo cp "$CONF_SRC/nginx.conf" "$CONF_DEST/nginx.conf"
fi

# Ricrea symlink in sites-enabled
echo "🔗 Rigenero symlink in sites-enabled/$MODE"
SA="$CONF_DEST/sites-available/$MODE"
SE="$CONF_DEST/sites-enabled/$MODE"
sudo mkdir -p "$SE"
sudo rm -f "$SE"/*.conf
for f in "$SA"/*.conf; do
  [[ -f "$f" ]] && sudo ln -s "$f" "$SE/$(basename "$f")"
done

# Sincronizza codice wwwroot
echo "🌍 Deploy codice in $WWW_DEST"
sudo mkdir -p "$WWW_DEST"
sudo rsync -av --delete "$WWW_SRC/" "$WWW_DEST/"

# Assicura che i log esistano
echo "📄 Verifica log in $LOGS_DEST"
sudo mkdir -p "$LOGS_DEST"
sudo touch "$LOGS_DEST/${MODE}_${PROJECT_NAME}_access.log" \
           "$LOGS_DEST/${MODE}_${PROJECT_NAME}_error.log"

# Verifica e ricarica NGINX
echo "🔍 Verifico configurazione NGINX..."
sudo /www/server/nginx/sbin/nginx -t

echo "🔁 Ricarico NGINX..."
sudo /www/server/nginx/sbin/nginx -s reload

echo "✅ Produzione '$MODE' aggiornata per '$PROJECT_NAME'"
