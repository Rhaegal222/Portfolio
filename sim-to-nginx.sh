#!/bin/bash

# sim-sync-to-nginx.sh
# Sincronizza la struttura simulata da deploy/www su NGINX reale gestito da aaPanel

set -e

# Percorsi
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DEPLOY_CONF_BASE="$SCRIPT_DIR/deploy/www/server/nginx/conf"
NGINX_CONF_BASE="/www/server/nginx/conf"

# Lista directory da sincronizzare
DIRS=(
  conf.d
  snippets
  sites-available/dev
  sites-available/prod
)

# Copia nginx.conf principale se esiste nella simulazione
if [ -f "$DEPLOY_CONF_BASE/nginx.conf" ]; then
  echo "📄 Copio nginx.conf in $NGINX_CONF_BASE"
  sudo cp "$DEPLOY_CONF_BASE/nginx.conf" "$NGINX_CONF_BASE/nginx.conf"
fi

# Sincronizza le directory
for dir in "${DIRS[@]}"; do
  SRC="$DEPLOY_CONF_BASE/$dir"
  DEST="$NGINX_CONF_BASE/$dir"
  if [ -d "$SRC" ]; then
    echo "🔄 Sync $dir"
    sudo rsync -av --delete "$SRC/" "$DEST/"
  else
    echo "⚠️  $SRC non trovato, skip"
  fi

done

# Ricrea i symlink per sites-enabled/{dev,prod}
for MODE in dev prod; do
  SA="$NGINX_CONF_BASE/sites-available/$MODE"
  SE="$NGINX_CONF_BASE/sites-enabled/$MODE"
  echo "🔗 Ricreo symlink per $MODE"
  sudo mkdir -p "$SE"
  sudo rm -f "$SE"/*.conf
  for f in "$SA"/*.conf; do
    [ -f "$f" ] && sudo ln -s "$f" "$SE/$(basename "$f")"
  done

done

# Verifica configurazione
echo "🔍 Verifico configurazione NGINX..."
sudo /www/server/nginx/sbin/nginx -t

# Ricarica nginx
echo "🔁 Ricarico NGINX..."
sudo /www/server/nginx/sbin/nginx -s reload

echo "✅ NGINX sincronizzato con la configurazione da deploy/www"
