#!/bin/bash
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

echo -e "\n🔍  \e[1;33mSTEP 1:\e[0m \e[1;32m[SIM]\e[0m Verifica cartella del progetto"
if [ ! -d "$PROJECT_PATH" ]; then
  echo "❌ La cartella del progetto non esiste: $PROJECT_PATH"
  exit 1
fi

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
DEPLOY_ROOT="$SCRIPT_DIR/deploy"
PORTS_FILE="$DEPLOY_ROOT/assigned_ports.env"

# ─── Percorsi di deploy ───
WWWROOT="www/wwwroot/$MODE"
WWWLOGS="www/wwwlogs"
NGINX_CONF_ROOT="www/server/nginx/conf"

# ─── Percorsi di configurazione NGINX ───
CONF_D="$NGINX_CONF_ROOT/conf.d"
NGINX_CONF="$NGINX_CONF_ROOT/nginx.conf"
SITES_AVAIL="$NGINX_CONF_ROOT/sites-available/$MODE"
SITES_ENABLED="$NGINX_CONF_ROOT/sites-enabled/$MODE"

echo -e "\n🔌  \e[1;33mSTEP 3:\e[0m Trova socket PHP-FPM php8.2"
PHP_SOCK=$(find /www/server/php/ -type s -name '*.sock' 2>/dev/null | grep php8.2 | head -n1)
if [[ -z "$PHP_SOCK" ]]; then echo "❌ [ERROR] Socket PHP-FPM php8.2 non trovato"; exit 1; fi


# Genera il file nginx.conf
echo -e "\n🔌  \e[1;33mSTEP 3:\e[0m \e[1;32m[SIM]\e[0m Trova socket PHP-FPM php8.2"
# Verifica se nginx.conf esiste, se no crealo
if [ ! -f "$DEPLOY_ROOT/$NGINX_CONF" ]; then
  echo -e "\n🔧 Creazione del file $DEPLOY_ROOT/$NGINX_CONF"
  cat > "$DEPLOY_ROOT/$NGINX_CONF" <<'EOF'
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

echo -e "\n📂  \e[1;33mSTEP 2:\e[0m \e[1;32m[SIM]\e[0m Creo directory per il VHOST"
rm -rf "$DEPLOY_ROOT/$SITES_AVAIL"
mkdir -p "$DEPLOY_ROOT/$SITES_AVAIL"
VHOST_FILE="$DEPLOY_ROOT/$SITES_AVAIL/${PROJECT_NAME}.conf"

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

if [ ! -d "$SITES_ENABLED" ]; then
  echo "La cartella /$SITES_ENABLED non esiste, la creo ora."
  mkdir -p "/$SITES_ENABLED"
fi

echo -e "\n🔗  \e[1;33mSTEP 5:\e[0m Creo symlink in sites-enabled"
ln -sf "$VHOST_FILE" "/$SITES_ENABLED/$PROJECT_NAME.conf"

# Verifica se tutte le variabili essenziali sono impostate correttamente
echo -e "\n🔍  \e[1;33mSTEP 4:\e[0m Verifica variabili"

# Verifica che la cartella del progetto esista
if [ ! -d "$PROJECT_PATH" ]; then
  echo "❌ La cartella del progetto non esiste: $PROJECT_PATH"
  exit 1
fi

# Verifica che la cartella WWWROOT esista
if [ ! -d "$DEPLOY_ROOT/$WWWROOT" ]; then
  echo "❌ La cartella WWWROOT non esiste: $WWWROOT"
  exit 1
fi

# Verifica che il file delle porte esista
if [ ! -f "$PORTS_FILE" ]; then
  echo "❌ Il file delle porte non esiste: $PORTS_FILE"
  exit 1
fi

source "$PORTS_FILE"

# Verifica che le porte siano state caricate correttamente
if [[ -z "${FRONT_PORT:-}" || -z "${BACK_PORT:-}" ]]; then
  echo "❌ FRONT_PORT o BACK_PORT mancanti nel file delle porte: $PORTS_FILE"
  exit 1
fi

# Verifica che il progetto sia valido e abbia il nome corretto
if [ -z "$PROJECT_NAME" ]; then
  echo "❌ Impossibile determinare il nome del progetto"
  exit 1
fi

# Verifica che i log siano configurati correttamente
if [ ! -d "$DEPLOY_ROOT/$WWWLOGS" ]; then
  echo "❌ La cartella dei log non esiste: $WWWLOGS"
  exit 1
