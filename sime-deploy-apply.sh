#!/usr/bin/env bash
#
# sime-deploy-apply.sh
# Applica il deploy effettivo in /www, trasferendo la configurazione e il progetto
# Uso: ./sime-deploy-apply.sh -dev | -prod

set -euo pipefail

# ─── STEP 0: Verifica esecuzione con permessi di root ───
if [[ $EUID -ne 0 ]]; then
  echo "❌ Questo script deve essere eseguito con i permessi di root. Esegui con sudo."
  exec sudo "$0" "$@"
fi

# ─── STEP 1: Verifica parametro environment ───
echo -e "\n🔍  \e[1;33mSTEP 1:\e[0m Verifico parametro environment"
if [[ "${1:-}" != "-dev" && "${1:-}" != "-prod" ]]; then
  echo -e "❌ \e[1;31mUso corretto:\e[0m $0 -dev|-prod"
  exit 1
fi
MODE="${1#-}"

# ─── STEP 2: Inizializzazione variabili ───
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$SCRIPT_DIR/deploy"

# Percorsi sorgente (simulazione)
CONF_SRC="$DEPLOY_ROOT/www/server/nginx/conf"
WWW_SRC="$DEPLOY_ROOT/www/wwwroot/$MODE"
LOGS_SRC="$DEPLOY_ROOT/www/wwwlogs/$MODE"

# Percorsi destinazione (reale)
CONF_DEST="/www/server/nginx/conf"
WWW_DEST="/www/wwwroot/$MODE"
LOGS_DEST="/www/wwwlogs/$MODE"

echo -e "\n🗂️  \e[1;33mSTEP 2:\e[0m Variabili inizializzate"
echo -e "    ➤ MODE         = $MODE"
echo -e "    ➤ DEPLOY_ROOT  = $DEPLOY_ROOT"
echo -e "    ➤ CONF_SRC     = $CONF_SRC"
echo -e "    ➤ WWW_SRC      = $WWW_SRC"
echo -e "    ➤ LOGS_SRC     = $LOGS_SRC"
echo -e "    ➤ CONF_DEST    = $CONF_DEST"
echo -e "    ➤ WWW_DEST     = $WWW_DEST"
echo -e "    ➤ LOGS_DEST    = $LOGS_DEST"

# ─── STEP 3: Rilevo nome e percorso progetto ───
echo -e "\n📂  \e[1;33mSTEP 3:\e[0m Rilevo nome progetto"

if [[ -d "$WWW_SRC/apps" ]]; then
  PROJECT_NAME=$(find "$WWW_SRC/apps" -mindepth 1 -maxdepth 1 -type d | head -n1 | xargs -r basename)
  PROJECT_PATH="$WWW_SRC/apps/$PROJECT_NAME"
else
  PROJECT_NAME=$(find "$WWW_SRC" -mindepth 1 -maxdepth 1 -type d | head -n1 | xargs -r basename)
  PROJECT_PATH="$WWW_SRC/$PROJECT_NAME"
fi

if [[ -z "$PROJECT_NAME" ]]; then
  echo -e "❌ Nessun progetto trovato in $WWW_SRC"
  exit 1
fi

echo -e "    ➤ Progetto: $PROJECT_NAME"
echo -e "    ➤ Percorso: $PROJECT_PATH"

