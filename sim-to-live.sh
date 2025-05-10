#!/usr/bin/env bash
#
# sim-to-live.sh
# Sincronizza la simulazione (deploy/www) con l'ambiente reale (/www)
# Uso: ./sim-to-live.sh -dev | -prod

set -euo pipefail
trap 'echo -e "❌ \e[1;31mErrore su comando:\e[0m $BASH_COMMAND" >&2' ERR

# --- STEP 0: Verifica parametro environment ---
echo -e "\n🔍 \e[1;33mSTEP 0:\e[0m Verifico parametro environment"
if [[ "${1:-}" != "-dev" && "${1:-}" != "-prod" ]]; then
  echo -e "❌ \e[1;31mUso corretto:\e[0m $0 -dev|-prod"
  exit 1
fi
MODE=${1#-}

# --- STEP 1: Definisco variabili di percorso ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_BASE="$SCRIPT_DIR/deploy/www"
LOGS_SRC="$DEPLOY_BASE/wwwlogs/$MODE"

CONF_SRC="$DEPLOY_BASE/server/nginx/conf"
WWW_SRC="$DEPLOY_BASE/wwwroot/$MODE"

CONF_DEST="/www/server/nginx/conf"
WWW_DEST="/www/wwwroot/$MODE"
LOGS_DEST="/www/wwwlogs"

echo -e "\n🚀 \e[1;33mSTEP 1:\e[0m MODE=$MODE"
echo -e "    ➤ DEPLOY_BASE=$DEPLOY_BASE"
echo -e "    ➤ LOGS_SRC=$LOGS_SRC"
echo -e "    ➤ LOGS_DEST=$LOGS_DEST"
echo -e "    ➤ WWW_SRC=$WWW_SRC"
echo -e "    ➤ WWW_DEST=$WWW_DEST"
echo -e "    ➤ CONF_SRC=$CONF_SRC"
echo -e "    ➤ CONF_DEST=$CONF_DEST"

# --- STEP 2: Trovo il progetto da deployare ---
echo -e "\n📂 \e[1;33mSTEP 2:\e[0m Rilevo nome progetto in $WWW_SRC"
PROJECT_NAME=$(find "$WWW_SRC" -mindepth 1 -maxdepth 1 -type d | head -n1 | xargs -r basename)
if [[ -z "$PROJECT_NAME" ]]; then
  echo -e "❌ \e[1;31mErrore:\e[0m Nessun progetto trovato in $WWW_SRC"
  exit 1
fi
echo -e "    ➤ Progetto: $PROJECT_NAME"

# --- STEP 3: Sincronizzo configurazione NGINX ---
echo -e "\n🔁 \e[1;33mSTEP 3:\e[0m Sync configurazione NGINX"
for dir in conf.d snippets "sites-available/$MODE"; do
  SRC_DIR="$CONF_SRC/$dir"
  DEST_DIR="$CONF_DEST/$dir"
  sudo mkdir -p "$DEST_DIR"
  if [[ -d "$SRC_DIR" ]]; then
    sudo cp -v "$SRC_DIR"/*.conf "$DEST_DIR"/ 2>/dev/null || true
  fi
done

# --- STEP 4: Copio nginx.conf principale ---
echo -e "\n📄 \e[1;33mSTEP 4:\e[0m Copio nginx.conf principale"
if [[ -f "$CONF_SRC/nginx.conf" ]]; then
  sudo cp -v "$CONF_SRC/nginx.conf" "$CONF_DEST/nginx.conf"
fi

# --- STEP 5: Aggiorno il symlink del vhost ---
echo -e "\n🔗 \e[1;33mSTEP 5:\e[0m Aggiorno symlink per $PROJECT_NAME"
SA="$CONF_DEST/sites-available/$MODE"
SE="$CONF_DEST/sites-enabled/$MODE"
SA_CONF="$SA/$PROJECT_NAME.conf"
SE_CONF="$SE/$PROJECT_NAME.conf"
sudo mkdir -p "$SE"
if [[ -f "$SA_CONF" ]]; then
  sudo rm -f "$SE_CONF"
  sudo ln -s "$SA_CONF" "$SE_CONF"
  echo -e "    ➤ Symlink: $SE_CONF → $SA_CONF"
else
  echo -e "❌ \e[1;31mErrore:\e[0m $SA_CONF non trovato"
  exit 1
fi

# --- STEP 6: Deploy del solo progetto (senza toccare gli altri) ---
echo -e "\n🌍 \e[1;33mSTEP 6:\e[0m Deploy di $PROJECT_NAME in $WWW_DEST"
PROJECT_SRC="$WWW_SRC/$PROJECT_NAME"
PROJECT_DEST="$WWW_DEST/$PROJECT_NAME"
if [[ ! -d "$PROJECT_SRC" ]]; then
  echo -e "❌ \e[1;31mErrore:\e[0m $PROJECT_SRC non trovato"
  exit 1
fi
sudo mkdir -p "$PROJECT_DEST"
sudo rsync -a --delete "$PROJECT_SRC"/ "$PROJECT_DEST"/
echo -e "    ➤ Copiato: $PROJECT_SRC → $PROJECT_DEST"

# --- STEP 7: Copio .env nel backend del progetto ---
echo -e "\n🗝️  \e[1;33mSTEP 7:\e[0m Copio .env in $PROJECT_DEST/backend"
if [[ -f "$PROJECT_SRC/backend/.env" ]]; then
  sudo cp -v "$PROJECT_SRC/backend/.env" "$PROJECT_DEST/backend/.env"
else
  echo -e "⚠️  Attenzione: .env non esiste in $PROJECT_SRC/backend"
fi

# --- STEP 8: Trasferisco i log del progetto ---
echo -e "\n📄 \e[1;33mSTEP 8:\e[0m Trasferisco log per $PROJECT_NAME"
LOGS_DEST="/www/wwwlogs/$MODE"    # <— qui
sudo mkdir -p "$LOGS_DEST"

for log in "$LOGS_SRC/${MODE}_${PROJECT_NAME}"*.log; do
  if [[ -f "$log" ]]; then
    sudo cp -v "$log" "$LOGS_DEST"/
  fi
done

# --- STEP 9: Verifico configurazione NGINX ---
echo -e "\n🔍 \e[1;33mSTEP 9:\e[0m Verifico configurazione NGINX"
sudo /www/server/nginx/sbin/nginx -t

# --- STEP 10: Ricarico o avvio NGINX ---
echo -e "\n🔁 \e[1;33mSTEP 10:\e[0m Ricarico NGINX"
if sudo lsof -i :80 -sTCP:LISTEN >/dev/null; then
  sudo /www/server/nginx/sbin/nginx -s reload || {
    sudo pkill nginx
    sudo /www/server/nginx/sbin/nginx
  }
else
  sudo /www/server/nginx/sbin/nginx
fi

# --- STEP 11: Leggo le porte assegnate da file ---
echo -e "\n🔢 \e[1;33mSTEP 11:\e[0m Leggo porte da assigned_ports.env"
PORTS_FILE="$SCRIPT_DIR/assigned_ports.env"

if [[ ! -f "$PORTS_FILE" ]]; then
  echo -e "❌ \e[1;31mErrore:\e[0m File porte non trovato: $PORTS_FILE"
  exit 1
fi

source "$PORTS_FILE"

if [[ -z "${FRONT_PORT:-}" || -z "${BACK_PORT:-}" ]]; then
  echo -e "❌ \e[1;31mErrore:\e[0m FRONT_PORT o BACK_PORT non presenti nel file"
  exit 1
fi

echo -e "    ➤ FRONT_PORT=$FRONT_PORT"
echo -e "    ➤ BACK_PORT=$BACK_PORT"

echo -e "\n🌐 \e[1;33mINFO:\e[0m URL simulazione attiva:"
echo -e "    🔗 Frontend ➝ http://localhost:$FRONT_PORT/"
echo -e "    🔗 Backend  ➝ http://localhost:$BACK_PORT/"

# --- 🧹 STEP 12: Rimuovo directory di simulazione ---
echo -e "\n🧹 \e[1;33mSTEP 12:\e[0m Rimuovo directory di simulazione"
sudo rm -rf "$SCRIPT_DIR/deploy"
rm -f "$PORTS_FILE"

# --- STEP 13: Fine ---
echo -e "\n✅ \e[1;32mSTEP 13:\e[0m Deploy ($MODE) di '$PROJECT_NAME' completato!\e[0m"
