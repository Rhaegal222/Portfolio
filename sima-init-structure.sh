#!/bin/bash
#
# sima-init-structure.sh
# 0) prendi in input -dev o -prod
# 1) Crea la struttura base di NGINX (sempre)
# 2) Chiedi se è il progetto principale
# 3) Se specificato un <project>, crea wwwroot/.../apps/<project>/{frontend,backend} in prod o dev
# 4) Crea la cartella dei log
#
set -e

if [[ $EUID -ne 0 ]]; then
  echo "❌ Questo script deve essere eseguito con i permessi di root. Esegui con sudo."
  exec sudo "$0" "$@"
fi

# Verifico se la modalità di esecuzione
echo -e "\n🔍  \e[1;33mSTEP 0:\e[0m Verifico modalità di esecuzione: \e[1;32m$1\e[0m"
if [[ "$1" != "-dev" && "$1" != "-prod" ]]; then
  echo "❌ Uso corretto: $0 -dev|-prod"
  exit 1
fi
MODE=${1#-}
shift

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

if [ -n "$1" ]; then
  PROJECT="$1"
  echo -e "\nℹ️   Progetto specificato: \e[1;32m$PROJECT\e[0m"
  shift

  PROJECT_PATH=$(realpath "$PROJECT")
  PROJECT_NAME=$(basename "$PROJECT_PATH")

  echo -e "\n🔍  \e[1;33mSTEP 0:\e[0m Verifica cartella del progetto"
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
fi

# --- 🗑️ STEP 1: Rimuovo struttura precedente se esistente ---
if [ -d "$SCRIPT_DIR/deploy" ]; then
  echo -e "\n🗑️   \e[1;33mSTEP 1:\e[0m Rimuovo struttura esistente \e[1;32m$SCRIPT_DIR/deploy\e[0m"
  sudo rm -rf "$SCRIPT_DIR/deploy"
fi

DEPLOY_ROOT="$SCRIPT_DIR/deploy/www"

# --- 🔧 STEP 2: Creo struttura base NGINX ---
NGINX_CONF_ROOT="$DEPLOY_ROOT/server/nginx/conf"
CONF_D="$NGINX_CONF_ROOT/conf.d"
SITES_AVAIL="$NGINX_CONF_ROOT/sites-available/$MODE"
SNIPPETS="$NGINX_CONF_ROOT/snippets"
NGINX_MAIN_CONF="$NGINX_CONF_ROOT/nginx.conf"
PROXY_PARAMS_SRC="$SCRIPT_DIR/server/nginx/conf.d/proxy_params.conf"

echo -e "\n🔧  \e[1;33mSTEP 2:\e[0m Creo directory base in \e[1;32m$NGINX_CONF_ROOT\e[0m"
echo "  ➕ /conf.d"
echo "  ➕ /sites-available/$MODE"
echo "  ➕ /snippets"
mkdir -p \
  "$CONF_D" \
  "$SITES_AVAIL" \
  "$SNIPPETS"

# --- 🌐 STEP 3: Creo directory wwwroot ---
DIR_WWWROOT="wwwroot/$MODE"
WWWROOT="$DEPLOY_ROOT/$DIR_WWWROOT"
echo -e "\n🌐  \e[1;33mSTEP 3:\e[0m Creo directory \e[1;32m$DIR_WWWROOT\e[0m in \e[1;32m$WWWROOT\e[0m"
mkdir -p "$WWWROOT"
echo -e "  ➕ $WWWROOT"

# --- 🗄️ STEP 4: Creo directory dei log per $MODE ---
DIR_WWWLOGS="wwwlogs/$MODE"
WWWLOGS="$DEPLOY_ROOT/$DIR_WWWLOGS"
echo -e "\n🗄️  \e[1;33mSTEP 4:\e[0m Creo directory \e[1;32m$DIR_WWWLOGS\e[0m in \e[1;32m$WWWLOGS\e[0m"
mkdir -p "$WWWLOGS"
echo -e "  ➕ $WWWLOGS"

# --- 📂 STEP 4.1: Creo struttura progetto se specificato ---
if [ -n "$PROJECT_NAME" ]; then
  # Carica e valida la risposta precedente se presente
IS_MAIN_FILE="$SCRIPT_DIR/deploy/is_main.env"
if [[ -f "$IS_MAIN_FILE" ]]; then
  source "$IS_MAIN_FILE"
  IS_MAIN=${IS_MAIN,,}
fi

if [[ "$IS_MAIN" != "y" && "$IS_MAIN" != "n" ]]; then
  read -rp $'\n\e[1;33m📌  È il progetto principale? [\e[1;32my/\e[1;31mN\e[0m] (default N): ' IS_MAIN
  IS_MAIN=${IS_MAIN:-n}
  IS_MAIN=${IS_MAIN,,}
  if [[ "$IS_MAIN" != "y" && "$IS_MAIN" != "n" ]]; then
    echo "❌  Risposta non valida, deve essere 'y' o 'n'"
    exit 1
  fi
  echo "IS_MAIN=$IS_MAIN" > "$IS_MAIN_FILE"
fi

  LOGS="$WWWLOGS/$PROJECT_NAME"

  if [[ "$IS_MAIN" == "y" ]]; then
    ROOT="$WWWROOT/$PROJECT_NAME"
  else
    ROOT="$WWWROOT/apps/$PROJECT_NAME"
  fi

  FRONT="$ROOT/frontend"
  BACK="$ROOT/backend"
  echo -e "\n📂  \e[1;33mSTEP 4.1:\e[0m Creo struttura per progetto '\e[1;32m$PROJECT_NAME\e[0m' in \e[1;32m$MODE\e[0m"
  mkdir -p "$FRONT" "$BACK" "$LOGS"
  echo -e "  ➕ $FRONT"
  echo -e "  ➕ $BACK"
  echo -e "  ➕ $LOGS"
fi

# --- 🔎 STEP 5: Trovo porte libere ---
echo -e "\n🔎  \e[1;33mSTEP 5:\e[0m Trovo porte libere"
find_free_port() {
  local p=$1
  while lsof -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; do
    ((p++))
  done
  echo "$p"
}
FRONT_PORT=$(find_free_port 8080)
BACK_PORT=$(find_free_port 8000)
echo -e "  ➤  FRONT_PORT= \e[1;33m$FRONT_PORT\e[0m, BACK_PORT= \e[1;33m$BACK_PORT\e[0m"

echo -e "\n🔧 [SIM $MODE] frontend -> \e[1;33mhttp://localhost:$FRONT_PORT/\e[0m"
echo -e "🔧 [SIM $MODE] backend  -> \e[1;33mhttp://localhost:$BACK_PORT/\e[0m"

# --- 🔢 STEP 6: Scrive le porte assegnate temporaneamente in $SCRIPT_DIR ---
PORTS_FILE="$SCRIPT_DIR/deploy/assigned_ports.env"
echo -e "\n💾 \e[1;33mSTEP 6:\e[0m Scrivo porte assegnate in \e[1;32m$PORTS_FILE\e[0m"
echo "FRONT_PORT=$FRONT_PORT" > "$PORTS_FILE"
echo "BACK_PORT=$BACK_PORT" >> "$PORTS_FILE"

# --- ✅ STEP 7: Completamento ---
echo -e "\n✅  \e[1;33mSTEP 7:\e[0m Struttura di deploy pronta."