fi

# Verifica che PHP_FPM sia disponibile
if [[ -z "$PHP_SOCK" ]]; then
  echo "❌ PHP-FPM non è configurato correttamente, socket PHP non trovato: $PHP_SOCK"
  exit 1
fi

# Verifica che il file di configurazione di NGINX esista
if [ ! -f "$DEPLOY_ROOT/$NGINX_CONF" ]; then
  echo "❌ Il file di configurazione di NGINX non esiste: $DEPLOY_ROOT/$NGINX_CONF"
  exit 1
fi

# Verifica che il file VHOST sia stato generato
if [ ! -f "$VHOST_FILE" ]; then
  echo "❌ Il file VHOST non è stato generato: $VHOST_FILE"
  exit 1
fi

echo -e "✅  \e[1;32mTutte le variabili sono state verificate correttamente\e[0m"

echo -e "\nℹ️   \e[1;33mSTEP 1:\e[0m Riepilogo variabili di deploy\n"
echo -e "  ➤  Modalità di deploy:     \e[1;33m$MODE\e[0m"
echo -e "  ➤  Progetto:               \e[1;33m$PROJECT\e[0m"
echo -e "  ➤  Nome progetto:          \e[1;33m$PROJECT_NAME\e[0m"
echo -e "  ➤  Percorso progetto:      \e[1;33m$PROJECT_PATH\e[0m"
echo -e "  ➤  SCRIPT_DIR:             \e[1;36m$SCRIPT_DIR\e[0m"
echo -e "  ➤  DEPLOY (sim root):      \e[1;36m$DEPLOY\e[0m"
echo -e "  ➤  WWWROOT (source):       \e[1;36m$WWWROOT\e[0m"
echo -e "  ➤  WWWLOGS (sim logs):     \e[1;36m$WWWLOGS\e[0m"
echo -e "  ➤  PORTS_FILE:             \e[1;36m$PORTS_FILE\e[0m"
echo -e "  ➤  REL_PATH:               \e[1;33m$REL_PATH\e[0m (usato nel VHOST)"
echo -e "  ➤  DEV_DIR_PART:           \e[1;33mwww/wwwroot/$MODE\e[0m"
echo -e "  ➤  LOGS_DIR (tmp logs):    \e[1;36m$LOGS_DIR\e[0m"
echo -e "  ➤  REAL_LOG_DIR (finale):  \e[1;36m$REAL_LOG_DIR\e[0m"
echo -e "  ➤  FRONT_PORT:             \e[1;35m$FRONT_PORT\e[0m"
echo -e "  ➤  BACK_PORT:              \e[1;35m$BACK_PORT\e[0m"
echo -e "  ➤  PHP_SOCK:               \e[1;35m$PHP_SOCK\e[0m"
echo -e "  ➤  NGINX_CONF_ROOT:        \e[1;36m$NGINX_CONF_ROOT\e[0m"
echo -e "  ➤  SITES_AVAIL:            \e[1;36m$SITES_AVAIL\e[0m"
echo -e "  ➤  SITES_ENABLED:          \e[1;36m$SITES_ENABLED\e[0m"
echo -e "  ➤  VHOST_FILE:             \e[1;36m$VHOST_FILE\e[0m\n"

# ⚠️ Conferma per procedere
read -rp $'\n\e[1;33m⚠️   Confermi di procedere con il deploy? [\e[1;32my/\e[1;31mN\e[0m] (default N): ' CONFIRM
CONFIRM=${CONFIRM:-n}
CONFIRM=${CONFIRM,,}
if [[ "$CONFIRM" != "y" ]]; then
  echo "⏹️  Operazione annullata"
  exit 1
fi

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

########## STEP 6: Trovo socket PHP-FPM #########

########## STEP 7: Generazione nginx.conf ##########
echo -e "\n⚙️ STEP 7: Configurazione di nginx.conf"


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

mkdir -p "$NGINX_CONF_ROOT/conf.d" "$SITES_AVAIL" "$SITES_ENABLED"
echo "    • NGINX_CONF_ROOT = $NGINX_CONF_ROOT"
echo "    • SITES_AVAIL     = $SITES_AVAIL"
echo "    • SITES_ENABLED   = $SITES_ENABLED"

########## STEP 12: Fine ##########
echo -e "\n🎉 STEP 12: Deploy NGINX simulato completato per $PROJECT_NAME (MODE=$MODE)"
