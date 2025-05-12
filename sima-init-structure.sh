#!/usr/bin/env bash
#
# sima-init-structure.sh
# 0) prendi in input -dev o -prod
# 1) Crea la struttura base di NGINX (sempre)
# 2) Chiedi se è il progetto principale
# 3) Se specificato un <project>, crea wwwroot/.../apps/<project>/{frontend,backend} in prod o dev
# 4) Crea la cartella dei log
# 5) Trova porte libere e salva in assigned_ports.env

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# ─── Funzioni ────────────────────────────────────────────────────────────────
require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "❌ Questo script deve essere eseguito con i permessi di root. Esegui con sudo."
    exec sudo "$0" "$@"
  fi
}

parse_args() {
  echo -e "\n🔍  \e[1;33mSTEP 0:\e[0m Verifico modalità di esecuzione"
  if [[ "${1:-}" != "-dev" && "${1:-}" != "-prod" ]]; then
    echo "❌ Uso corretto: $0 -dev|-prod [<percorso_progetto>]"
    exit 1
  fi
  MODE=${1#-}; shift

  DEPLOY_ROOT="$SCRIPT_DIR/deploy/www"

  if [ -n "${1:-}" ]; then
    PROJECT="$1"; shift
    echo -e "\nℹ️   Progetto specificato: \e[1;32m$PROJECT\e[0m"
    PROJECT_PATH=$(realpath "$PROJECT")
    PROJECT_NAME=$(basename "$PROJECT_PATH")
  else
    PROJECT=""
    PROJECT_NAME=""
  fi
}

detect_type() {
  # Assicuro che $SCRIPT_DIR/deploy esista
  mkdir -p "$SCRIPT_DIR/deploy"

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
    VHOST_SUBDIR=""
  else
    REL_PATH="apps/$PROJECT_NAME"
    VHOST_SUBDIR="/apps"
  fi
}

cleanup_previous() {
  if [ -d "$SCRIPT_DIR/deploy" ]; then
    echo -e "\n🗑️   \e[1;33mSTEP 1:\e[0m Rimuovo struttura precedente: \e[1;32m$SCRIPT_DIR/deploy\e[0m"
    rm -rf "$SCRIPT_DIR/deploy"
  fi
}

verify_project() {
  if [ -z "$PROJECT" ]; then
    return
  fi
  echo -e "\n🔍  \e[1;33mSTEP 2:\e[0m Verifica cartella del progetto"
  if [ ! -d "$PROJECT_PATH" ]; then
    echo "❌ La cartella del progetto non esiste: $PROJECT_PATH"
    exit 1
  fi
  FRONTEND_DIR=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_frontend" | head -n1)
  if [ -z "$FRONTEND_DIR" ]; then
    echo "❌ Nessuna cartella *_frontend trovata in $PROJECT_PATH"
    exit 1
  fi
  PROJECT_NAME=$(basename "$FRONTEND_DIR" | cut -d'_' -f1)
}

create_nginx_structure() {
  echo -e "\n🔧  \e[1;33mSTEP 3:\e[0m Creo struttura base NGINX"
  NGINX_CONF_ROOT="$DEPLOY_ROOT/server/nginx/conf"
  CONF_D="$NGINX_CONF_ROOT/conf.d"
  SITES_AVAIL="$CONF_D/sites-available/$MODE"
  SITES_ENABLED="$CONF_D/sites-enabled/$MODE"
  SNIPPETS="$NGINX_CONF_ROOT/snippets"

  echo "  ➕ $CONF_D"
  echo "  ➕ $SITES_AVAIL"
  echo "  ➕ $SITES_ENABLED"
  echo "  ➕ $SNIPPETS"

  mkdir -p "$CONF_D" "$SITES_AVAIL" "$SITES_ENABLED" "$SNIPPETS"
}

create_wwwroot() {
  echo -e "\n🌐  \e[1;33mSTEP 4:\e[0m Creo directory wwwroot"
  WWWROOT="$DEPLOY_ROOT/wwwroot/$MODE"
  echo "  ➕ $WWWROOT"
  mkdir -p "$WWWROOT"
}

create_wwwlogs() {
  echo -e "\n🗄️  \e[1;33mSTEP 5:\e[0m Creo directory wwwlogs"
  WWWLOGS="$DEPLOY_ROOT/wwwlogs/$MODE"
  echo "  ➕ $WWWLOGS"
  mkdir -p "$WWWLOGS"
}

project_structure() {
  if [ -z "$PROJECT_NAME" ]; then
    return
  fi
  echo -e "\n📂  \e[1;33mSTEP 6:\e[0m Creo struttura progetto '$PROJECT_NAME'"
  IS_MAIN_FILE="$SCRIPT_DIR/deploy/is_main.env"
  IS_MAIN="n"
  if [[ -f "$IS_MAIN_FILE" ]]; then
    source "$IS_MAIN_FILE"
    IS_MAIN=${IS_MAIN,,}
  fi
  if [[ "$IS_MAIN" != "y" && "$IS_MAIN" != "n" ]]; then
    read -rp $'\n❓  È il progetto principale? [y/N]: ' IS_MAIN
    IS_MAIN=${IS_MAIN:-n}; IS_MAIN=${IS_MAIN,,}
    if [[ "$IS_MAIN" != "y" && "$IS_MAIN" != "n" ]]; then
      echo "❌ Risposta non valida"
      exit 1
    fi
    echo "IS_MAIN=$IS_MAIN" > "$IS_MAIN_FILE"
  fi

  if [[ "$IS_MAIN" == "y" ]]; then
    ROOT="$WWWROOT/$PROJECT_NAME"
    LOGS="$WWWLOGS/$PROJECT_NAME"
  else
    ROOT="$WWWROOT/apps/$PROJECT_NAME"
    LOGS="$WWWLOGS/apps/$PROJECT_NAME"
  fi
  FRONT_DIR="$ROOT/frontend"
  BACK_DIR="$ROOT/backend"
  LOGS_DIR="$LOGS"

  echo "  ➕ $FRONT_DIR"
  echo "  ➕ $BACK_DIR"
  echo "  ➕ $LOGS_DIR"

  mkdir -p "$FRONT_DIR" "$BACK_DIR" "$LOGS_DIR"
}

find_free_port() {
  local p=$1
  while lsof -iTCP:"$p" -sTCP:LISTEN &>/dev/null; do
    ((p++))
  done
  echo "$p"
}

assign_ports() {
  echo -e "\n🔎  \e[1;33mSTEP 7:\e[0m Trovo porte libere"
  FRONT_PORT=$(find_free_port 8080)
  BACK_PORT=$(find_free_port 8000)
  echo "  ➤ FRONT_PORT= \e[1;32m$FRONT_PORT\e[0m, BACK_PORT= \e[1;32m$BACK_PORT\e[0m"
}

write_ports_file() {
  echo -e "\n💾  \e[1;33mSTEP 8:\e[0m Scrivo porte assegnate"
  PORTS_FILE="$SCRIPT_DIR/deploy/assigned_ports.env"
  mkdir -p "$(dirname "$PORTS_FILE")"
  {
    echo "FRONT_PORT=$FRONT_PORT"
    echo "BACK_PORT=$BACK_PORT"
  } > "$PORTS_FILE"
  echo "  ➕ $PORTS_FILE"
}

print_summary() {
  echo -e "\n✅  \e[1;33mSTRUTTURA DI DEPLOY PRONTA\e[0m"
  echo "  • Mode:       $MODE"
  echo "  • Deploy dir: $DEPLOY_ROOT"
  echo "  • WWWROOT:    $WWWROOT"
  echo "  • WWWLOGS:    $WWWLOGS"
  if [ -n "$PROJECT_NAME" ]; then
    echo "  • Project:    $PROJECT_NAME"
    echo "  • Frontend:   $FRONT_DIR"
    echo "  • Backend:    $BACK_DIR"
    echo "  • Log dir:    $LOGS_DIR"
  fi
  echo "  • Ports:      $FRONT_PORT / $BACK_PORT"
}

# ─── Main ───────────────────────────────────────────────────────────────────

require_root "$@"
parse_args "$@"
cleanup_previous
detect_type
verify_project
create_nginx_structure
create_wwwroot
create_wwwlogs
project_structure
assign_ports
write_ports_file
print_summary
