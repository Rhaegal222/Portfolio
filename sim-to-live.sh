#!/usr/bin/env bash
#
# sim-to-live.sh
# Sincronizza la simulazione (deploy/www) con l'ambiente reale (/www)
# Uso: ./sim-to-live.sh -dev | -prod

set -euo pipefail
trap 'echo -e "❌ \e[1;31mErrore su comando:\e[0m $BASH_COMMAND" >&2' ERR

# --- 📝 STEP 0: Verifica parametro environment ---
echo -e "\n🔍 \e[1;33mSTEP 0:\e[0m Verifico parametro environment"
if [[ "${1:-}" != "-dev" && "${1:-}" != "-prod" ]]; then
  echo -e "❌ \e[1;31mUso corretto:\e[0m $0 -dev|-prod"
  exit 1
fi
MODE=${1#-}

echo -e "\n🚀 \e[1;33mSTEP 1:\e[0m Imposto MODE=$MODE"

# --- 🔍 STEP 2: Definizioni percorsi ---
echo -e "\n🔍 \e[1;33mSTEP 2:\e[0m Imposto percorsi sorgente e destinazione"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_BASE="$SCRIPT_DIR/deploy/www"

# Percorsi simulati
CONF_SRC="$DEPLOY_BASE/server/nginx/conf"
WWW_SRC="$DEPLOY_BASE/wwwroot/$MODE"

# Percorsi reali
CONF_DEST="/www/server/nginx/conf"
WWW_DEST="/www/wwwroot/$MODE"
LOGS_DEST="/www/wwwlogs"

echo -e "    ➤ CONF_SRC: $CONF_SRC"
echo -e "    ➤ CONF_DEST: $CONF_DEST"
echo -e "    ➤ WWW_SRC: $WWW_SRC"
echo -e "    ➤ WWW_DEST: $WWW_DEST"
echo -e "    ➤ LOGS_DEST: $LOGS_DEST"

# --- 📂 STEP 3: Trova progetto ---
echo -e "\n📂 \e[1;33mSTEP 3:\e[0m Rilevo nome progetto in $WWW_SRC"
PROJECT_NAME=$(find "$WWW_SRC" -mindepth 1 -maxdepth 1 -type d | head -n1 | xargs -n1 basename)
if [[ -z "$PROJECT_NAME" ]]; then
  echo -e "❌ \e[1;31mErrore:\e[0m Nessun progetto trovato in $WWW_SRC"
  exit 1
fi
echo -e "    ➤ Progetto: $PROJECT_NAME"

# --- 🔁 STEP 4: Sincronizza configurazione NGINX ---
echo -e "\n🔁 \e[1;33mSTEP 4:\e[0m Sync configurazione NGINX"
for dir in conf.d snippets \
           "sites-available/$MODE" \
           "sites-enabled/$MODE"; do
  SRC_DIR="$CONF_SRC/$dir"
  DEST_DIR="$CONF_DEST/$dir"
  echo -e "    • $dir"
  sudo mkdir -p "$DEST_DIR"
  if [[ -d "$SRC_DIR" ]]; then
    sudo rsync -av --delete "$SRC_DIR/" "$DEST_DIR/"
  fi
done

# Copia nginx.conf principale
echo -e "\n📄 \e[1;33mSTEP 5:\e[0m Copio nginx.conf principale"
if [[ -f "$CONF_SRC/nginx.conf" ]]; then
  sudo cp "$CONF_SRC/nginx.conf" "$CONF_DEST/nginx.conf"
  echo -e "    ➤ Copiato nginx.conf"
fi

# --- 🔗 STEP 6: Rigenera symlink in sites-enabled ---
echo -e "\n🔗 \e[1;33mSTEP 6:\e[0m Rigenero symlink in sites-enabled/$MODE"
SA="$CONF_DEST/sites-available/$MODE"
SE="$CONF_DEST/sites-enabled/$MODE"
sudo mkdir -p "$SE"
sudo rm -f "$SE"/*.conf
for f in "$SA"/*.conf; do
  [[ -f "$f" ]] && sudo ln -s "$f" "$SE/$(basename "$f")"
done

echo -e "\n🌍 \e[1;33mSTEP 7:\e[0m Deploy codice wwwroot"
sudo mkdir -p "$WWW_DEST"
sudo rsync -av --delete "$WWW_SRC/" "$WWW_DEST/"

# --- 📄 STEP 8: Verifica log esistenza ---
echo -e "\n📄 \e[1;33mSTEP 8:\e[0m Verifica e crea file di log"
sudo mkdir -p "$LOGS_DEST"
sudo touch "$LOGS_DEST/${MODE}_${PROJECT_NAME}_access.log" \
           "$LOGS_DEST/${MODE}_${PROJECT_NAME}_error.log"

# --- 🔍 STEP 9: Verifica e ricarica NGINX ---
echo -e "\n🔍 \e[1;33mSTEP 9:\e[0m Verifico configurazione NGINX"
sudo /www/server/nginx/sbin/nginx -t

echo -e "🔁 \e[1;33mSTEP 10:\e[0m Ricarico NGINX"
sudo /www/server/nginx/sbin/nginx -s reload

# --- ✅ STEP 11: Completamento ---
echo -e "\n✅ \e[1;32mSTEP 11:\e[0m Produzione '$MODE' aggiornata per '$PROJECT_NAME'"