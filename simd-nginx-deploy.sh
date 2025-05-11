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
echo -e "\n🔍  \e[1;32m[SIM]\e[0m \e[1;33mSTEP 0:\e[0m Verifico modalità di esecuzione"
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
echo -e "\n🔍  \e[1;32m[SIM]\e[0m \e[1;33mSTEP 1:\e[0m Verifica cartella del progetto"
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

PORTS_FILE="$SCRIPT_DIR/deploy/assigned_ports.env"

# 📥 Carico porte e le espongo
if [ ! -f "$PORTS_FILE" ]; then
  echo "❌ File porte non trovato: $PORTS_FILE"
  exit 1
fi
source "$PORTS_FILE"
export FRONT_PORT BACK_PORT

# socket PHP-FPM (se serve)
PHP_SOCK=$(find /www/server/php/ -type s -name '*.sock' 2>/dev/null | head -n1)
if [ -z "$PHP_SOCK" ]; then
  echo "❌ Socket PHP-FPM non trovato"
  exit 1
fi
export PHP_SOCK

# ─── Radice della simulazione ───
DEPLOY_ROOT="$SCRIPT_DIR/deploy"

# ─── Percorsi Reali ───
SERVER="/www/server"
WWWROOT="/www/wwwroot/$MODE"
WWWLOGS="/www/wwwlogs/$MODE"
DIR_NGINX_CONF="$SERVER/nginx/conf"
SITES_AVAIL="$DIR_NGINX_CONF/sites-available/$MODE"
SITES_ENABLED="$DIR_NGINX_CONF/sites-enabled/$MODE"
NGINX_CONF="$DIR_NGINX_CONF/nginx.conf"
CONF_D="$DIR_NGINX_CONF/conf.d"
VHOST_FILE="$SITES_AVAIL/${PROJECT_NAME}.conf"

# 📂 STEP 2: Directory per VHOST
echo -e "\n🔌  \e[1;32m[SIM]\e[0m \e[1;33mSTEP 2:\e[0m Verifica directory per il VHOST (simulazione)"
if [ ! -d "$DEPLOY_ROOT/$SITES_AVAIL" ]; then
  echo "  ➕ Creo $DEPLOY_ROOT/$SITES_AVAIL"
  mkdir -p "$DEPLOY_ROOT/$SITES_AVAIL"
fi

# 🔧 STEP 3: nginx.conf simulato
echo -e "\n🔧  \e[1;32m[SIM]\e[0m \e[1;33mSTEP 3:\e[0m Verifica file nginx.conf (simulazione)"
if [ ! -f "$DEPLOY_ROOT$NGINX_CONF" ]; then
  echo -e "  ➕ Creo $DEPLOY_ROOT$NGINX_CONF"
  mkdir -p "$(dirname "$DEPLOY_ROOT$NGINX_CONF")"
