#!/bin/bash
set -e

DEV_BASE=/www/wwwroot/dev/nginx
NGINX_BASE=/www/server/nginx/conf

echo "📄 Sync nginx.conf..."
if [ -f "$DEV_BASE/nginx.conf" ]; then
  sudo cp "$DEV_BASE/nginx.conf" "$NGINX_BASE/nginx.conf"
fi

echo "🔄 Sincronizzo conf.d, snippets, sites-available/prod..."
for dir in conf.d snippets sites-available/prod; do
  sudo rsync -av --delete "$DEV_BASE/$dir/" "$NGINX_BASE/$dir/"
done

echo "🔗 Ricreo symlink in sites-enabled/prod..."
SA="$NGINX_BASE/sites-available/prod"
SE="$NGINX_BASE/sites-enabled/prod"
sudo mkdir -p "$SE"
sudo rm -f "$SE"/*.conf
for f in "$SA"/*.conf; do
  sudo ln -s "$f" "$SE/$(basename $f)"
done

echo "🔍 Verifica configurazione nginx..."
sudo /www/server/nginx/sbin/nginx -t

echo "🔁 Ricarico nginx..."
sudo /www/server/nginx/sbin/nginx -s reload

echo "✅ Deploy Nginx PRODUCTION completato."
