#!/bin/bash
#
# sima-init-structure.sh
# 1) Crea la struttura base di NGINX (sempre)
# 2) Crea wwwroot/prod anche se vuota
# 3) Se passi un <project>, crea anche wwwroot/prod/<project>/{frontend,backend}
#

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DEPLOY_ROOT="$SCRIPT_DIR/deploy/www"

# --- 1) NGINX base config ---
NGINX_CONF_ROOT="$DEPLOY_ROOT/server/nginx/conf"
CONF_D="$NGINX_CONF_ROOT/conf.d"
SITES_AVAIL_DEV="$NGINX_CONF_ROOT/sites-available/dev"
SITES_AVAIL_PROD="$NGINX_CONF_ROOT/sites-available/prod"
SNIPPETS="$NGINX_CONF_ROOT/snippets"
NGINX_MAIN_CONF="$NGINX_CONF_ROOT/nginx.conf"
PROXY_PARAMS_SRC="$SCRIPT_DIR/server/nginx/conf.d/proxy_params.conf"

echo "🔧 Creo struttura base NGINX in $NGINX_CONF_ROOT…"
mkdir -p \
  "$CONF_D" \
  "$SITES_AVAIL_DEV" \
  "$SITES_AVAIL_PROD" \
  "$SNIPPETS"

# main nginx.conf (solo se non esiste)
if [ ! -f "$NGINX_MAIN_CONF" ]; then
  cat > "$NGINX_MAIN_CONF" <<'EOF'
user  www www;
worker_processes auto;
pid        /www/server/nginx/logs/nginx.pid;
error_log  /www/server/nginx/logs/error.log crit;

events {
    worker_connections 51200;
    use                epoll;
}

http {
    include       mime.types;
    include       proxy.conf;
    lua_package_path "/www/server/nginx/lib/lua/?.lua;;";

    default_type  application/octet-stream;
    sendfile       on;
    tcp_nopush     on;
    tcp_nodelay    on;
    keepalive_timeout 65;
    client_max_body_size 50m;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript;

    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers         'ECDHE-ECDSA-CHACHA20-POLY1305:...';

    include conf.d/*.conf;
    include sites-enabled/dev/*.conf;
    include sites-enabled/prod/*.conf;

    include /www/server/panel/vhost/nginx/*.conf;
    include /www/server/panel/vhost/nginx/dev/*.conf;
    include /www/server/panel/vhost/nginx/prod/*.conf;
}
EOF
  echo "  ➕ Creato $NGINX_MAIN_CONF"
fi

# proxy_params.conf  
if [ -f "$PROXY_PARAMS_SRC" ]; then
  cp "$PROXY_PARAMS_SRC" "$CONF_D/proxy_params.conf"
  echo "  📄 Copiato proxy_params.conf"
else
  cat > "$CONF_D/proxy_params.conf" <<'EOF'
# proxy_params.conf
proxy_http_version 1.1;
proxy_set_header   Host              $host;
proxy_set_header   X-Real-IP         $remote_addr;
proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header   X-Forwarded-Proto $scheme;
proxy_redirect     off;
EOF
  echo "  ➕ Generato proxy_params.conf di default"
fi

# --- 2) Creo sempre wwwroot/prod (anche se vuota) ---
WWWROOT_PROD_ROOT="$DEPLOY_ROOT/wwwroot/prod"
echo "🔧 Creo directory wwwroot/prod…"
mkdir -p "$WWWROOT_PROD_ROOT"
echo "  ➕ $WWWROOT_PROD_ROOT"

# --- 3) Se passato argomento, crea cartelle progetto ---
if [ -n "$1" ]; then
  PROJECT="$1"
  FRONTEND_DIR="$WWWROOT_PROD_ROOT/$PROJECT/frontend"
  BACKEND_DIR="$WWWROOT_PROD_ROOT/$PROJECT/backend"

  echo "🔧 Creo struttura wwwroot per progetto '$PROJECT'…"
  mkdir -p "$FRONTEND_DIR" "$BACKEND_DIR"
  echo "  ➕ $FRONTEND_DIR"
  echo "  ➕ $BACKEND_DIR"
fi

echo "✅ Struttura di deploy pronta."
