#!/bin/bash

# simc-nginx-deploy.sh
# Simula il deploy NGINX in locale tramite la struttura in deploy/www
# Genera file .conf già pronti per la produzione (path reali)

set -e

# Controllo parametro environment (-dev o -prod)
if [[ "$1" != "-dev" && "$1" != "-prod" ]]; then
  echo "❌ Uso: $0 -dev|-prod"
  exit 1
fi
MODE=${1#-}
shift

# Percorsi
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DEPLOY_ROOT="$SCRIPT_DIR/deploy/www"
DEV_BASE="$DEPLOY_ROOT/server/nginx/conf"
LOCAL_WWWROOT="$DEPLOY_ROOT/wwwroot/$MODE"
LOGS_DIR="/www/wwwlogs"

# Socket PHP-FPM dinamico (prende il primo da PHP 8.2)
PHP_SOCK=$(find /www/server/php/ -type s -name "*.sock" 2>/dev/null | grep php8.2 | head -n1)
if [[ -z "$PHP_SOCK" || ! -S "$PHP_SOCK" ]]; then
  echo "❌ Socket PHP-FPM non trovato o non valido"
  exit 1
fi

# Rileva progetto
PROJECT_NAME=$(find "$LOCAL_WWWROOT" -mindepth 1 -maxdepth 1 -type d | head -n1 | xargs -n1 basename)
if [[ -z "$PROJECT_NAME" ]]; then
  echo "❌ Nessun progetto trovato in $LOCAL_WWWROOT"
  exit 1
fi

# Trova porte libere
find_free_port(){
  local p=$1
  while lsof -iTCP:$p -sTCP:LISTEN >/dev/null 2>&1; do ((p++)); done
  echo $p
}
FRONT_PORT=$(find_free_port 8080)
BACK_PORT=$(find_free_port 8000)

echo "🔧 [SIM $MODE] frontend -> http://localhost:$FRONT_PORT/"
echo "🔧 [SIM $MODE] backend  -> http://localhost:$BACK_PORT/"

# Percorsi vhost
SITES_AVAIL="$DEV_BASE/sites-available/$MODE"
SITES_ENABLED="$DEV_BASE/sites-enabled/$MODE"
mkdir -p "$DEV_BASE/conf.d" "$SITES_AVAIL" "$SITES_ENABLED"

# proxy_params.conf
if [[ ! -f "$DEV_BASE/conf.d/proxy_params.conf" ]]; then
  cat > "$DEV_BASE/conf.d/proxy_params.conf" <<'EOF'
# proxy_params.conf
proxy_http_version 1.1;
proxy_set_header   Host              $host;
proxy_set_header   X-Real-IP         $remote_addr;
proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header   X-Forwarded-Proto $scheme;
proxy_redirect     off;
EOF
  echo "⚙️  [SIM] Generato proxy_params.conf"
fi

# … tutto quanto sopra resta identico …

# Vhost .conf
VHOST_FILE="$SITES_AVAIL/$PROJECT_NAME.conf"
cat > "$VHOST_FILE" <<EOF
server {
    listen       $FRONT_PORT;
    listen       [::]:$FRONT_PORT;
    server_name  _;
    root         $LOCAL_WWWROOT/$PROJECT_NAME/frontend/browser;
    index        index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    access_log  $LOGS_DIR/${MODE}_${PROJECT_NAME}_front_access.log;
    error_log   $LOGS_DIR/${MODE}_${PROJECT_NAME}_front_error.log;
}

server {
    listen       $BACK_PORT;
    listen       [::]:$BACK_PORT;
    server_name  _;
    root         $LOCAL_WWWROOT/$PROJECT_NAME/backend/public;
    index        index.php;

    charset utf-8;
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    error_page 404 /index.php;

    location ~ ^/index\\.php(/|\$) {
        fastcgi_pass   unix:$PHP_SOCK;
        fastcgi_param  SCRIPT_FILENAME $LOCAL_WWWROOT/$PROJECT_NAME/backend/public/index.php;
        include         fastcgi_params;
        fastcgi_hide_header X-Powered-By;
    }

    location ~ /\\.(?!well-known).* {
        deny all;
    }

    access_log  $LOGS_DIR/${MODE}_${PROJECT_NAME}_api_access.log;
    error_log   $LOGS_DIR/${MODE}_${PROJECT_NAME}_api_error.log;
}
EOF

# Symlink
rm -f "$SITES_ENABLED"/*.conf
ln -s "$VHOST_FILE" "$SITES_ENABLED/$PROJECT_NAME.conf"

echo "✅ [SIM $MODE] Vhost generato in $SITES_AVAIL"
