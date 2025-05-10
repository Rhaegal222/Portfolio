#!/bin/bash
#
# simd-nginx-deploy.sh
# Simula il deploy NGINX in locale usando la struttura in deploy/www
# Genera file .conf pronti per la produzione con path reali
# Uso: ./simd-nginx-deploy.sh -dev|-prod

set -euo pipefail

########## STEP 0: Verifica parametro ##########
echo -e "\n🔍 STEP 0: Verifico parametro (-dev o -prod)"
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
echo -e "\n🚀 [STEP 0] Modalità: $MODE"

########## STEP 1: Configurazione percorsi ##########
echo -e "\n🔧 STEP 1: Configuro i percorsi di lavoro"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DEPLOY_ROOT="$SCRIPT_DIR/deploy/www"
DEV_WWWROOT="$DEPLOY_ROOT/wwwroot/$MODE"
LOGS_BASE="$DEPLOY_ROOT/wwwlogs"
REAL_LOG_DIR="/www/wwwlogs"
# assigned_ports.env è dentro deploy
PORTS_FILE="$SCRIPT_DIR/deploy/assigned_ports.env"

echo "    • SCRIPT_DIR    = $SCRIPT_DIR"
echo "    • DEPLOY_ROOT   = $DEPLOY_ROOT"
echo "    • DEV_WWWROOT   = $DEV_WWWROOT"
echo "    • LOGS_BASE     = $LOGS_BASE"
echo "    • REAL_LOG_DIR  = $REAL_LOG_DIR"
echo "    • PORTS_FILE    = $PORTS_FILE"

if [[ ! -d "$DEV_WWWROOT" ]]; then
  echo "❌ [ERROR] Directory di deploy non trovata: $DEV_WWWROOT"
  echo "   ➤ Esegui prima sima-init-structure.sh"
  exit 1
fi

echo "✅ [STEP 1] Percorsi validi"

########## STEP 2: Caricamento porte ##########
echo -e "\n🔢 STEP 2: Carico porte da $PORTS_FILE"
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
echo "✅ [STEP 2] Porte caricate correttamente"

########## STEP 3: Rilevamento progetto ##########
echo -e "\n🔍 STEP 3: Individuo cartella del progetto"
if [[ -d "$DEV_WWWROOT/apps" && -n "$(ls -A "$DEV_WWWROOT/apps")" ]]; then
  PROJECT_PARENT="$DEV_WWWROOT/apps"
  DEV_DIR_PART="www/wwwroot/$MODE/apps"
  echo "    • Uso apps directory: $PROJECT_PARENT"
else
  PROJECT_PARENT="$DEV_WWWROOT"
  DEV_DIR_PART="www/wwwroot/$MODE"
  echo "    • Uso root directory: $PROJECT_PARENT"
fi
PROJECT_NAME=$(find "$PROJECT_PARENT" -mindepth 1 -maxdepth 1 -type d | head -n1 | xargs -n1 basename)
if [[ -z "$PROJECT_NAME" ]]; then
  echo "❌ [ERROR] Nessun progetto trovato in $PROJECT_PARENT"
  exit 1
fi
echo "    • Progetto trovato: $PROJECT_NAME"
echo "✅ [STEP 3] Progetto individuato"

########## STEP 4: Preparazione log ##########
echo -e "\n🗂️ STEP 4: Creo directory e file di log"
LOGS_DIR="$LOGS_BASE/$MODE"
mkdir -p "$LOGS_DIR"
touch \
  "$LOGS_DIR/${MODE}_${PROJECT_NAME}_front_access.log" \
  "$LOGS_DIR/${MODE}_${PROJECT_NAME}_front_error.log" \
  "$LOGS_DIR/${MODE}_${PROJECT_NAME}_api_access.log" \
  "$LOGS_DIR/${MODE}_${PROJECT_NAME}_api_error.log"
echo "    • LogDir    = $LOGS_DIR"
echo "✅ [STEP 4] Log pronti"

########## STEP 5: PHP-FPM socket ##########
echo -e "\n🔌 STEP 5: Trovo socket PHP-FPM php8.2"
PHP_SOCK=$(find /www/server/php/ -type s -name '*.sock' 2>/dev/null | grep php8.2 | head -n1)
if [[ -z "$PHP_SOCK" || ! -S "$PHP_SOCK" ]]; then
  echo "❌ [ERROR] Socket PHP-FPM php8.2 non trovato"
  exit 1
