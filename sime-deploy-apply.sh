#!/usr/bin/env bash
#
# sime-deploy-apply.sh
# Applica il deploy effettivo in /www, trasferendo la configurazione e il progetto
# Uso: ./sime-deploy-apply.sh -dev|-prod

set -euo pipefail

# ─── Funzioni ────────────────────────────────────────────────────────────────

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "❌ Questo script richiede permessi di root. Uso sudo..."
    exec sudo "$0" "$@"
  fi
}

parse_args() {
  echo -e "\n🔍  \e[1;33mSTEP 1:\e[0m Verifico parametro environment"
  if [[ "${1:-}" != "-dev" && "${1:-}" != "-prod" ]]; then
    echo -e "❌ \e[1;31mUso corretto:\e[0m $0 -dev|-prod"
    exit 1
  fi
  MODE="${1#-}"
}

init_vars() {
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  DEPLOY_ROOT="$SCRIPT_DIR/deploy"

  CONF_SRC="$DEPLOY_ROOT/www/server/nginx/conf"
  WWW_SRC="$DEPLOY_ROOT/www/wwwroot/$MODE"
  LOGS_SRC="$DEPLOY_ROOT/www/wwwlogs/$MODE"

  CONF_DEST="/www/server/nginx/conf"
  WWW_DEST="/www/wwwroot/$MODE"
  LOGS_DEST="/www/wwwlogs/$MODE"

  echo -e "\n🗂️  \e[1;33mSTEP 2:\e[0m Variabili inizializzate"
  cat <<EOF
    ➤ MODE        = $MODE
    ➤ DEPLOY_ROOT = $DEPLOY_ROOT
    ➤ CONF_SRC    = $CONF_SRC
    ➤ WWW_SRC     = $WWW_SRC
    ➤ LOGS_SRC    = $LOGS_SRC
    ➤ CONF_DEST   = $CONF_DEST
    ➤ WWW_DEST    = $WWW_DEST
    ➤ LOGS_DEST   = $LOGS_DEST
EOF
}

detect_project() {
  echo -e "\n📂  \e[1;33mSTEP 3:\e[0m Rilevo nome e percorso progetto"
  if [[ -d "$WWW_SRC/apps" ]]; then
    PROJECT_NAME=$(find "$WWW_SRC/apps" -mindepth 1 -maxdepth 1 -type d | head -n1 | xargs basename)
    PROJECT_SRC="$WWW_SRC/apps/$PROJECT_NAME"
    PROJECT_DEST="$WWW_DEST/apps/$PROJECT_NAME"
    VHOST_SUBDIR="apps"
  else
    PROJECT_NAME=$(find "$WWW_SRC" -mindepth 1 -maxdepth 1 -type d | head -n1 | xargs basename)
    PROJECT_SRC="$WWW_SRC/$PROJECT_NAME"
    PROJECT_DEST="$WWW_DEST/$PROJECT_NAME"
    VHOST_SUBDIR=""
  fi

  if [[ -z "$PROJECT_NAME" ]]; then
    echo -e "❌ Nessun progetto trovato in $WWW_SRC"
    exit 1
  fi

  echo "    ➤ Progetto: $PROJECT_NAME"
  echo "    ➤ Percorso: $PROJECT_SRC"
}

sync_nginx_conf() {
  echo -e "\n🔁  \e[1;33mSTEP 4:\e[0m Sincronizzo conf.d"
  SRC_CONF_D="$CONF_SRC/conf.d"
  DST_CONF_D="$CONF_DEST/conf.d"

  sudo mkdir -p "$DST_CONF_D"
  sudo rsync -av "$SRC_CONF_D/" "$DST_CONF_D/"

  echo "    ➤ Copiato/aggiornato: $SRC_CONF_D → $DST_CONF_D"
}

copy_main_conf() {
  echo -e "\n📄  \e[1;33mSTEP 5:\e[0m Copio nginx.conf se mancante"
  if [[ -f "$CONF_SRC/nginx.conf" && ! -f "$CONF_DEST/nginx.conf" ]]; then
    cp -v "$CONF_SRC/nginx.conf" "$CONF_DEST/nginx.conf"
  else
    echo "⚠️  $CONF_DEST/nginx.conf già presente"
  fi
}

