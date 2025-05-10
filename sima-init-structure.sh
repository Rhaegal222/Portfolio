#!/bin/bash
#
# sima-init-structure.sh
# 1) Crea la struttura base di NGINX (sempre)
# 2) Crea wwwroot/prod/apps e wwwroot/dev/apps (anche vuote)
# 3) Se specificato un <project>, crea wwwroot/.../apps/<project>/{frontend,backend} sia in prod che in dev
# 4) Crea la cartella dei log
#
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# --- 🗑️ STEP 0: Rimuovo struttura precedente se esistente ---
if [ -d "$SCRIPT_DIR/deploy" ]; then
  echo -e "\n🗑️  \e[1;33mSTEP 0:\e[0m Rimuovo struttura esistente $SCRIPT_DIR/deploy"
  sudo rm -rf "$SCRIPT_DIR/deploy"
fi

DEPLOY_ROOT="$SCRIPT_DIR/deploy/www"

# --- 🔧 STEP 1: Creo struttura base NGINX ---
NGINX_CONF_ROOT="$DEPLOY_ROOT/server/nginx/conf"
CONF_D="$NGINX_CONF_ROOT/conf.d"
SITES_AVAIL_DEV="$NGINX_CONF_ROOT/sites-available/dev"
SITES_AVAIL_PROD="$NGINX_CONF_ROOT/sites-available/prod"
SNIPPETS="$NGINX_CONF_ROOT/snippets"
NGINX_MAIN_CONF="$NGINX_CONF_ROOT/nginx.conf"
PROXY_PARAMS_SRC="$SCRIPT_DIR/server/nginx/conf.d/proxy_params.conf"

echo -e "\n🔧  \e[1;33mSTEP 1:\e[0m Creo directory base in $NGINX_CONF_ROOT"
echo "  ➤ $CONF_D"
echo "  ➤ $SITES_AVAIL_DEV"
echo "  ➤ $SITES_AVAIL_PROD"
echo "  ➤ $SNIPPETS"
mkdir -p \
  "$CONF_D" \
  "$SITES_AVAIL_DEV" \
  "$SITES_AVAIL_PROD" \
  "$SNIPPETS"

# Configuro nginx.conf solo se non esiste
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
  echo -e "  ➕ \e[1;32mCreato $NGINX_MAIN_CONF\e[0m"
fi

# --- ⚙️ STEP 1.1: Configuro proxy_params.conf ---
echo -e "\n⚙️  \e[1;33mSTEP 2:\e[0m Configuro proxy_params.conf"
if [ -f "$PROXY_PARAMS_SRC" ]; then
  cp "$PROXY_PARAMS_SRC" "$CONF_D/proxy_params.conf"
  echo -e "  📄 \e[1;32mCopiato proxy_params.conf da $PROXY_PARAMS_SRC\e[0m"
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
  echo -e "  ➕ \e[1;32mGenerato proxy_params.conf di default\e[0m"
fi

# --- 🌐 STEP 2: Creo sempre wwwroot/prod/apps ---
WWWROOT_PROD_ROOT="$DEPLOY_ROOT/wwwroot/prod"
echo -e "\n🌐  STEP 2: Creo directory wwwroot/prod/apps in $WWWROOT_PROD_ROOT"
mkdir -p "$WWWROOT_PROD_ROOT/apps"
echo -e "  ➕ $WWWROOT_PROD_ROOT/apps"

# --- 🌐 STEP 3: Creo sempre wwwroot/dev/apps ---
WWWROOT_DEV_ROOT="$DEPLOY_ROOT/wwwroot/dev"
echo -e "\n🌐  STEP 3: Creo directory wwwroot/dev/apps in $WWWROOT_DEV_ROOT"
mkdir -p "$WWWROOT_DEV_ROOT/apps"
echo -e "  ➕ $WWWROOT_DEV_ROOT/apps"

# --- 🗄️ STEP 4: Creo directory dei log per dev e prod ---
LOGS_BASE="$DEPLOY_ROOT/wwwlogs"
LOGS_DEV="$LOGS_BASE/dev"
LOGS_PROD="$LOGS_BASE/prod"

echo -e "\n🗄️  \e[1;33mSTEP 4:\e[0m Creo directory log per dev e prod"
mkdir -p "$LOGS_DEV" "$LOGS_PROD"
echo -e "  ➕ \e[1;32m$LOGS_DEV\e[0m"
echo -e "  ➕ \e[1;32m$LOGS_PROD\e[0m"


# --- 📂 STEP 5: Creo struttura progetto se specificato ---
if [ -n "$1" ]; then
  PROJECT="$1"
  PROD_ROOT="$WWWROOT_PROD_ROOT/apps/$PROJECT"
  DEV_ROOT="$WWWROOT_DEV_ROOT/apps/$PROJECT"

  FRONT_PROD="$PROD_ROOT/frontend"
  BACK_PROD="$PROD_ROOT/backend"
  FRONT_DEV="$DEV_ROOT/frontend"
  BACK_DEV="$DEV_ROOT/backend"

  echo -e "\n📂  \e[1;33mSTEP 5:\e[0m Creo struttura per progetto '$PROJECT' in prod e dev"
  mkdir -p "$FRONT_PROD" "$BACK_PROD" "$FRONT_DEV" "$BACK_DEV"
  echo -e "  ➕ $FRONT_PROD"
  echo -e "  ➕ $BACK_PROD"
  echo -e "  ➕ $FRONT_DEV"
  echo -e "  ➕ $BACK_DEV"
fi

# --- 🔎 STEP 6: Trovo porte libere ---
echo -e "\n🔎 \e[1;33mSTEP 6:\e[0m Trovo porte libere"
find_free_port(){ local p=$1; while lsof -iTCP:$p -sTCP:LISTEN >/dev/null 2>&1; do ((p++)); done; echo $p; }
FRONT_PORT=$(find_free_port 8080)
BACK_PORT=$(find_free_port 8000)
echo -e "    ➤ FRONT_PORT=$FRONT_PORT, BACK_PORT=$BACK_PORT"

echo -e "\n🔧 [SIM $MODE] frontend -> http://localhost:$FRONT_PORT/"
echo -e "🔧 [SIM $MODE] backend  -> http://localhost:$BACK_PORT/"

# --- 🔢 STEP 7: Scrive le porte assegnate temporaneamente in $SCRIPT_DIR ---
PORTS_FILE="$SCRIPT_DIR/deploy/assigned_ports.env"
echo -e "\n💾 \e[1;33mSTEP 7:\e[0m Scrivo porte assegnate in $PORTS_FILE"
echo "FRONT_PORT=$FRONT_PORT" > "$PORTS_FILE"
echo "BACK_PORT=$BACK_PORT" >> "$PORTS_FILE"

# --- ✅ STEP 6: Completamento ---
echo -e "\n✅  \e[1;33mSTEP 8:\e[0m Struttura di deploy pronta."