#!/bin/bash

# simc-nginx-deploy.sh
# Simula il deploy NGINX in locale tramite la struttura in deploy/www
# Non tocca il server reale: lavora solo in deploy/www

set -e

# Controllo parametro environment (-dev o -prod)
if [[ "$1" != "-dev" && "$1" != "-prod" ]]; then
  echo "❌ Uso: $0 -dev|-prod"
  exit 1
fi
MODE=${1#-}   # estrae dev o prod
shift

# Percorsi di simulazione (solo deploy)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DEPLOY_ROOT="$SCRIPT_DIR/deploy/www"
DEV_BASE="$DEPLOY_ROOT/server/nginx/conf"
WWWROOT_BASE="$DEPLOY_ROOT/wwwroot/$MODE"
LOGS_DIR="$DEPLOY_ROOT/logs"

# Rileva il progetto (primo sotto-dir in wwwroot/$MODE)
PROJECT_NAME=$(find "$WWWROOT_BASE" -mindepth 1 -maxdepth 1 -type d | head -n1 | xargs -n1 basename)
if [ -z "$PROJECT_NAME" ]; then
  echo "❌ Nessun progetto trovato in $WWWROOT_BASE"
  exit 1
fi

# Trova porte libere per frontend e backend
test_port() {
  local p=$1
  while lsof -iTCP:$p -sTCP:LISTEN >/dev/null 2>&1; do
    ((p++))
  done
  echo $p
}
FRONT_PORT=$(test_port 8080)
BACK_PORT=$(test_port 8000)

echo "🔧 [SIM $MODE] ports -> frontend: http://localhost:$FRONT_PORT/, backend: http://localhost:$BACK_PORT/"

# Percorsi vhost nella struttura deploy
SITES_AVAIL_DEV="$DEV_BASE/sites-available/$MODE"
SITES_ENABLED_DEV="$DEV_BASE/sites-enabled/$MODE"
VHOST_FILE="$SITES_AVAIL_DEV/$PROJECT_NAME.conf"

# Crea directory deploy (senza sudo)
mkdir -p "$DEV_BASE/conf.d" "$SITES_AVAIL_DEV" "$SITES_ENABLED_DEV" "$LOGS_DIR"

# Genera proxy_params.conf di default se manca
if [ ! -f "$DEV_BASE/conf.d/proxy_params.conf" ]; then
  cat > "$DEV_BASE/conf.d/proxy_params.conf" <<'EOF'
# proxy_params.conf
proxy_http_version 1.1;
proxy_set_header   Host              $host;
proxy_set_header   X-Real-IP         $remote_addr;
proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header   X-Forwarded-Proto $scheme;
proxy_redirect     off;
EOF
  echo "⚙️  [SIM] Generato $DEV_BASE/conf.d/proxy_params.conf"
fi

# Genera vhost simulato
echo "⚙️  [SIM] Creo vhost in $VHOST_FILE"
cat > "$VHOST_FILE" <<EOF
server {
    listen $FRONT_PORT default_server;
    server_name _;

    root $WWWROOT_BASE/$PROJECT_NAME/frontend;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /api {
        proxy_pass http://127.0.0.1:$BACK_PORT;
        include conf.d/proxy_params.conf;
    }

    access_log $LOGS_DIR/${MODE}_access.log;
    error_log  $LOGS_DIR/${MODE}_error.log;
}
EOF

# Abilita il vhost tramite symlink
rm -f "$SITES_ENABLED_DEV"/*.conf
ln -s "$VHOST_FILE" "$SITES_ENABLED_DEV/$PROJECT_NAME.conf"

echo "✅ [SIM $MODE] Deploy NGINX simulato pronto in $DEV_BASE"
