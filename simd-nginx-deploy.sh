#!/usr/bin/env bash
#
# simd-nginx-deploy.sh
# Simula il deploy NGINX in locale usando la struttura in deploy/www
# Genera i file .conf con percorsi reali ma li posiziona sotto deploy/www
# Uso: ./simd-nginx-deploy.sh -dev|-prod <percorso_progetto>

set -euo pipefail

# ─── Funzioni ────────────────────────────────────────────────────────────────

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "❌ Questo script va eseguito come root. Ritento con sudo..."
    exec sudo "$0" "$@"
  fi
}

parse_args() {
  echo -e "\n🔍  [SIM] STEP 0: Verifico parametri"
  if [[ "${1:-}" != "-dev" && "${1:-}" != "-prod" ]]; then
    echo "❌ Uso corretto: $0 -dev|-prod <percorso_progetto>"
    exit 1
  fi
  MODE=${1#-}; shift

  if [[ -z "${1:-}" ]]; then
    echo "❌ Specificare percorso del progetto"
    exit 1
  fi
  PROJECT="$1"; shift

  SCRIPT_DIR=$(readlink -f "$(dirname "$0")")
  PROJECT_PATH=$(readlink -f "$PROJECT")
}

verify_project() {
  echo -e "\n🔍  [SIM] STEP 1: Controllo progetto"
  if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "❌ Cartella progetto non trovata: $PROJECT_PATH"
    exit 1
  fi
  FRONTEND_DIR=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_frontend" | head -n1)
  BACKEND_DIR=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_backend"  | head -n1)
  if [[ -z "$FRONTEND_DIR" || -z "$BACKEND_DIR" ]]; then
    echo "❌ Mancano *_frontend o *_backend in $PROJECT_PATH"
    exit 1
  fi
  PROJECT_NAME=$(basename "$FRONTEND_DIR" | cut -d'_' -f1)
}

load_ports_and_php() {
  echo -e "\n📥  [SIM] STEP 2: Carico porte e PHP-FPM socket"
  PORTS_FILE="$SCRIPT_DIR/deploy/assigned_ports.env"
  if [[ ! -f "$PORTS_FILE" ]]; then
    echo "❌ File porte non trovato: $PORTS_FILE"
    exit 1
  fi
  source "$PORTS_FILE"
  export FRONT_PORT BACK_PORT

  PHP_SOCK=$(find /www/server/php/ -type s -name '*.sock' | head -n1)
  if [[ -z "$PHP_SOCK" ]]; then
    echo "❌ Socket PHP-FPM non trovato"
    exit 1
  fi
  export PHP_SOCK
}

setup_simulation_dirs() {
  echo -e "\n🔧  [SIM] STEP 3: Imposto cartelle di simulazione"
  SIM_ROOT="$SCRIPT_DIR/deploy"
  SIM_WWWROOT="$SIM_ROOT/www/wwwroot/$MODE"
  SIM_WWWLOGS="$SIM_ROOT/www/wwwlogs/$MODE"
  SIM_NGINX_CONF="$SIM_ROOT/www/server/nginx/conf"
  SIM_CONF_D="$SIM_NGINX_CONF/conf.d"
  SIM_SA="$SIM_CONF_D/sites-available/$MODE"
  SIM_SE="$SIM_CONF_D/sites-enabled/$MODE"

  mkdir -p \
    "$SIM_WWWROOT" \
    "$SIM_WWWLOGS" \
    "$SIM_CONF_D" \
    "$SIM_SA" \
    "$SIM_SE"
  echo "  ➕ WWWROOT simulato:   $SIM_WWWROOT"
  echo "  ➕ WWWLOGS simulato:   $SIM_WWWLOGS"
  echo "  ➕ conf.d simulato:    $SIM_CONF_D"
  echo "  ➕ sites-available:     $SIM_SA"
  echo "  ➕ sites-enabled:       $SIM_SE"
}

generate_main_nginx_conf() {
  echo -e "\n🔧  [SIM] STEP 4: Creo nginx.conf simulato"
  cat > "$SIM_NGINX_CONF/nginx.conf" <<'EOF'
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
    include conf.d/sites-enabled/*/*.conf;
    include conf.d/sites-available/*/*.conf;
}

stream {
    log_format tcp_format '$time_local|$remote_addr|$protocol|$status|$bytes_sent|$bytes_received|$session_time';
    access_log /www/wwwlogs/tcp-access.log tcp_format;
    error_log  /www/wwwlogs/tcp-error.log;
    include /www/server/panel/vhost/nginx/tcp/*.conf;
}
EOF
}

determine_rel_path() {
  # Se il progetto esiste in /www/wwwroot/$MODE/apps, allora è under apps
  if [[ -d "/www/wwwroot/$MODE/apps/$PROJECT_NAME" ]]; then
    REL_PATH="apps/$PROJECT_NAME"
  else
    REL_PATH="$PROJECT_NAME"
  fi
}

generate_vhost_conf() {
  echo -e "\n📂  [SIM] STEP 5: Generazione VHOST"
  # directory disponibile
  if [[ $REL_PATH == apps/* ]]; then
    SA_DIR="$SIM_SA/apps"
  else
    SA_DIR="$SIM_SA"
  fi
  mkdir -p "$SA_DIR"
  local VF="$SA_DIR/${PROJECT_NAME}.conf"

  cat > "$VF" <<EOF
server {
  listen       $FRONT_PORT;
  listen       [::]:$FRONT_PORT;
  server_name  _;
  access_log   /www/wwwlogs/$MODE/$REL_PATH/${PROJECT_NAME}_front_access.log;
  error_log    /www/wwwlogs/$MODE/$REL_PATH/${PROJECT_NAME}_front_error.log;

  root   /www/wwwroot/$MODE/$REL_PATH/frontend/browser;
  index  index.html;

  location / {
    try_files \$uri \$uri/ /index.html;
  }
}

server {
  listen       $BACK_PORT;
  listen       [::]:$BACK_PORT;
  server_name  _;
  root         /www/wwwroot/$MODE/$REL_PATH/backend/public;
  index        index.php;

  location / {
    try_files \$uri \$uri/ /index.php?\$query_string;
  }

  location ~ ^/index\\.php(/|\$) {
    fastcgi_pass   unix:$PHP_SOCK;
    fastcgi_param  SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    include        fastcgi_params;
  }

  location ~ \\.php\$ {
    return 404;
  }

  access_log   /www/wwwlogs/$MODE/$REL_PATH/${PROJECT_NAME}_api_access.log;
  error_log    /www/wwwlogs/$MODE/$REL_PATH/${PROJECT_NAME}_api_error.log;
}
EOF

  echo "  ➕ VHOST creato: $VF"
}

create_log_files() {
  echo -e "\n🗂️   [SIM] STEP 6: Creo file di log"
  local LOGDIR="$SIM_WWWLOGS/$REL_PATH"
  mkdir -p "$LOGDIR"
  for f in front_access front_error api_access api_error; do
    touch "$LOGDIR/${PROJECT_NAME}_${f}.log"
  done
}

print_summary() {
  echo -e "\nℹ️   [SIM] STEP 7: Riepilogo simulazione"
  cat <<EOF
  • Mode:           $MODE
  • Progetto:       $PROJECT_PATH
  • Nome:           $PROJECT_NAME
  • Sim root:       $SIM_ROOT
  • nginx.conf sim: $SIM_NGINX_CONF/nginx.conf
  • vhost sim:      $SIM_SA/${PROJECT_NAME}.conf
  • WWWROOT real:   /www/wwwroot/$MODE/$REL_PATH
  • WWWLOGS real:   /www/wwwlogs/$MODE/$REL_PATH
  • FRONT_PORT:     $FRONT_PORT
  • BACK_PORT:      $BACK_PORT
EOF
  echo -e "\n✅  Simulazione completata: i file sono in $SIM_NGINX_CONF"
}

# ─── Main ────────────────────────────────────────────────────────────────────

require_root "$@"
parse_args "$@"
verify_project
load_ports_and_php
setup_simulation_dirs
generate_main_nginx_conf
determine_rel_path
generate_vhost_conf
create_log_files
print_summary
