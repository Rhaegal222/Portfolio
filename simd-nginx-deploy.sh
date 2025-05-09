#!/bin/bash
#
# simd-nginx-deploy.sh
# Simula il deploy NGINX in locale tramite la struttura in deploy/www
# Genera file .conf già pronti per la produzione (path reali)
# Uso: ./simc-nginx-deploy.sh -dev | -prod

set -e

# --- 📝 STEP 0: Verifico parametro environment ---
echo -e "\n🔍 \e[1;33mSTEP 0:\e[0m Verifico parametro -dev|-prod"
if [[ "$1" != "-dev" && "$1" != "-prod" ]]; then
  echo -e "❌ \e[1;31mUso corretto:\e[0m $0 -dev|-prod"
  exit 1
fi
MODE=${1#-}
shift

echo -e "\n🚀 \e[1;33mSTEP 1:\e[0m Imposto variabili di deploy (MODE=$MODE)"

# --- 🔍 STEP 2: Definisco percorsi base ---
echo -e "\n🔍 \e[1;33mSTEP 2:\e[0m Definisco percorsi base"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DEPLOY_ROOT="$SCRIPT_DIR/deploy/www"
DEV_BASE="$DEPLOY_ROOT/server/nginx/conf"
DEV_WWWROOT="$DEPLOY_ROOT/wwwroot/$MODE"
DEV_DIR="www/wwwroot/dev"
PROD_DIR="www/wwwroot/prod"

# Percorsi log
if [[ "$MODE" == "dev" ]]; then
  LOGS_DIR="$DEPLOY_ROOT/wwwlogs/dev"
elif [[ "$MODE" == "prod" ]]; then
  LOGS_DIR="$DEPLOY_ROOT/wwwlogs/prod"
else
  echo -e "❌ \e[1;31mErrore:\e[0m MODE non valido"
  exit 1
fi

REAL_LOG_DIR="/www/wwwlogs"  # Percorso reale dei log usato nei VHOST

echo -e "    ➤ DEPLOY_ROOT=$DEPLOY_ROOT"
echo -e "    ➤ DEV_BASE=$DEV_BASE"
echo -e "    ➤ DEV_WWWROOT=$DEV_WWWROOT"
echo -e "    ➤ LOGS_DIR=$LOGS_DIR"

# --- 🔍 STEP 3: Rilevo nome progetto ---
echo -e "\n📂 \e[1;33mSTEP 3:\e[0m Rilevo nome progetto in $DEV_WWWROOT"
PROJECT_NAME=$(find "$DEV_WWWROOT" -mindepth 1 -maxdepth 1 -type d | head -n1 | xargs -n1 basename)
if [[ -z "$PROJECT_NAME" ]]; then
  echo -e "❌ \e[1;31mErrore:\e[0m Nessun progetto in $DEV_WWWROOT"
  exit 1
fi
echo -e "    ➤ Progetto: $PROJECT_NAME"

# --- 🗂️ STEP 4: Creo cartella log e file ---
echo -e "\n🗂️  \e[1;33mSTEP 4:\e[0m Creo directory e file di log"
mkdir -p "$LOGS_DIR"
touch \
  "$LOGS_DIR/${MODE}_${PROJECT_NAME}_front_access.log" \
  "$LOGS_DIR/${MODE}_${PROJECT_NAME}_front_error.log" \
  "$LOGS_DIR/${MODE}_${PROJECT_NAME}_api_access.log" \
  "$LOGS_DIR/${MODE}_${PROJECT_NAME}_api_error.log"
echo -e "    ➤ Log in $LOGS_DIR"

# --- 🔌 STEP 5: Trovo socket PHP-FPM ---
echo -e "\n🔌 \e[1;33mSTEP 5:\e[0m Trovo socket PHP-FPM php8.2"
PHP_SOCK=$(find /www/server/php/ -type s -name "*.sock" 2>/dev/null | grep php8.2 | head -n1)
if [[ -z "$PHP_SOCK" || ! -S "$PHP_SOCK" ]]; then
  echo "❌ Socket PHP-FPM non trovato o non valido"
  exit 1
fi
echo -e "    ➤ PHP_SOCK=$PHP_SOCK"

# --- 🔎 STEP 6: Trovo porte libere ---
echo -e "\n🔎 \e[1;33mSTEP 6:\e[0m Trovo porte libere"
find_free_port(){ local p=$1; while lsof -iTCP:$p -sTCP:LISTEN >/dev/null 2>&1; do ((p++)); done; echo $p; }
FRONT_PORT=$(find_free_port 8080)
BACK_PORT=$(find_free_port 8000)
echo -e "    ➤ FRONT_PORT=$FRONT_PORT, BACK_PORT=$BACK_PORT"

echo -e "\n🔧 [SIM $MODE] frontend -> http://localhost:$FRONT_PORT/"
echo -e "🔧 [SIM $MODE] backend  -> http://localhost:$BACK_PORT/"

# --- 🗂️ STEP 7: Preparo directory NGINX ---
echo -e "\n📁 \e[1;33mSTEP 7:\e[0m Creo conf.d, sites-available e sites-enabled"
SITES_AVAIL="$DEV_BASE/sites-available/$MODE"
SITES_ENABLED="$DEV_BASE/sites-enabled/$MODE"
mkdir -p "$DEV_BASE/conf.d" "$SITES_AVAIL" "$SITES_ENABLED"
echo -e "    ➤ conf.d, $SITES_AVAIL, $SITES_ENABLED creati"

# --- ⚙️ STEP 8: Configuro proxy_params.conf ---
echo -e "\n⚙️  \e[1;33mSTEP 8:\e[0m Genero proxy_params.conf se mancante"
if [[ ! -f "$DEV_BASE/conf.d/proxy_params.conf" ]]; then
  cat > "$DEV_BASE/conf.d/proxy_params.conf" <<'EOF'
# proxy_params.conf
proxy_http_version 1.1;
proxy_set_header   Host              \$host;
proxy_set_header   X-Real-IP         \$remote_addr;
proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
proxy_set_header   X-Forwarded-Proto \$scheme;
proxy_redirect     off;
EOF
  echo -e "    ➤ proxy_params.conf generato"
fi

# --- 📄 STEP 9: Genero file VHOST ---
echo -e "\n📄 \e[1;33mSTEP 9:\e[0m Genero $PROJECT_NAME.conf in sites-available"
VHOST_FILE="$SITES_AVAIL/$PROJECT_NAME.conf"
cat > "$VHOST_FILE" <<EOF
server {
    listen       $FRONT_PORT;
    listen       [::]:$FRONT_PORT;
    server_name  _;
    root         /$DEV_DIR/$PROJECT_NAME/frontend/browser;
    index        index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    access_log  $REAL_LOG_DIR/${MODE}/${MODE}_${PROJECT_NAME}_front_access.log;
    error_log   $REAL_LOG_DIR/${MODE}/${MODE}_${PROJECT_NAME}_front_error.log;
}

server {
    listen       $BACK_PORT;
    listen       [::]:$BACK_PORT;
    server_name  _;
    root         /$DEV_DIR/$PROJECT_NAME/backend/public;
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
        fastcgi_param  SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include         fastcgi_params;
        fastcgi_hide_header X-Powered-By;
    }

    location ~ /\\.(?!well-known).* {
        deny all;
    }

    access_log  $REAL_LOG_DIR/${MODE}/${MODE}_${PROJECT_NAME}_api_access.log;
    error_log   $REAL_LOG_DIR/${MODE}/${MODE}_${PROJECT_NAME}_api_error.log;
}
EOF