# ─── STEP 4: Sincronizzo configurazione NGINX ───
echo -e "\n🔁  \e[1;33mSTEP 4:\e[0m Sincronizzo configurazione NGINX"
for dir in conf.d snippets "sites-available/$MODE"; do
  SRC="$CONF_SRC/$dir"
  DEST="$CONF_DEST/$dir"
  sudo mkdir -p "$DEST"
  [[ -d "$SRC" ]] && sudo cp -v "$SRC"/*.conf "$DEST"/ 2>/dev/null || true
done

# ─── STEP 5: Copio nginx.conf ───
echo -e "\n📄  \e[1;33mSTEP 5:\e[0m Copio nginx.conf principale"
[[ -f "$CONF_SRC/nginx.conf" ]] && sudo cp -v "$CONF_SRC/nginx.conf" "$CONF_DEST/nginx.conf"

# ─── STEP 6: Aggiorno symlink VHOST ───
echo -e "\n🔗  \e[1;33mSTEP 6:\e[0m Aggiorno symlink VHOST"

SA="$CONF_DEST/sites-available/$MODE"
SE="$CONF_DEST/sites-enabled/$MODE"

# se esiste apps/<project>.conf lo uso, altrimenti root
if [[ -f "$SA/apps/$PROJECT_NAME.conf" ]]; then
  SA_CONF="$SA/apps/$PROJECT_NAME.conf"
  SE_DIR="$SE/apps"
elif [[ -f "$SA/$PROJECT_NAME.conf" ]]; then
  SA_CONF="$SA/$PROJECT_NAME.conf"
  SE_DIR="$SE"
else
  echo -e "❌ Configurazione mancante: né $SA/apps/$PROJECT_NAME.conf né $SA/$PROJECT_NAME.conf"
  exit 1
fi

SE_CONF="$SE_DIR/$PROJECT_NAME.conf"
sudo mkdir -p "$SE_DIR"
sudo rm -f "$SE_CONF"
sudo ln -s "$SA_CONF" "$SE_CONF"
echo -e "    ➤ Symlink creato: $SE_CONF → $SA_CONF"

# ─── STEP 7: Deploy del progetto ───
echo -e "\n 🌍  \e[1;33mSTEP 7:\e[0m Deploy del progetto"

if [[ -d "$WWW_SRC/apps/$PROJECT_NAME" ]]; then
  PROJECT_SRC="$WWW_SRC/apps/$PROJECT_NAME"
  PROJECT_DEST="$WWW_DEST/apps/$PROJECT_NAME"
else
  PROJECT_SRC="$WWW_SRC/$PROJECT_NAME"
  PROJECT_DEST="$WWW_DEST/$PROJECT_NAME"
fi

if [[ ! -d "$PROJECT_SRC" ]]; then
  echo -e "❌ Progetto non trovato: $PROJECT_SRC"
  exit 1
fi

# Controlla se la cartella di destinazione esiste già
if [[ -d "$PROJECT_DEST" ]]; then
  # Chiede conferma all'utente per eliminare il progetto esistente
  read -p "Il progetto '$PROJECT_NAME' esiste già nella destinazione. Vuoi eliminarlo e continuare? (y/n): " CONFIRMATION
  if [[ "$CONFIRMATION" =~ ^[Yy]$ ]]; then
    echo -e "\n 🔴 Elimino la cartella esistente: $PROJECT_DEST"

    # Prendi possesso della cartella e dei suoi contenuti
    sudo chown -R $USER:$USER "$PROJECT_DEST"

    # Rimuovi l'attributo immutabile da tutti i file all'interno
    sudo chattr -i -R "$PROJECT_DEST"

    # Rimuovi la cartella
    sudo rm -rf "$PROJECT_DEST"  # Rimuove la cartella esistente
  else
    echo "❌ Setup annullato. Il progetto non verrà sovrascritto."
    exit 1  # Esce dallo script
  fi
fi

# Crea la cartella di destinazione
sudo mkdir -p "$PROJECT_DEST"

# Sincronizza il progetto
sudo rsync -a --delete "$PROJECT_SRC"/ "$PROJECT_DEST"/
echo -e "    ➤ Copiato: $PROJECT_SRC → $PROJECT_DEST"

# ─── STEP 8: Copio .env ───
echo -e "\n🗝️   \e[1;33mSTEP 8:\e[0m Copio .env del backend"
ENV_SRC="$PROJECT_SRC/backend/.env"
ENV_DEST="$PROJECT_DEST/backend/.env"
[[ -f "$ENV_SRC" ]] && sudo cp -v "$ENV_SRC" "$ENV_DEST" || echo "⚠️  Nessun .env trovato"

# ─── STEP 9: Copia file log ───
echo -e "\n📤  \e[1;33mSTEP 9:\e[0m Copio file di log del progetto"
SRC_LOG_DIR="$LOGS_SRC/$PROJECT_NAME"
DEST_LOG_DIR="$LOGS_DEST/$PROJECT_NAME"

# Rimuovi la directory di log di destinazione se esiste
if [[ -d "$DEST_LOG_DIR" ]]; then
  sudo rm -rf "$DEST_LOG_DIR"
  echo "    🗑️  Rimosso: $DEST_LOG_DIR"
  sudo mkdir -p "$DEST_LOG_DIR"
  echo "    ➕  Creato: $DEST_LOG_DIR"
else
  sudo mkdir -p "$DEST_LOG_DIR"
  echo "    ➕  Creato: $DEST_LOG_DIR"
fi

echo "     ➤  Copio log da: $SRC_LOG_DIR a $DEST_LOG_DIR"

LOG_FILES=(
  "${PROJECT_NAME}_front_access.log"
  "${PROJECT_NAME}_front_error.log"
  "${PROJECT_NAME}_api_access.log"
  "${PROJECT_NAME}_api_error.log"
)

for LOG_FILE in "${LOG_FILES[@]}"; do
  SRC="$SRC_LOG_DIR/$LOG_FILE"
  DEST="$DEST_LOG_DIR/$LOG_FILE"
  
  if [[ -f "$SRC" ]]; then
    sudo cp -v "$SRC" "$DEST"
    echo "  📄 Copiato: $SRC → $DEST"
  else
    echo "  ⚠️  Mancante: $SRC"
  fi
done

exit 1

# ─── STEP 10: Verifica configurazione NGINX ───
echo -e "\n🔍  \e[1;33mSTEP 10:\e[0m Verifica configurazione NGINX"
sudo /www/server/nginx/sbin/nginx -t

# ─── STEP 11: Ricarico o avvio NGINX ───
echo -e "\n🔁  \e[1;33mSTEP 11:\e[0m Ricarico o avvio NGINX"
if sudo lsof -i :80 -sTCP:LISTEN >/dev/null; then
  sudo /www/server/nginx/sbin/nginx -s reload || {
    sudo pkill nginx
    sudo /www/server/nginx/sbin/nginx
  }
else
  sudo /www/server/nginx/sbin/nginx
fi

# ─── STEP 12: Stampo info porte ───
echo -e "\n🔢  \e[1;33mSTEP 12:\e[0m Porte assegnate"
PORTS_FILE="$DEPLOY_ROOT/assigned_ports.env"
[[ -f "$PORTS_FILE" ]] || { echo "❌ File porte mancante: $PORTS_FILE"; exit 1; }
source "$PORTS_FILE"
[[ -z "${FRONT_PORT:-}" || -z "${BACK_PORT:-}" ]] && { echo "❌ Variabili porte non presenti"; exit 1; }
echo -e "    ➤ FRONT_PORT: $FRONT_PORT"
echo -e "    ➤ BACK_PORT:  $BACK_PORT"
echo -e "\n🌐  URL:"
echo -e "    🔗 Frontend ➝ http://localhost:$FRONT_PORT/"
echo -e "    🔗 Backend  ➝ http://localhost:$BACK_PORT/"

# ─── STEP 13: Cleanup ───
echo -e "\n🧹  \e[1;33mSTEP 13:\e[0m Pulizia cartelle temporanee"
# sudo rm -rf "$DEPLOY_ROOT"

# ─── STEP 14: Fine ───
echo -e "\n✅  \e[1;32mSTEP 14:\e[0m Deploy completato con successo: $PROJECT_NAME ($MODE)\e[0m"
