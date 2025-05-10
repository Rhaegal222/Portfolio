#!/usr/bin/env bash
#
# simd-nginx-deploy.sh
# Simula il deploy NGINX in locale usando la struttura in deploy/www
# Genera file .conf pronti per la produzione con path reali
# Uso: ./simd-nginx-deploy.sh -dev|-prod

set -euo pipefail

# 📍 Parametri
echo -e "\n🔍  \e[1;33mSTEP 0:\e[0m \e[1;32m[SIM]\e[0m Verifico modalità di esecuzione"
if [[ "$1" != "-dev" && "$1" != "-prod" ]]; then
  echo "❌ Uso corretto: $0 -dev|-prod <percorso_progetto>"
  exit 1
fi
MODE=${1#-}
shift

# Verifica se è stato specificato un progetto
if [ -z "$1" ]; then
  echo "❌ Specificare nome progetto"
  exit 1
else
  PROJECT="$1"
  shift
fi

# Recupero percorso del progetto
SCRIPT_DIR=$(readlink -f "$(dirname "$0")")
PROJECT_PATH=$(readlink -f "$PROJECT")
PROJECT_NAME=$(basename "$PROJECT_PATH")

# 📂 Verifica cartella del progetto
echo -e "\n🔍  \e[1;33mSTEP 1:\e[0m \e[1;32m[SIM]\e[0m Verifica cartella del progetto"
if [ ! -d "$PROJECT_PATH" ]; then
  echo "❌ La cartella del progetto non esiste: $PROJECT_PATH"
  exit 1
fi

# Verifica la presenza delle cartelle frontend e backend
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

# ─── Percorsi di simulazione del deploy ───
DEPLOY_ROOT="/www"  # Destinazione finale

# ─── Percorsi di deploy ───
WWWROOT="www/wwwroot/$MODE"
WWWLOGS="www/wwwlogs"
NGINX_CONF_ROOT="/www/server/nginx/conf"  # Usare direttamente il percorso finale

# ─── Percorsi di configurazione NGINX ───
CONF_D="$NGINX_CONF_ROOT/conf.d"
NGINX_CONF="$NGINX_CONF_ROOT/nginx.conf"
SITES_AVAIL="$NGINX_CONF_ROOT/sites-available/$MODE"
SITES_ENABLED="$NGINX_CONF_ROOT/sites-enabled/$MODE"
REAL_LOG_DIR="/www/wwwlogs/$MODE"  # Percorso finale per i log

# 📂 Creazione delle directory di simulazione
echo -e "\n🔌  \e[1;33mSTEP 2:\e[0m \e[1;32m[SIM]\e[0m Creazione directory per il VHOST"
mkdir -p "$SITES_AVAIL"
VHOST_FILE="$SITES_AVAIL/${PROJECT_NAME}.conf"

# 🔧 Creazione del file nginx.conf
echo -e "\n🔧  \e[1;33mSTEP 3:\e[0m Creazione file nginx.conf"
if [ ! -f "$NGINX_CONF" ]; then
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
  echo -e "  ➕ \e[1;32mCreato $NGINX_CONF\e[0m"
fi

# 📂 Creazione file VHOST
cat > "$VHOST_FILE" <<EOF
server {
  listen       \$FRONT_PORT;
  listen       [::]:\$FRONT_PORT;
  server_name  _;
  root         /\$DEV_DIR_PART/\$REL_PATH/frontend/browser;
  index        index.html;

  location / {
    try_files \$uri \$uri/ /index.html;
  }

  access_log  \$REAL_LOG_DIR/\$MODE/\${PROJECT_NAME}_front_access.log;
  error_log   \$REAL_LOG_DIR/\$MODE/\${PROJECT_NAME}_front_error.log;
}

server {
  listen       \$BACK_PORT;
  listen       [::]:\$BACK_PORT;
  server_name  _;
  root         /\$DEV_DIR_PART/\$REL_PATH/backend/public;
  index        index.php;

  location / {
    try_files \$uri \$uri/ /index.php?\$query_string;
  }

  location ~ ^/index\\.php(/|\$) {
    fastcgi_pass   unix:\$PHP_SOCK;
    fastcgi_param  SCRIPT_FILENAME /\$DEV_DIR_PART/\$REL_PATH/backend/public\$fastcgi_script_name;
    include        fastcgi_params;
  }

  location ~ /\\.(?!well-known).* {
    deny all;
  }

  access_log  \$REAL_LOG_DIR/\$MODE/\${PROJECT_NAME}_api_access.log;
  error_log   \$REAL_LOG_DIR/\$MODE/\${PROJECT_NAME}_api_error.log;
}
EOF

# 📂 Verifica e creazione delle cartelle "sites-enabled"
echo -e "\n🔗  \e[1;33mSTEP 4:\e[0m Creazione symlink in sites-enabled"
if [ ! -d "$SITES_ENABLED" ]; then
  echo "La cartella $SITES_ENABLED non esiste, la creo ora."
  mkdir -p "$SITES_ENABLED"
fi
ln -sf "$VHOST_FILE" "$SITES_ENABLED/$PROJECT_NAME.conf"

# 📜 Riepilogo variabili di deploy
echo -e "\nℹ️   \e[1;33mSTEP 5:\e[0m Riepilogo variabili di deploy"
echo -e "  ➤  Modalità di deploy:     \e[1;33m$MODE\e[0m"
echo -e "  ➤  Progetto:               \e[1;33m$PROJECT\e[0m"
echo -e "  ➤  Nome progetto:          \e[1;33m$PROJECT_NAME\e[0m"
echo -e "  ➤  Percorso progetto:      \e[1;33m$PROJECT_PATH\e[0m"
echo -e "  ➤  SCRIPT_DIR:             \e[1;36m$SCRIPT_DIR\e[0m"
echo -e "  ➤  DEPLOY (sim root):      \e[1;36m$DEPLOY_ROOT\e[0m"
echo -e "  ➤  WWWROOT (source):       \e[1;36m$WWWROOT\e[0m"
echo -e "  ➤  SITES_AVAIL:            \e[1;36m$SITES_AVAIL\e[0m"
echo -e "  ➤  VHOST_FILE:             \e[1;36m$VHOST_FILE\e[0m"

# Sezione Destinazione (file e percorsi in /www)
echo -e "\n🔧   \e[1;33m[Destinazione]\e[0m"
echo -e "  ➤  SITES_ENABLED:          \e[1;36m$SITES_ENABLED\e[0m"
echo -e "  ➤  NGINX_CONF_ROOT:        \e[1;36m$NGINX_CONF_ROOT\e[0m"
echo -e "  ➤  NGINX_CONF:             \e[1;36m$NGINX_CONF\e[0m"
echo -e "  ➤  REAL_LOG_DIR:           \e[1;36m$REAL_LOG_DIR\e[0m"
