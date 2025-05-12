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
  echo -e "\n🔍  \e[1;32m[SIM]\e[0m \e[1;33mSTEP 0:\e[0m Verifico parametri"
  if [[ "${1:-}" != "-dev" && "${1:-}" != "-prod" ]]; then
    echo "❌ Uso corretto: $0 -dev|-prod <percorso_progetto>"
    exit 1
  fi
  MODE=${1#-}
  shift
  if [ -z "${1:-}" ]; then
    echo "❌ Specificare nome progetto"
    exit 1
  fi
  PROJECT="$1"
  shift

  SCRIPT_DIR=$(readlink -f "$(dirname "$0")")
  PROJECT_PATH=$(readlink -f "$PROJECT")
}

step1_verify_project() {
  echo -e "\n🔍  \e[1;32m[SIM]\e[0m \e[1;33mSTEP 1:\e[0m Verifica cartella progetto"
  if [ ! -d "$PROJECT_PATH" ]; then
    echo "❌ La cartella non esiste: $PROJECT_PATH"
    exit 1
  fi
  FRONTEND_DIR=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_frontend" | head -n1)
  BACKEND_DIR=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_backend"  | head -n1)
  if [ -z "$FRONTEND_DIR" ] || [ -z "$BACKEND_DIR" ]; then
    echo "❌ Mancano *_frontend o *_backend"
    exit 1
  fi
  PROJECT_NAME=$(basename "$FRONTEND_DIR" | cut -d'_' -f1)
}

step2_load_ports_php() {
  echo -e "\n📥  \e[1;32m[SIM]\e[0m \e[1;33mSTEP 2:\e[0m Carico porte e PHP-FPM socket"
  PORTS_FILE="$SCRIPT_DIR/deploy/assigned_ports.env"
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
  echo -e "\n🔌  \e[1;32m[SIM]\e[0m \e[1;33mSTEP 3:\e[0m Preparo simulation dirs"
  DEPLOY_ROOT="$SCRIPT_DIR/deploy"
  WWWROOT="/www/wwwroot/$MODE"
  WWWLOGS="/www/wwwlogs/$MODE"
  NGINX_CONF_PATH="/www/server/nginx/conf/nginx.conf"
  SITES_AVAIL="/www/server/nginx/conf/sites-available/$MODE"

  mkdir -p "$DEPLOY_ROOT$SITES_AVAIL"
  echo "  ➕ $DEPLOY_ROOT$SITES_AVAIL"

  if [ ! -f "$DEPLOY_ROOT$NGINX_CONF_PATH" ]; then
    echo "  ➕ Creo nginx.conf simulato"
    mkdir -p "$(dirname "$DEPLOY_ROOT$NGINX_CONF_PATH")"
    cat > "$DEPLOY_ROOT$NGINX_CONF_PATH" <<'EOF'
user  www www;
worker_processes auto;
pid   /www/server/nginx/logs/nginx.pid;
error_log /www/server/nginx/logs/error.log crit;

events {
    worker_connections 10240;
    use epoll;
}

http {
    include mime.types;
    include proxy.conf;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;
    client_max_body_size 50m;
    gzip on;
    gzip_types text/plain text/css application/json application/javascript;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'ECDHE-ECDSA-CHACHA20-POLY1305:...';

    include conf.d/*.conf;
    include sites-enabled/$MODE/*.conf;
    include /www/server/panel/vhost/nginx/$MODE/*.conf;
}

stream {
    log_format tcp '$time_local|$remote_addr|$protocol|$status|$bytes_sent|$bytes_received|$session_time';
    access_log /www/wwwlogs/tcp-access.log tcp;
    error_log /www/wwwlogs/tcp-error.log;
    include /www/server/panel/vhost/nginx/tcp/*.conf;
}
EOF
  else
    echo "  ✅ nginx.conf simulato esiste"
  fi
}

step4_detect_type() {
  echo -e "\n📌  \e[1;32m[SIM]\e[0m \e[1;33mSTEP 4:\e[0m Tipo di progetto"
  IS_MAIN="n"; VALID=false
  if [ -f "$SCRIPT_DIR/deploy/is_main.env" ]; then
    source "$SCRIPT_DIR/deploy/is_main.env"
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
    echo "IS_MAIN=$IS_MAIN" > "$SCRIPT_DIR/deploy/is_main.env"
  fi

  if [[ "$IS_MAIN" == "y" ]]; then
    REL_PATH="$PROJECT_NAME"
    VHOST_SUB=""
  else
    REL_PATH="apps/$PROJECT_NAME"
    VHOST_SUB="/apps"
  fi
}

step5_generate_vhost() {
  echo -e "\n📂  \e[1;32m[SIM]\e[0m \e[1;33mSTEP 5:\e[0m Generazione VHOST"
  # se non main, aggiungo “/apps” al path
  if [[ "$IS_MAIN" == "y" ]]; then
    VHOST_DIR="$DEPLOY_ROOT$SITES_AVAIL"
  else
    VHOST_DIR="$DEPLOY_ROOT$SITES_AVAIL/apps"
  fi
  mkdir -p "$VHOST_DIR"
  VHOST_FILE="$VHOST_DIR/${PROJECT_NAME}.conf"

  cat > "$VHOST_FILE" <<EOF
server {
  listen       $FRONT_PORT;
  listen       [::]:$FRONT_PORT;
  server_name  _;
  access_log   $WWWLOGS/$REL_PATH/${PROJECT_NAME}_front_access.log;
  error_log    $WWWLOGS/$REL_PATH/${PROJECT_NAME}_front_error.log;

  root         $WWWROOT/$REL_PATH/frontend/browser;
  index        index.html;

  location / {
    try_files \$uri \$uri/ /index.html;
  }
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
    fastcgi_param  SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    include        fastcgi_params;
  }

  location ~ /\\.(?!well-known).* { deny all; }

  access_log   $WWWLOGS/$REL_PATH/${PROJECT_NAME}_api_access.log;
  error_log    $WWWLOGS/$REL_PATH/${PROJECT_NAME}_api_error.log;
}
EOF
  echo "  ➕ VHOST creato: $VHOST_FILE"
}


step6_setup_logs() {
  echo -e "\n🗂️   \e[1;33mSTEP 6:\e[0m Configuro log"
  LOG_DIR="$SCRIPT_DIR/deploy/www/wwwlogs/$MODE/$REL_PATH"
  mkdir -p "$LOG_DIR" && echo "  ➕ Dir log: $LOG_DIR"
  for t in front_access front_error api_access api_error; do
    f="$LOG_DIR/${PROJECT_NAME}_${t}.log"
    if [ ! -f "$f" ]; then
      touch "$f" && echo "  ➕ Creo: $f"
    else
      echo "  ✅ Esiste: $f"
    fi
  done
}

step7_summary() {
  echo -e "\nℹ️   \e[1;33mSTEP 7:\e[0m Riepilogo"
  cat <<EOF
  Modalità:        $MODE
  Progetto:        $PROJECT_PATH
  Nome:            $PROJECT_NAME
  PATH deploy:     $SCRIPT_DIR/deploy
  WWWROOT:         /www/wwwroot/$MODE/$REL_PATH
  Log dir:         /www/wwwlogs/$MODE/$REL_PATH
  Front port:      $FRONT_PORT
  Back port:       $BACK_PORT
EOF
  echo -e "\n✅ Simulazione completa in $SCRIPT_DIR/deploy/www/nginx/conf/sites-available/$MODE$VHOST_SUB"
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
