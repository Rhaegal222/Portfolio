#!/bin/bash
#
# simd-nginx-deploy.sh
# Simula il deploy NGINX in locale usando la struttura in deploy/www
# Genera file .conf pronti per la produzione con path reali
# Uso: ./simd-nginx-deploy.sh -dev|-prod

set -euo pipefail

########## STEP 1: Verifica parametro ##########
echo -e "\n🔍 STEP 1: Verifico parametro (-dev o -prod)"
if [ "$#" -lt 1 ]; then
  echo "❌ Uso: $0 -dev|-prod"
  exit 1
fi
case "$1" in
  -dev|-prod)
    MODE=${1#-}
    shift
    ;;
  *)
    echo "❌ Uso: $0 -dev|-prod"
    exit 1
    ;;
esac
echo -e "\n🚀 [STEP 1] Modalità: $MODE"

########## STEP 2: Configurazione percorsi ##########
echo -e "\n🔧 STEP 2: Configuro i percorsi di lavoro"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DEPLOY_ROOT="$SCRIPT_DIR/deploy/www"
WWWROOT="$DEPLOY_ROOT/wwwroot/$MODE"
LOGS_BASE="$DEPLOY_ROOT/wwwlogs"
REAL_LOG_DIR="/www/wwwlogs"
PORTS_FILE="$SCRIPT_DIR/deploy/assigned_ports.env"

echo "    • SCRIPT_DIR    = $SCRIPT_DIR"
echo "    • DEPLOY_ROOT   = $DEPLOY_ROOT"
echo "    • WWWROOT       = $WWWROOT"
echo "    • LOGS_BASE     = $LOGS_BASE"
echo "    • REAL_LOG_DIR  = $REAL_LOG_DIR"
echo "    • PORTS_FILE    = $PORTS_FILE"

if [[ ! -d "$WWWROOT" ]]; then
  echo "❌ [ERROR] Directory di deploy non trovata: $WWWROOT"
  echo "   ➤ Esegui prima sima-init-structure.sh"
  exit 1
fi
echo "✅ [STEP 2] Percorsi validi"

########## STEP 3: Caricamento porte ##########
echo -e "\n🔢 STEP 3: Carico porte da $PORTS_FILE"
if [[ ! -f "$PORTS_FILE" ]]; then
  echo "❌ [ERROR] File porte non trovato: $PORTS_FILE"
  exit 1
fi
source "$PORTS_FILE"
if [[ -z "${FRONT_PORT:-}" || -z "${BACK_PORT:-}" ]]; then
  echo "❌ [ERROR] FRONT_PORT o BACK_PORT mancanti in $PORTS_FILE"
  exit 1
fi
echo "    • FRONT_PORT = $FRONT_PORT"
echo "    • BACK_PORT  = $BACK_PORT"
echo "✅ [STEP 3] Porte caricate correttamente"

########## STEP 4: Rilevamento progetto ##########
echo -e "\n🔍 STEP 4: Seleziona progetto"
# Chiedo all'utente se è il progetto principale
read -rp "➤ È il progetto principale? [y/N] " IS_MAIN
IS_MAIN=${IS_MAIN,,}  # Converto in minuscolo

# Determina il nome del progetto in base alla risposta
if [[ "$IS_MAIN" == "y" ]]; then
  PROJECT_NAME=$(basename "$WWWROOT"/*/)
  REL_PATH="$PROJECT_NAME"  # Escludiamo "apps/" per il progetto principale
else
  if [[ -d "$WWWROOT/apps" ]]; then
    PROJECT_NAME=$(basename "$WWWROOT/apps"/*/)
    REL_PATH="apps/$PROJECT_NAME"  # Aggiungi "apps/" per i progetti non principali
  else
    echo "❌ [ERROR] La cartella 'apps' non esiste."
    exit 1
  fi
fi

if [[ -z "$PROJECT_NAME" ]]; then
  echo "❌ [ERROR] Impossibile determinare il nome del progetto"
  exit 1
fi

echo "    • PROJECT_NAME = $PROJECT_NAME"
echo "    • REL_PATH     = $REL_PATH"
echo "✅ [STEP 4] Progetto configurato"

########## STEP 5: Preparazione log ##########
echo -e "\n🗂️ STEP 5: Creo directory e file di log"
LOGS_DIR="$LOGS_BASE/$MODE"
mkdir -p "$LOGS_DIR"
touch \
  "$LOGS_DIR/${MODE}_${PROJECT_NAME}_front_access.log" \
  "$LOGS_DIR/${MODE}_${PROJECT_NAME}_front_error.log" \
  "$LOGS_DIR/${MODE}_${PROJECT_NAME}_api_access.log" \
  "$LOGS_DIR/${MODE}_${PROJECT_NAME}_api_error.log"