echo -e "    ➤ VHOST_FILE creato: $VHOST_FILE"

# --- 📂 STEP 9.1: Mostro percorsi usati nel VHOST ---
echo -e "\n📂 \e[1;33mSTEP 9.1:\e[0m Percorsi usati nel VHOST:"
echo -e "    ➤ Frontend root : /$DEV_DIR/$PROJECT_NAME/frontend/browser"
echo -e "    ➤ Backend root  : /$DEV_DIR/$PROJECT_NAME/backend/public"
echo -e "    ➤ Log access FE : $REAL_LOG_DIR/${MODE}/${MODE}_${PROJECT_NAME}_front_access.log"
echo -e "    ➤ Log error  FE : $REAL_LOG_DIR/${MODE}/${MODE}_${PROJECT_NAME}_front_error.log"
echo -e "    ➤ Log access API: $REAL_LOG_DIR/${MODE}/${MODE}_${PROJECT_NAME}_api_access.log"
echo -e "    ➤ Log error  API: $REAL_LOG_DIR/${MODE}/${MODE}_${PROJECT_NAME}_api_error.log"

# --- 🔗 STEP 10: Creo symlink ---
echo -e "\n🔗 \e[1;33mSTEP 10:\e[0m Rigenero symlink in sites-enabled"
rm -f "$SITES_ENABLED"/*.conf
ln -s "$VHOST_FILE" "$SITES_ENABLED/$PROJECT_NAME.conf"
echo -e "    ➤ Symlink creato in $SITES_ENABLED/$PROJECT_NAME.conf"

# --- ✅ STEP 11: Completamento ---
echo -e "\n✅ \e[1;32mSTEP 11:\e[0m Deploy NGINX simulato completato per $PROJECT_NAME (MODE=$MODE)\e[0m"
