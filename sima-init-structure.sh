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

# Verifica se la modalità è corretta
if [[ "$1" != "-dev" && "$1" != "-prod" ]]; then
  echo "❌ Uso corretto: $0 -dev|-prod"
  exit 1
fi

MODE=${1#-}
shift

# Verifica se è stato specificato un progetto se é stato specificato assegnalo a $PROJECT
if [ -n "$1" ]; then
  PROJECT="$1"
  shift
fi


SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# --- 🗑️ STEP 0: Rimuovo struttura precedente se esistente ---
if [ -d "$SCRIPT_DIR/deploy" ]; then
  echo -e "\n🗑️  \e[1;33mSTEP 0:\e[0m Rimuovo struttura esistente \e[1;32m$SCRIPT_DIR/deploy\e[0m"
  sudo rm -rf "$SCRIPT_DIR/deploy"
fi

DEPLOY_ROOT="$SCRIPT_DIR/deploy/www"

# --- 🔧 STEP 1: Creo struttura base NGINX ---
NGINX_CONF_ROOT="$DEPLOY_ROOT/server/nginx/conf"
CONF_D="$NGINX_CONF_ROOT/conf.d"
SITES_AVAIL="$NGINX_CONF_ROOT/sites-available/$MODE"
SNIPPETS="$NGINX_CONF_ROOT/snippets"
NGINX_MAIN_CONF="$NGINX_CONF_ROOT/nginx.conf"
PROXY_PARAMS_SRC="$SCRIPT_DIR/server/nginx/conf.d/proxy_params.conf"

echo -e "\n🔧  \e[1;33mSTEP 1:\e[0m Creo directory base in \e[1;32m$NGINX_CONF_ROOT\e[0m"
echo "  ➤  /conf.d"
echo "  ➤  /sites-available/$MODE"
echo "  ➤  /snippets"
mkdir -p \
  "$CONF_D" \
  "$SITES_AVAIL" \
  "$SNIPPETS"

# --- 🌐 STEP 2: Creo directory wwwroot ---
DIR="wwwroot/$MODE"
WWWROOT="$DEPLOY_ROOT/$DIR"
echo -e "\n🌐  \e[1;33mSTEP 2:\e[0m Creo directory \e[1;32m$DIR\e[0m in \e[1;32m$WWWROOT\e[0m"
mkdir -p "$WWWROOT"
echo -e "  ➕ $WWWROOT"

# --- 🗄️ STEP 3: Creo directory dei log per dev e prod ---
LOGS_BASE="$DEPLOY_ROOT/wwwlogs"
LOGS="$LOGS_BASE/$MODE"

echo -e "\n🗄️  \e[1;33mSTEP 3:\e[0m Creo directory log per $MODE"
mkdir -p "$LOGS"
echo -e "  ➕ $LOGS"

# --- 📂 STEP 4: Creo struttura progetto se specificato ---
# --- 📂 STEP 4: Creo struttura progetto se specificato ---
if [ -n "$PROJECT" ]; then
  ROOT="$WWWROOT/apps/$PROJECT"
  FRONT="$ROOT/frontend"
  BACK="$ROOT/backend"

  echo -e "\n📂  \e[1;33mSTEP 4:\e[0m Creo struttura per progetto '$PROJECT' in $MODE"
  mkdir -p "$FRONT" "$BACK"
  echo -e "  ➕ $FRONT"
  echo -e "  ➕ $BACK"
fi

# --- 🔎 STEP 5: Trovo porte libere ---
echo -e "\n🔎 \e[1;33mSTEP 5:\e[0m Trovo porte libere"
find_free_port(){ local p=$1; while lsof -iTCP:$p -sTCP:LISTEN >/dev/null 2>&1; do ((p++)); done; echo $p; }
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
