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
FOLDERS=("conf.d" "snippets" "sites-available" "sites-enabled")

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

echo "✅ Sincronizzazione completata."

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