fi
echo "    • PHP_SOCK = $PHP_SOCK"
echo "✅ [STEP 5] Socket trovato"

########## STEP 6: Setup cartelle NGINX ##########
echo -e "\n📁 STEP 6: Preparo conf.d, sites-available, sites-enabled"
NGINX_CONF_ROOT="$DEPLOY_ROOT/server/nginx/conf"
SITES_AVAIL="$NGINX_CONF_ROOT/sites-available/$MODE"
SITES_ENABLED="$NGINX_CONF_ROOT/sites-enabled/$MODE"
mkdir -p "$NGINX_CONF_ROOT/conf.d" "$SITES_AVAIL" "$SITES_ENABLED"
echo "    • NGINX_CONF_ROOT = $NGINX_CONF_ROOT"
echo "    • SITES_AVAIL     = $SITES_AVAIL"
echo "    • SITES_ENABLED   = $SITES_ENABLED"

# proxy_params.conf
if [[ ! -f "$NGINX_CONF_ROOT/conf.d/proxy_params.conf" ]]; then
  cat > "$NGINX_CONF_ROOT/conf.d/proxy_params.conf" << 'EOF'
# proxy_params.conf
proxy_http_version 1.1;
proxy_set_header   Host              $host;
proxy_set_header   X-Real-IP         $remote_addr;
proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header   X-Forwarded-Proto $scheme;
proxy_redirect     off;
EOF
  echo "    • proxy_params.conf generato"
fi
echo "✅ [STEP 6] Cartelle NGINX pronte"

########## STEP 7: Generazione VHOST ##########
echo -e "\n📝 STEP 7: Genero file VHOST"
VHOST_FILE="$SITES_AVAIL/${PROJECT_NAME}.conf"
cat > "$VHOST_FILE" <<EOF
server {
    listen       $FRONT_PORT;
    listen       [::]:$FRONT_PORT;
    server_name  _;
    root         /$DEV_DIR_PART/$PROJECT_NAME/frontend/browser;
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
    root         /$DEV_DIR_PART/$PROJECT_NAME/backend/public;
    index        index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ ^/index\\.php(/|$) {
        fastcgi_pass   unix:$PHP_SOCK;
        fastcgi_param  SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include        fastcgi_params;
    }

    location ~ /\\.(?!well-known).* {
        deny all;
    }

    access_log  $REAL_LOG_DIR/$MODE/${PROJECT_NAME}_api_access.log;
    error_log   $REAL_LOG_DIR/$MODE/${PROJECT_NAME}_api_error.log;
}
EOF

echo "    • VHOST_FILE = $VHOST_FILE"
echo "✅ [STEP 7] VHOST generato"

########## STEP 8: Visualizzazione percorsi ##########
echo -e "\n📂 STEP 8: Percorsi usati nel VHOST:"
echo "    • Frontend root     = /$DEV_DIR_PART/$PROJECT_NAME/frontend/browser"
echo "    • Backend root      = /$DEV_DIR_PART/$PROJECT_NAME/backend/public"
echo "    • Log front access  = $REAL_LOG_DIR/$MODE/${PROJECT_NAME}_front_access.log"
echo "    • Log front error   = $REAL_LOG_DIR/$MODE/${PROJECT_NAME}_front_error.log"
echo "    • Log API access    = $REAL_LOG_DIR/$MODE/${PROJECT_NAME}_api_access.log"
echo "    • Log API error     = $REAL_LOG_DIR/$MODE/${PROJECT_NAME}_api_error.log"
echo "✅ [STEP 8] Percorsi confermati"

########## STEP 9: Attivazione VHOST ##########
echo -e "\n🔗 STEP 9: Creo symlink in sites-enabled"
rm -f "$SITES_ENABLED"/*.conf
ln -s "$VHOST_FILE" "$SITES_ENABLED/$PROJECT_NAME.conf"
echo "    • Symlink creato = $SITES_ENABLED/$PROJECT_NAME.conf"
echo "✅ [STEP 9] Symlink attivo"

########## STEP 10: Fine ##########
echo -e "\n🎉 STEP 10: Deploy NGINX simulato completato per $PROJECT_NAME (MODE=$MODE)"