cat > "$DEPLOY_ROOT$NGINX_CONF" <<'EOF'
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
    ssl_ciphers         'ECDHE-ECDSA-CHACHA20-POLY1305:...'; # Usa la stringa cifrata adeguata

    include conf.d/*.conf;
    include sites-enabled/dev/*.conf;
    include sites-enabled/prod/*.conf;

    include /www/server/panel/vhost/nginx/*.conf;
    include /www/server/panel/vhost/nginx/dev/*.conf;
    include /www/server/panel/vhost/nginx/prod/*.conf;
}

stream {
    log_format tcp_format '$time_local|$remote_addr|$protocol|$status|$bytes_sent|$bytes_received|$session_time|$upstream_addr|$upstream_bytes_sent|$upstream_bytes_received|$upstream_connect_time';
  
    access_log /www/wwwlogs/tcp-access.log tcp_format;
    error_log /www/wwwlogs/tcp-error.log;
    include /www/server/panel/vhost/nginx/tcp/*.conf;
}
EOF
fi

# STEP 3: REL_PATH
if [[ -d "$DEPLOY_ROOT$WWWROOT/apps/$PROJECT_NAME" ]]; then
  REL_PATH="apps/$PROJECT_NAME"
  # useremo alias per il frontend
  FRONT_ROOT=""  
  FRONT_LOC=$(cat <<EOF
  # redirect /$REL_PATH → /$REL_PATH/
  location = /$REL_PATH {
    return 301 /$REL_PATH/;
  }

  # SPA sotto /$REL_PATH/
  location /$REL_PATH/ {
    alias $WWWROOT/$REL_PATH/frontend/browser/;
    index index.html;
    try_files \$uri \$uri/ /$REL_PATH/index.html;
  }
EOF
)
else
  REL_PATH="$PROJECT_NAME"
  # root “normale” per il principale
  FRONT_ROOT="  root   $WWWROOT/$REL_PATH/frontend/browser;
  index  index.html;"
  FRONT_LOC=$(cat <<EOF

  location / {
    try_files \$uri \$uri/ /index.html;
  }
EOF
)
fi

# STEP 4: genero il VHOST
cat > "$DEPLOY_ROOT$VHOST_FILE" <<EOF
server {
  listen       $FRONT_PORT;
  listen       [::]:$FRONT_PORT;
  server_name  _;
  access_log   $WWWLOGS/$PROJECT_NAME/${PROJECT_NAME}_front_access.log;
  error_log    $WWWLOGS/$PROJECT_NAME/${PROJECT_NAME}_front_error.log;
$FRONT_ROOT
$FRONT_LOC
}

server {
  listen       $BACK_PORT;
  listen       [::]:$BACK_PORT;
  server_name  _;
  root         $WWWROOT/$REL_PATH/backend/public;
  index        index.php;

  location / {
    try_files \$uri \$uri/ /index.php?\$query_string;
  }

  location ~ ^/index\\.php(/|\$) {
    fastcgi_pass   unix:$PHP_SOCK;
    fastcgi_param  SCRIPT_FILENAME $WWWROOT/$REL_PATH/backend/public\$fastcgi_script_name;
    include        fastcgi_params;
  }

  location ~ /\\.(?!well-known).* { deny all; }

  access_log  $WWWLOGS/$PROJECT_NAME/${PROJECT_NAME}_api_access.log;
  error_log   $WWWLOGS/$PROJECT_NAME/${PROJECT_NAME}_api_error.log;
}
EOF

# Determina se il progetto è sotto "apps"
if [[ -d "$DEPLOY_ROOT$WWWROOT/apps/$PROJECT_NAME" ]]; then
  REL_PATH="apps/$PROJECT_NAME"
  FRONT_LOC=$(cat <<EOF
  # redirect /$REL_PATH → /$REL_PATH/
  location = /$REL_PATH {
    return 301 /$REL_PATH/;
  }

  # SPA sotto /$REL_PATH/
  location /$REL_PATH/ {
    alias $WWWROOT/$REL_PATH/frontend/browser/;
    index index.html;
    try_files \$uri \$uri/ /$REL_PATH/index.html;
  }
EOF
)
else
  REL_PATH="$PROJECT_NAME"
  FRONT_ROOT="  root   $WWWROOT/$REL_PATH/frontend/browser;
  index  index.html;"
  FRONT_LOC=$(cat <<EOF

  location / {
    try_files \$uri \$uri/ /index.html;
  }
EOF
)
fi

# Creo la directory dei log per il progetto (in base alla struttura)
echo -e "\n🗂️   \e[1;33mSTEP 5:\e[0m Creazione directory e file di log (simulazione)"
SIM_LOG_DIR="$DEPLOY_ROOT$WWWLOGS/$PROJECT_NAME"

# Crea la directory dei log se non esiste
if [ ! -d "$SIM_LOG_DIR" ]; then
  echo "  ➕ Creo directory log: $SIM_LOG_DIR"
  mkdir -p "$SIM_LOG_DIR"
else
  echo "  ✅ Directory log già presente: $SIM_LOG_DIR"
fi

# Elenco dei file di log da creare
LOG_FILES=( "${PROJECT_NAME}_front_access.log" "${PROJECT_NAME}_front_error.log" "${PROJECT_NAME}_api_access.log" "${PROJECT_NAME}_api_error.log" )

# Creazione dei file di log se non esistono
for LOG_FILE in "${LOG_FILES[@]}"; do
  FULL_PATH="$SIM_LOG_DIR/$LOG_FILE"
  if [ ! -f "$FULL_PATH" ]; then
    echo "  ➕ Creo file log: $FULL_PATH"
    touch "$FULL_PATH"
  else
    echo "  ✅ File log già presente: $FULL_PATH"
  fi
done


# 📜 STEP 6: Riepilogo variabili
echo -e "\nℹ️   \e[1;33mSTEP 6:\e[0m Riepilogo variabili di deploy"
echo -e "  ➤  Modalità:        \e[1;33m$MODE\e[0m"
echo -e "  ➤  Progetto:        \e[1;33m$PROJECT\e[0m"
echo -e "  ➤  Nome:            \e[1;33m$PROJECT_NAME\e[0m"
echo -e "  ➤  SCRIPT:          \e[1;33m$SCRIPT_DIR\e[0m"
echo -e "  ➤  DEPLOY:          \e[1;33m$DEPLOY_ROOT\e[0m"
echo -e "  ➤  WWWROOT:         \e[1;33m$WWWROOT\e[0m"
echo -e "  ➤  LOGS:            \e[1;33m$WWWLOGS\e[0m"
echo -e "  ➤  PHP_SOCK:        \e[1;33m$PHP_SOCK\e[0m"
echo -e "  ➤  nginx.conf:      \e[1;33m$NGINX_CONF\e[0m"
echo -e "  ➤  sites-available: \e[1;33m$SITES_AVAIL\e[0m"
echo -e "  ➤  sites-enabled:   \e[1;33m$SITES_ENABLED\e[0m"
echo -e "  ➤  vhost file:      \e[1;33m$VHOST_FILE\e[0m"
echo -e "  ➤  FRONT_PORT:      \e[1;33m$FRONT_PORT\e[0m"
echo -e "  ➤  BACK_PORT:       \e[1;33m$BACK_PORT\e[0m"

echo -e "\n✅  Simulazione completa: i file sono pronti in $DEPLOY_ROOT/server/nginx/conf"
