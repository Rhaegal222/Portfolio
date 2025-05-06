# sync-nginx-dev.sh
#!/bin/bash

set -e

# Verifica che lsof sia installato
command -v lsof >/dev/null 2>&1 || {
  echo "❌ lsof non trovato. Installalo con uno di questi comandi:"
  echo "   • Ubuntu/Debian: sudo apt-get update && sudo apt-get install -y lsof"
  echo "   • CentOS/RHEL:   sudo yum install -y lsof"
  exit 1
}

# Funzione per trovare una porta libera
test_port() {
  local p=$1
  while lsof -iTCP:$p -sTCP:LISTEN >/dev/null 2>&1; do
    p=$((p+1))
  done
  echo $p
}

# Percorsi
DEV_BASE="/www/wwwroot/server/dev/nginx"
NGINX_BASE="/www/server/nginx/conf"

# Se non esiste, crea conf.d e genera proxy_params.conf di default
if [ ! -d "$DEV_BASE/conf.d" ]; then
  sudo mkdir -p "$DEV_BASE/conf.d"
fi
if [ ! -f "$DEV_BASE/conf.d/proxy_params.conf" ]; then
  sudo tee "$DEV_BASE/conf.d/proxy_params.conf" > /dev/null <<'EOF'
# proxy_params.conf
proxy_http_version 1.1;
proxy_set_header   Host              $host;
proxy_set_header   X-Real-IP         $remote_addr;
proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header   X-Forwarded-Proto $scheme;
proxy_redirect     off;
EOF
fi

# Trova porte libere
declare -i FRONT_PORT=$(test_port 8080)
declare -i BACK_PORT=$(test_port 8000)

echo "🔧 DEV ports -> frontend: $FRONT_PORT, backend: $BACK_PORT"

# Vhost DEV
DEV_SITES_AVAIL="$DEV_BASE/sites-available/dev"
DEV_SITES_ENABLED="$DEV_BASE/sites-enabled/dev"
VHOST_FILE="$DEV_SITES_AVAIL/site.conf"

# Crea cartelle in DEV e su NGINX
sudo mkdir -p "$DEV_SITES_AVAIL" "$DEV_SITES_ENABLED"

# Genera vhost DEV (con sudo)
echo "⚙️  Creo vhost DEV in $VHOST_FILE"
sudo tee "$VHOST_FILE" > /dev/null <<EOF
server {
  listen $FRONT_PORT default_server;
  server_name _;

  root /www/wwwroot/dev/deploy/www/wwwroot/prod/wyrmrest.com/frontend;
  index index.html;

  location / {
    try_files \$uri \$uri/ /index.html;
  }

  location /api {
    proxy_pass http://127.0.0.1:$BACK_PORT;
    include conf.d/proxy_params.conf;
  }

  access_log /www/wwwlogs/dev_access.log;
  error_log  /www/wwwlogs/dev_error.log;
}
EOF

# Sincronizza solo se esistono
echo "🔄 Sincronizzo DEV config nel sistema NGINX"
# conf.d
if [ -d "$DEV_BASE/conf.d" ]; then
  sudo rsync -av --delete "$DEV_BASE/conf.d/" "$NGINX_BASE/conf.d/"
else
  echo "⚠️  Nessuna cartella conf.d in DEV, skip"
fi
# proxy_params.conf
if [ -f "$DEV_BASE/conf.d/proxy_params.conf" ]; then
   sudo cp "$DEV_BASE/conf.d/proxy_params.conf" "$NGINX_BASE/conf.d/proxy_params.conf"
else
  echo "⚠️  proxy_params.conf non trovato in DEV, skip"
fi
# sites-available/dev
if [ -d "$DEV_SITES_AVAIL" ]; then
  sudo rsync -av --delete "$DEV_SITES_AVAIL/" "$NGINX_BASE/sites-available/dev/"
else
  echo "⚠️  Nessuna cartella sites-available/dev in DEV, skip"
fi

# Rigenera symlink DEV
echo "🔗 Rigenero symlink in sites-enabled/dev"
sudo mkdir -p "$NGINX_BASE/sites-enabled/dev"
sudo rm -f "$NGINX_BASE/sites-enabled/dev"/*.conf
sudo ln -s "$NGINX_BASE/sites-available/dev/site.conf" "$NGINX_BASE/sites-enabled/dev/site.conf"

# Test e reload DEV
echo "🔍 Test configurazione nginx (DEV)..."
sudo /www/server/nginx/sbin/nginx -t

echo "🔁 Ricarico nginx (DEV)..."
if [ ! -s /www/server/nginx/logs/nginx.pid ]; then
  echo "⚙️ Avvio nginx (DEV)..."
  sudo /www/server/nginx/sbin/nginx
else
  echo "🔁 Ricarico nginx (DEV)..."
  sudo /www/server/nginx/sbin/nginx -s reload
fi

# Mostra URL
HOST_IP=$(hostname -I | awk '{print $1}')
echo "✅ DEV live: http://localhost:$FRONT_PORT/"