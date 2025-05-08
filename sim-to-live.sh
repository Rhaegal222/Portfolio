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
# --- 🔁 STEP 4: Sincronizza configurazione NGINX ---
echo -e "\n🔁 \e[1;33mSTEP 4:\e[0m Sync configurazione NGINX (solo file del progetto corrente)"
for dir in conf.d snippets "sites-available/$MODE"; do
  SRC_DIR="$CONF_SRC/$dir"
  DEST_DIR="$CONF_DEST/$dir"
  echo -e "    • $dir"
  sudo mkdir -p "$DEST_DIR"
  if [[ -d "$SRC_DIR" ]]; then
    for file in "$SRC_DIR"/*.conf; do
      [[ -f "$file" ]] && sudo cp "$file" "$DEST_DIR/"
    done
  fi
done

# --- 📄 STEP 5: Copia nginx.conf principale ---
echo -e "\n📄 \e[1;33mSTEP 5:\e[0m Copio nginx.conf principale"
if [[ -f "$CONF_SRC/nginx.conf" ]]; then
  sudo cp "$CONF_SRC/nginx.conf" "$CONF_DEST/nginx.conf"
  echo -e "    ➤ Copiato nginx.conf"
fi

# --- 🔗 STEP 6: Rigenera symlink in sites-enabled ---
# --- 🔗 STEP 6: Rigenera symlink in sites-enabled ---
echo -e "\n🔗 \e[1;33mSTEP 6:\e[0m Aggiorno symlink per $PROJECT_NAME in sites-enabled/$MODE"
SA="$CONF_DEST/sites-available/$MODE"
SE="$CONF_DEST/sites-enabled/$MODE"
SA_CONF="$SA/$PROJECT_NAME.conf"
SE_CONF="$SE/$PROJECT_NAME.conf"
sudo mkdir -p "$SE"
if [[ -f "$SA_CONF" ]]; then
  sudo rm -f "$SE_CONF"
  sudo ln -s "$SA_CONF" "$SE_CONF"
  echo -e "    ➤ Symlink aggiornato: $SE_CONF"
else
  echo -e "❌ \e[1;31mErrore:\e[0m File $SA_CONF non trovato"
  exit 1
fi

# --- 🌍 STEP 7: Deploy solo il progetto, non rimpiazza gli altri ---
echo -e "\n🌍 \e[1;33mSTEP 7:\e[0m Deploy progetto $PROJECT_NAME in $WWW_DEST"
PROJECT_SRC="$WWW_SRC/$PROJECT_NAME"
PROJECT_DEST="$WWW_DEST/$PROJECT_NAME"
sudo mkdir -p "$PROJECT_DEST"
sudo rsync -av --delete "$PROJECT_SRC/" "$PROJECT_DEST/"
echo -e "    ➤ Codice deployato in $PROJECT_DEST"

# --- 🗝️ STEP 8: Copia file .env in backend ---
echo -e "\n🗝️ \e[1;33mSTEP 8:\e[0m Copio .env nel backend"
SRC_ENV="$PROJECT_SRC/backend/.env"
DEST_BACKEND="$PROJECT_DEST/backend"
if [[ -f "$SRC_ENV" ]]; then
  sudo cp "$SRC_ENV" "$DEST_BACKEND/.env"
  echo -e "    ➤ .env copiato in $DEST_BACKEND"
else
  echo -e "❌ \e[1;31mErrore:\e[0m .env non trovato in $SRC_ENV" >&2
  exit 1
fi

# --- 📄 STEP 9: Verifica log esistenza ---
echo -e "\n📄 \e[1;33mSTEP 9:\e[0m Verifica e crea file di log"
sudo mkdir -p "$LOGS_DEST"
sudo touch "$LOGS_DEST/${MODE}_${PROJECT_NAME}_access.log" \
           "$LOGS_DEST/${MODE}_${PROJECT_NAME}_error.log"

# --- 🔍 STEP 10: Verifica e ricarica NGINX ---
echo -e "\n🔍 \e[1;33mSTEP 10:\e[0m Verifico configurazione NGINX"
sudo /www/server/nginx/sbin/nginx -t

echo -e "🔁 \e[1;33mSTEP 11:\e[0m Ricarico NGINX"
sudo /www/server/nginx/sbin/nginx -s reload

# --- 🧹 STEP 12: Rimuovo directory deploy ---
echo -e "\n🧹 \e[1;33mSTEP 12:\e[0m Rimuovo directory di simulazione"
sudo rm -rf "$SCRIPT_DIR/deploy"

# --- ✅ STEP 13: Completamento ---
echo -e "\n✅ \e[1;32mSTEP 13:\e[0m Produzione '$MODE' aggiornata per '$PROJECT_NAME'\e[0m"