echo "    • LogDir    = $LOGS_DIR"
echo "✅ [STEP 5] Log pronti"

########## STEP 6: Trovo socket PHP-FPM ##########
echo -e "\n🔌 STEP 6: Trovo socket PHP-FPM php8.2"
PHP_SOCK=$(find /www/server/php/ -type s -name '*.sock' 2>/dev/null | grep php8.2 | head -n1)
if [[ -z "$PHP_SOCK" ]]; then echo "❌ [ERROR] Socket PHP-FPM php8.2 non trovato"; exit 1; fi
echo "    • PHP_SOCK = $PHP_SOCK"
echo "✅ [STEP 6] Socket trovato"

########## STEP 7: Generazione nginx.conf ##########
echo -e "\n⚙️ STEP 7: Configurazione di nginx.conf"

# Verifica se nginx.conf esiste, se no crealo
NGINX_MAIN_CONF="/www/server/nginx/conf/nginx.conf"
if [ ! -f "$NGINX_MAIN_CONF" ]; then
  echo -e "\n🔧 Creazione del file $NGINX_MAIN_CONF"
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

########## STEP 8: Configuro proxy_params.conf ##########
echo -e "\n⚙️ STEP 8: Configuro proxy_params.conf"

if [ ! -f "$CONF_D/proxy_params.conf" ]; then
  cat > "$CONF_D/proxy_params.conf" <<'EOF'
# proxy_params.conf
proxy_http_version 1.1;
proxy_set_header   Host              $host;
proxy_set_header   X-Real-IP         $remote_addr;
proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header   X-Forwarded-Proto $scheme;
proxy_redirect     off;
EOF
  echo -e "  📄 \e[1;32mGenerato proxy_params.conf di default\e[0m"
else
  echo -e "  📄 \e[1;32mProxy_params.conf già presente\e[0m"
fi

########## STEP 9: Preparo directory di configurazione NGINX ##########
echo -e "\n📁 STEP 9: Preparo conf.d, sites-available, sites-enabled"

# Imposta la struttura delle directory
NGINX_CONF_ROOT="$DEPLOY_ROOT/server/nginx/conf"
SITES_AVAIL="$NGINX_CONF_ROOT/sites-available/$MODE"
SITES_ENABLED="$NGINX_CONF_ROOT/sites-enabled/$MODE"

# Crea le cartelle se non esistono
mkdir -p "$NGINX_CONF_ROOT/conf.d" "$SITES_AVAIL" "$SITES_ENABLED"
echo "    • NGINX_CONF_ROOT = $NGINX_CONF_ROOT"
echo "    • SITES_AVAIL     = $SITES_AVAIL"
echo "    • SITES_ENABLED   = $SITES_ENABLED"

########## STEP 10: Generazione VHOST ##########
echo -e "\n📝 STEP 10: Genero file VHOST"
VHOST_FILE="$SITES_AVAIL/${PROJECT_NAME}.conf"
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

    access_log  $REAL_LOG_DIR/$MODE/${PROJECT_NAME}_front_access.log;
    error_log   $REAL_LOG_DIR/$MODE/${PROJECT_NAME}_front_error.log;
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

    location ~ ^/index\.php(/|$) {
        fastcgi_pass   unix:$PHP_SOCK;
        fastcgi_param  SCRIPT_FILENAME /$DEV_DIR_PART/$REL_PATH/backend/public\$fastcgi_script_name;
        include        fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }

    access_log  $REAL_LOG_DIR/$MODE/${PROJECT_NAME}_api_access.log;
    error_log   $REAL_LOG_DIR/$MODE/${PROJECT_NAME}_api_error.log;
}
EOF
echo "    • VHOST_FILE = $VHOST_FILE"
echo "✅ [STEP 10] VHOST generato"

########## STEP 11: Attivazione VHOST ##########
echo -e "\n🔗 STEP 11: Creo symlink in sites-enabled"
ln -sf "$VHOST_FILE" "$SITES_ENABLED/$PROJECT_NAME.conf"
echo "    • Symlink creato = $SITES_ENABLED/$PROJECT_NAME.conf"
echo "✅ [STEP 11] Symlink attivo"

########## STEP 12: Fine ##########
echo -e "\n🎉 STEP 12: Deploy NGINX simulato completato per $PROJECT_NAME (MODE=$MODE)"
