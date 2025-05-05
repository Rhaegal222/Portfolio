#!/bin/bash

# Percorsi
DEV_BASE="/www/wwwroot/dev/nginx"
NGINX_BASE="/www/server/nginx/conf"

# Copia il file nginx.conf
echo "📄 Copio nginx.conf..."
if [ -f "$DEV_BASE/nginx.conf" ]; then
    sudo cp "$DEV_BASE/nginx.conf" "$NGINX_BASE/nginx.conf"
    echo "✅ nginx.conf copiato correttamente."
else
    echo "⚠️  nginx.conf non trovato in $DEV_BASE"
fi

# Cartelle da sincronizzare
FOLDERS=("conf.d" "snippets" "sites-available/dev")

echo "🔄 Avvio sincronizzazione delle cartelle da '$DEV_BASE' a '$NGINX_BASE'..."

for dir in "${FOLDERS[@]}"; do
    SRC="$DEV_BASE/$dir/"
    DST="$NGINX_BASE/$dir/"
    if [ -d "$SRC" ]; then
        echo "📁 Sincronizzo $dir..."
        sudo rsync -av --delete "$SRC" "$DST"
    else
        echo "⚠️  Cartella mancante: $SRC"
    fi
done

# Ricrea i symlink per sites-enabled/dev
echo -e "\n🔗 Ricreo symlink da sites-available/dev a sites-enabled/dev..."
SITES_AVAILABLE="$NGINX_BASE/sites-available/dev"
SITES_ENABLED="$NGINX_BASE/sites-enabled/dev"

# Crea la cartella se non esiste
if [ ! -d "$SITES_ENABLED" ]; then
    echo "📂 Creo cartella missing: $SITES_ENABLED"
    sudo mkdir -p "$SITES_ENABLED"
fi

# Pulisce i vecchi symlink
sudo rm -f "$SITES_ENABLED"/*.conf

# Ricrea symlink solo per file .conf
for file in "$SITES_AVAILABLE"/*.conf; do
    if [ -f "$file" ]; then
        sudo ln -s "$file" "$SITES_ENABLED/$(basename "$file")"
        echo "➕ Linkato $(basename "$file")"
    fi
done

echo "✅ Symlink aggiornati."

# Test configurazione
echo -e "\n🔍 Verifica configurazione Nginx..."
sudo /www/server/nginx/sbin/nginx -c "$NGINX_BASE/nginx.conf" -t

# Ricarica Nginx se test OK
if [ $? -eq 0 ]; then
    echo "🔁 Ricarico Nginx..."
    sudo /www/server/nginx/sbin/nginx -s reload
    echo "✅ Nginx ricaricato con successo."
else
    echo "❌ Errore nella configurazione Nginx. Nessun reload eseguito."
fi
