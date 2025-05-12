#!/usr/bin/env bash
#
# simd-nginx-deploy.sh
# Simula il deploy NGINX in locale usando la struttura in deploy/www
# Uso: ./simd-nginx-deploy.sh -dev|-prod <percorso_progetto>

set -euo pipefail

# ─── Funzioni ────────────────────────────────────────────────────────────────

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "❌ Questo script deve essere eseguito con i permessi di root. Esegui con sudo."
    exec sudo "$0" "$@"
  fi
}

step0_parse_args() {
  echo -e "\n🔍  [SIM] STEP 0: Verifico parametri"
  if [[ "${1:-}" != "-dev" && "${1:-}" != "-prod" ]]; then
    echo "❌ Uso corretto: $0 -dev|-prod <percorso_progetto>"
    exit 1
  fi
  MODE=${1#-}; shift
  if [ -z "${1:-}" ]; then
    echo "❌ Specificare nome progetto"
    exit 1
  fi
  PROJECT="$1"; shift

  SCRIPT_DIR=$(readlink -f "$(dirname "$0")")
  SIM_ROOT="$SCRIPT_DIR/deploy"
  PROJECT_PATH=$(readlink -f "$PROJECT")
}

step1_verify_project() {
  echo -e "\n🔍  [SIM] STEP 1: Verifica cartella progetto"
  if [ ! -d "$PROJECT_PATH" ]; then
    echo "❌ La cartella non esiste: $PROJECT_PATH"
    exit 1
  fi
  FRONTEND_DIR=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_frontend" | head -n1)
  BACKEND_DIR=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_backend"  | head -n1)
  if [ -z "$FRONTEND_DIR" ] || [ -z "$BACKEND_DIR" ]; then
    echo "❌ Mancano le cartelle *_frontend o *_backend"
    exit 1
  fi
  PROJECT_NAME=$(basename "$FRONTEND_DIR" | cut -d'_' -f1)
}

step2_load_ports_php() {
  echo -e "\n📥  [SIM] STEP 2: Carico porte e PHP-FPM socket"
  PORTS_FILE="$SIM_ROOT/assigned_ports.env"
  if [ ! -f "$PORTS_FILE" ]; then
    echo "❌ File porte non trovato: $PORTS_FILE"
    exit 1
  fi
  source "$PORTS_FILE"
  export FRONT_PORT BACK_PORT

  PHP_SOCK=$(find /www/server/php/ -type s -name '*.sock' 2>/dev/null | head -n1)
  if [ -z "$PHP_SOCK" ]; then
    echo "❌ Socket PHP-FPM non trovato"
    exit 1
  fi
  export PHP_SOCK
}

step3_setup_simulation() {
  echo -e "\n🔌  [SIM] STEP 3: Preparo simulation dirs"
  SIM_WWWROOT="$SIM_ROOT/www/wwwroot/$MODE"
  SIM_WWWLOGS="$SIM_ROOT/www/wwwlogs/$MODE"
  SIM_NGINX_CONF="$SIM_ROOT/www/server/nginx/conf"
  CONF_D="$SIM_NGINX_CONF/conf.d"
  SITES_AVAIL="$CONF_D/sites-available/$MODE"
  SITES_ENABLED="$CONF_D/sites-enabled/$MODE"

  mkdir -p "$SIM_WWWROOT" "$SIM_WWWLOGS" \
           "$SIM_NGINX_CONF" "$CONF_D" \
           "$SITES_AVAIL" "$SITES_ENABLED"
  echo "  ➕ Simulated WWWROOT: $SIM_WWWROOT"
  echo "  ➕ Simulated WWWLOGS: $SIM_WWWLOGS"
  echo "  ➕ Simulated conf.d:   $CONF_D"
  echo "  ➕ sites-available:    $SITES_AVAIL"
  echo "  ➕ sites-enabled:      $SITES_ENABLED"

  SIM_NGINX_MAIN="$SIM_NGINX_CONF/nginx.conf"
  if [ ! -f "$SIM_NGINX_MAIN" ]; then
    echo "  ➕ Creo nginx.conf simulato"
    cat > "$SIM_NGINX_MAIN" <<'EOF'
user  www www;
worker_processes auto;
pid        /www/server/nginx/logs/nginx.pid;
error_log  /www/server/nginx/logs/error.log crit;

events {
    worker_connections 10240;
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

    include /www/server/panel/vhost/nginx/*.conf;
    include conf.d/*.conf;
    include conf.d/sites-enabled/*/*.conf;
}

stream {
    log_format tcp_format '$time_local|$remote_addr|$protocol|$status|$bytes_sent|$bytes_received|$session_time|$upstream_addr|$upstream_bytes_sent|$upstream_bytes_received|$upstream_connect_time';
    access_log /www/wwwlogs/tcp-access.log tcp_format;
    error_log /www/wwwlogs/tcp-error.log;
    include /www/server/panel/vhost/nginx/tcp/*.conf;
}
EOF
  fi
}

step4_detect_type() {
  echo -e "\n📌  [SIM] STEP 4: Tipo di progetto"
  IS_MAIN="n"; VALID=false
  if [ -f "$SIM_ROOT/is_main.env" ]; then
    source "$SIM_ROOT/is_main.env"
    IS_MAIN=${IS_MAIN,,}
    [[ "$IS_MAIN" == "y" || "$IS_MAIN" == "n" ]] && VALID=true
  fi
  if [ "$VALID" = false ]; then
    read -rp $'\n❓  È progetto principale? [y/N]: ' IS_MAIN
    IS_MAIN=${IS_MAIN:-n}; IS_MAIN=${IS_MAIN,,}
    if [[ "$IS_MAIN" != "y" && "$IS_MAIN" != "n" ]]; then
      echo "❌ Risposta non valida"
      exit 1
    fi
    echo "IS_MAIN=$IS_MAIN" > "$SIM_ROOT/is_main.env"
  fi

  if [[ "$IS_MAIN" == "y" ]]; then
    REL_PATH="$PROJECT_NAME"
    VHOST_SUBDIR=""
  else
    REL_PATH="apps/$PROJECT_NAME"
    VHOST_SUBDIR="apps"
  fi
}

step5_generate_vhost() {
  echo -e "\n📂  [SIM] STEP 5: Generazione VHOST"
  SA_DIR="$CONF_D/sites-available/$MODE${VHOST_SUBDIR:+/$VHOST_SUBDIR}"
  mkdir -p "$SA_DIR"
  VHOST_FILE="$SA_DIR/${PROJECT_NAME}.conf"

  cat > "$VHOST_FILE" <<EOF
server {
  listen       $FRONT_PORT;
  listen       [::]:$FRONT_PORT;
  server_name  _;
  access_log   $SIM_WWWLOGS/$REL_PATH/${PROJECT_NAME}_front_access.log;
  error_log    $SIM_WWWLOGS/$REL_PATH/${PROJECT_NAME}_front_error.log;

  root   $SIM_WWWROOT/$REL_PATH/frontend/browser;
  index  index.html;

  location / {
    try_files \$uri \$uri/ /index.html;
  }
}

server {
  listen       $BACK_PORT;
  listen       [::]:$BACK_PORT;
  server_name  _;
  root         $SIM_WWWROOT/$REL_PATH/backend/public;
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

  access_log   $SIM_WWWLOGS/$REL_PATH/${PROJECT_NAME}_api_access.log;
  error_log    $SIM_WWWLOGS/$REL_PATH/${PROJECT_NAME}_api_error.log;
}
EOF

  echo "  ➕ VHOST creato: $VHOST_FILE"
}

step6_setup_logs() {
  echo -e "\n🗂️   [SIM] STEP 6: Creazione log"
  LOG_DIR="$SIM_WWWLOGS/$REL_PATH"
  mkdir -p "$LOG_DIR"
  for f in front_access front_error api_access api_error; do
    FILE="$LOG_DIR/${PROJECT_NAME}_${f}.log"
    if [ ! -f "$FILE" ]; then
      touch "$FILE"
      echo "  ➕ Creo file log: $FILE"
    fi
  done
}

step7_summary() {
  echo -e "\nℹ️   [SIM] STEP 7: Riepilogo simulazione"
  cat <<EOF
  Mode:            $MODE
  Progetto:        $PROJECT_PATH
  Nome:            $PROJECT_NAME
  Sim root:        $SIM_ROOT
  WWWROOT (sim):   $SIM_WWWROOT
  WWWLOGS (sim):   $SIM_WWWLOGS
  conf.d:          $CONF_D
  sites-avail:     $CONF_D/sites-available/$MODE
  sites-enabled:   $CONF_D/sites-enabled/$MODE
  FRONT_PORT:      $FRONT_PORT
  BACK_PORT:       $BACK_PORT
EOF
}

# ─── Main ───────────────────────────────────────────────────────────────────

require_root "$@"
step0_parse_args "$@"
step1_verify_project
step2_load_ports_php
step3_setup_simulation
step4_detect_type
step5_generate_vhost
step6_setup_logs
step7_summary