update_vhost_symlink() {
  echo -e "\n🔗  STEP 6: Aggiorno symlink VHOST"

  # cartella base di conf.d
  local BASE="$CONF_DEST/conf.d"
  # directory sites-available ed enabled per questo MODE
  local SA_BASE="$BASE/sites-available/$MODE"
  local SE_BASE="$BASE/sites-enabled/$MODE"

  # se il progetto è sotto apps/, usiamo la sottocartella apps
  if [[ -d "$WWW_DEST/apps/$PROJECT_NAME" ]]; then
    SA_DIR="$SA_BASE/apps"
    SE_DIR="$SE_BASE"
  else
    SA_DIR="$SA_BASE"
    SE_DIR="$SE_BASE"
  fi

  # percorso del file .conf
  local SA_CONF="$SA_DIR/$PROJECT_NAME.conf"

  if [[ ! -f "$SA_CONF" ]]; then
    echo "❌ Configurazione mancante: $SA_CONF"
    exit 1
  fi

  # creiamo la dir enabled e colleghiamo
  mkdir -p "$SE_DIR"
  ln -sf "$SA_CONF" "$SE_DIR/$PROJECT_NAME.conf"
  echo "    ➤ Symlink creato: $SE_DIR/$PROJECT_NAME.conf → $SA_CONF"
}

deploy_project() {
  echo -e "\n🌍  \e[1;33mSTEP 7:\e[0m Deploy del progetto"
  if [[ -d "$PROJECT_DEST" ]]; then
    read -rp "Esiste già $PROJECT_DEST. Sovrascrivere? [y/N]: " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
      chattr -i -R "$PROJECT_DEST" || true
      rm -rf "$PROJECT_DEST"
    else
      echo "❌ Deploy annullato."
      exit 1
    fi
  fi
  mkdir -p "$PROJECT_DEST"
  rsync -a --delete "$PROJECT_SRC"/ "$PROJECT_DEST"/
  echo "    ➤ Copiato: $PROJECT_SRC → $PROJECT_DEST"
}

copy_env() {
  echo -e "\n🗝️   \e[1;33mSTEP 8:\e[0m Copio .env del backend"
  local ENV_SRC="$PROJECT_SRC/backend/.env"
  local ENV_DEST="$PROJECT_DEST/backend/.env"
  if [[ -f "$ENV_SRC" ]]; then
    cp -v "$ENV_SRC" "$ENV_DEST"
  else
    echo "⚠️  Nessun .env in $PROJECT_SRC/backend"
  fi
}

copy_logs() {
  echo -e "\n📤  STEP 9: Copio file di log"

  # Determino il percorso relativo dei log (con o senza "apps/")
  if [[ -d "$LOGS_SRC/apps/$PROJECT_NAME" ]]; then
    REL_LOG_PATH="apps/$PROJECT_NAME"
  else
    REL_LOG_PATH="$PROJECT_NAME"
  fi

  SRC_LOG_DIR="$LOGS_SRC/$REL_LOG_PATH"
  DEST_LOG_DIR="$LOGS_DEST/$REL_LOG_PATH"

  # Ricreo la destinazione da zero
  sudo rm -rf "$DEST_LOG_DIR"
  sudo mkdir -p "$DEST_LOG_DIR"
  echo "    ➤ Src logs: $SRC_LOG_DIR"
  echo "    ➤ Dst logs: $DEST_LOG_DIR"

  for f in front_access front_error api_access api_error; do
    LOG_SRC="$SRC_LOG_DIR/${PROJECT_NAME}_${f}.log"
    LOG_DST="$DEST_LOG_DIR/${PROJECT_NAME}_${f}.log"
    if [[ -f "$LOG_SRC" ]]; then
      sudo cp -v "$LOG_SRC" "$LOG_DST"
    else
      echo "  ⚠️  Mancante: $LOG_SRC"
    fi
  done
}

test_nginx_conf() {
  echo -e "\n🔍  \e[1;33mSTEP 10:\e[0m Verifica configurazione NGINX"
  nginx -t
}

reload_nginx() {
  echo -e "\n🔁  \e[1;33mSTEP 11:\e[0m Ricarico o avvio NGINX"
  if sudo lsof -i :80 -sTCP:LISTEN >/dev/null; then
    sudo /www/server/nginx/sbin/nginx -s reload || {
      sudo pkill nginx
      sudo /www/server/nginx/sbin/nginx
    }
  else
    sudo /www/server/nginx/sbin/nginx
  fi
}

print_ports() {
  echo -e "\n🔢  \e[1;33mSTEP 12:\e[0m Porte assegnate"
  source "$DEPLOY_ROOT/assigned_ports.env"
  echo "    ➤ FRONT_PORT: $FRONT_PORT"
  echo "    ➤ BACK_PORT:  $BACK_PORT"
  echo -e "\n🌐  URL:"
  echo "    🔗 Frontend ➝ http://localhost:$FRONT_PORT/"
  echo "    🔗 Backend  ➝ http://localhost:$BACK_PORT/"
}

print_summary() {
  echo -e "\n✅  \e[1;32mSTEP 14:\e[0m Deploy completato: $PROJECT_NAME ($MODE)"
}

# ─── Main ───────────────────────────────────────────────────────────────────

require_root "$@"
parse_args "$@"
init_vars
detect_project
sync_nginx_conf
copy_main_conf
update_vhost_symlink
deploy_project
copy_env
copy_logs
test_nginx_conf
reload_nginx
print_ports
print_summary
