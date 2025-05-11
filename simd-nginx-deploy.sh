#!/usr/bin/env bash
#
# simd-nginx-deploy.sh
# Simula il deploy NGINX in locale usando la struttura in deploy/www
# Verifica i percorsi nella simulazione (genera i file .conf con variabili espanse)
# Uso: ./simd-nginx-deploy.sh -dev|-prod <percorso_progetto>

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "❌ Questo script deve essere eseguito con i permessi di root. Esegui con sudo."
  exec sudo "$0" "$@"
fi

# 📍 STEP 0: Parametri
echo -e "\n🔍  \e[1;33mSTEP 0:\e[0m Verifico modalità di esecuzione"
if [[ "${1:-}" != "-dev" && "${1:-}" != "-prod" ]]; then
  echo "❌ Uso corretto: $0 -dev|-prod <percorso_progetto>"
  exit 1
fi
MODE=${1#-}
shift

# 📂 Verifica parametro progetto
if [ -z "${1:-}" ]; then
  echo "❌ Specificare nome progetto"
  exit 1
fi
PROJECT="$1"
shift

# ─── Recupero informazioni ───
SCRIPT_DIR=$(readlink -f "$(dirname "$0")")
PROJECT_PATH=$(readlink -f "$PROJECT")
PROJECT_NAME=$(basename "$PROJECT_PATH")

# 📂 STEP 1: Verifica cartella del progetto (simulazione)
echo -e "\n🔍  \e[1;33mSTEP 1:\e[0m Verifica cartella del progetto"
if [ ! -d "$PROJECT_PATH" ]; then
  echo "❌ La cartella del progetto non esiste: $PROJECT_PATH"
  exit 1
fi

# rilevo frontend/backend per estrarre PROJECT_NAME
FRONTEND_DIR=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_frontend")
if [ -n "$FRONTEND_DIR" ]; then
  PROJECT_NAME=$(basename "$FRONTEND_DIR" | cut -d'_' -f1)
else
  echo "❌ Nessuna cartella *_frontend trovata in $PROJECT_PATH"
  exit 1
fi

BACKEND_DIR=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_backend")
if [ -n "$BACKEND_DIR" ]; then
  PROJECT_NAME=$(basename "$BACKEND_DIR" | cut -d'_' -f1)
else
  echo "❌ Nessuna cartella *_backend trovata in $PROJECT_PATH"
  exit 1
fi

# ─── Percorsi di simulazione ───
DEPLOY_ROOT="$SCRIPT_DIR/deploy/www"
PORTS_FILE="$SCRIPT_DIR/deploy/assigned_ports.env"

# 📥 Carico porte e le espongo
if [ ! -f "$PORTS_FILE" ]; then
  echo "❌ File porte non trovato: $PORTS_FILE"
  exit 1
fi
source "$PORTS_FILE"
export FRONT_PORT BACK_PORT

# variabili di percorso usate in VHOST
export DEV_DIR_PART="www/wwwroot/$MODE"
export REL_PATH="$PROJECT_NAME"

# socket PHP-FPM (se serve)
PHP_SOCK=$(find /www/server/php/ -type s -name '*.sock' 2>/dev/null | head -n1)
if [ -z "$PHP_SOCK" ]; then
  echo "❌ Socket PHP-FPM non trovato"
  exit 1
fi
export PHP_SOCK

# ─── Percorsi NGINX in simulazione ───
WWWROOT="/www/wwwroot/$MODE"
WWWLOGS="www/wwwlogs"
NGINX_CONF_ROOT="$DEPLOY_ROOT/server/nginx/conf"
CONF_D="$NGINX_CONF_ROOT/conf.d"
NGINX_CONF="$NGINX_CONF_ROOT/nginx.conf"
SITES_AVAIL="$NGINX_CONF_ROOT/sites-available/$MODE"
SITES_ENABLED="$NGINX_CONF_ROOT/sites-enabled/$MODE"
REAL_LOG_DIR="$DEPLOY_ROOT/wwwlogs/$MODE"

# file VHOST simulato
VHOST_FILE="$SITES_AVAIL/${PROJECT_NAME}.conf"

# 📂 STEP 2: Directory per VHOST
echo -e "\n🔌  \e[1;33mSTEP 2:\e[0m Verifica directory per il VHOST (simulazione)"
if [ ! -d "$SITES_AVAIL" ]; then
  echo "  ➕ Creo $SITES_AVAIL"
  mkdir -p "$SITES_AVAIL"
else
  echo "  ➤ Esiste $SITES_AVAIL"
fi

# 🔧 STEP 3: nginx.conf simulato
echo -e "\n🔧  \e[1;33mSTEP 3:\e[0m Verifica file nginx.conf (simulazione)"
if [ ! -f "$NGINX_CONF" ]; then
  echo "  ➕ Creo $NGINX_CONF"
  mkdir -p "$(dirname "$NGINX_CONF")"
  cat > "$NGINX_CONF" <<'EOF'
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
else
  echo "  ➤ Esiste $NGINX_CONF"
fi

# 📂 STEP 4: VHOST simulato con variabili espanse
echo -e "\n📂  \e[1;33mSTEP 4:\e[0m Verifica file VHOST (simulazione)"
if [ ! -f "$VHOST_FILE" ]; then
  echo "  ➕ Creo $VHOST_FILE"
  cat > "$VHOST_FILE" <<EOF
server {
  listen       $FRONT_PORT;
  listen       [::]:$FRONT_PORT;
  server_name  _;
  root         /$DEV_DIR_PART/$REL_PATH/frontend/browser;
  index        index.html;

  location / {
    try_files \$uri \$uri/ /index.html;
  }

  access_log  $REAL_LOG_DIR/${PROJECT_NAME}_front_access.log;
  error_log   $REAL_LOG_DIR/${PROJECT_NAME}_front_error.log;
}

server {
  listen       $BACK_PORT;
  listen       [::]:$BACK_PORT;
  server_name  _;
  root         /$DEV_DIR_PART/$REL_PATH/backend/public;
  index        index.php;

  location / {
    try_files \$uri \$uri/ /index.php?\$query_string;
  }

  location ~ ^/index\\.php(/|\$) {
    fastcgi_pass   unix:$PHP_SOCK;
    fastcgi_param  SCRIPT_FILENAME /$DEV_DIR_PART/$REL_PATH/backend/public\$fastcgi_script_name;
    include        fastcgi_params;
  }

  location ~ /\\.(?!well-known).* {
    deny all;
  }

  access_log  $REAL_LOG_DIR/${PROJECT_NAME}_api_access.log;
  error_log   $REAL_LOG_DIR/${PROJECT_NAME}_api_error.log;
}
EOF
else
  echo "  ➤ Esiste $VHOST_FILE"
fi

# 📜 STEP 5: Riepilogo variabili
echo -e "\nℹ️   \e[1;33mSTEP 5:\e[0m Riepilogo variabili di deploy"
echo -e "  ➤  Modalità:   \e[1;33m$MODE\e[0m"
echo -e "  ➤  Progetto:   \e[1;33m$PROJECT\e[0m"
echo -e "  ➤  Nome:       \e[1;33m$PROJECT_NAME\e[0m"
echo -e "  ➤  SCRIPT:     \e[1;33m$SCRIPT_DIR\e[0m"
echo -e "  ➤  DEPLOY:     \e[1;33m$DEPLOY_ROOT\e[0m"
echo -e "  ➤  WWWROOT:    \e[1;33m$WWWROOT\e[0m"
echo -e "  ➤  LOGS:       \e[1;33m$REAL_LOG_DIR\e[0m"
echo -e "  ➤  PHP_SOCK:   \e[1;33m$PHP_SOCK\e[0m"
echo -e "  ➤  nginx.conf: \e[1;33m$NGINX_CONF\e[0m"
echo -e "  ➤  vhost file: \e[1;33m$VHOST_FILE\e[0m"
echo -e "  ➤  FRONT_PORT: \e[1;33m$FRONT_PORT\e[0m"
echo -e "  ➤  BACK_PORT:  \e[1;33m$BACK_PORT\e[0m"

echo -e "\n✅  Simulazione completa: i file sono pronti in $DEPLOY_ROOT/server/nginx/conf"
