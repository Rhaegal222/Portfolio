#!/bin/bash

# sim-sync-to-nginx.sh
# Sincronizza la struttura simulata da deploy/www su NGINX reale gestito da aaPanel

set -euo pipefail
trap 'echo "Errore rilevato al comando: $BASH_COMMAND. Uscita." >&2' ERR

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
  sites-enabled/dev
  sites-enabled/prod
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

  # Se la directory di destinazione non esiste, creala
  if [ ! -d "$DEST" ]; then
    echo "📂 Directory $DEST non esistente, creazione..."
    sudo mkdir -p "$DEST"
  fi

  if [ ! -d "$SRC" ]; then
  echo "⚠️  $SRC non trovato, lo creo vuoto"
  sudo mkdir -p "$SRC"
  sudo touch "$SRC/.placeholder"
fi
done

# Ricrea i symlink per sites-enabled/{dev,prod}
for MODE in dev prod; do
  SA="$NGINX_CONF_BASE/sites-available/$MODE"
  SE="$NGINX_CONF_BASE/sites-enabled/$MODE"

  echo "🔗 Ricreo symlink per $MODE"

  # Assicurati che la directory di sites-enabled esista
  if [ ! -d "$SE" ]; then
    sudo mkdir -p "$SE"
  fi

  # Rimuove tutti i symlink/vecchi file .conf nella directory di sites-enabled
  sudo rm -f "$SE"/*.conf

  for f in "$SA"/*.conf; do
    if [ -f "$f" ]; then
      sudo ln -s "$f" "$SE/$(basename "$f")"
    fi
  done
done

# Verifica configurazione
echo "🔍 Verifico configurazione NGINX..."
sudo /www/server/nginx/sbin/nginx -t

# Ricarica nginx
echo "🔁 Ricarico NGINX..."
sudo /www/server/nginx/sbin/nginx -s reload

echo "✅ NGINX sincronizzato con la configurazione da deploy/www"
