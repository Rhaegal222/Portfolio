#!/usr/bin/env bash
#
# simb-build-backend.sh
# Prepara il backend Laravel per il deploy

set -euo pipefail

# ─── Funzioni ────────────────────────────────────────────────────────────────

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "❌ Questo script deve essere eseguito con i permessi di root. Esegui con sudo."
    exec sudo "$0" "$@"
  fi
}

parse_args() {
  echo -e "\n🔍  \e[1;33mSTEP 0:\e[0m Verifico parametri"
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

  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  PROJECT_PATH=$(realpath "$PROJECT")
}

step1_verify_project() {
  echo -e "\n🔍  \e[1;33mSTEP 1:\e[0m Verifico cartella progetto"
  if [ ! -d "$PROJECT_PATH" ]; then
    echo "❌ La cartella del progetto non esiste: $PROJECT_PATH"
    exit 1
  fi
}

step2_detect_backend_dir() {
  echo -e "\n🔍  \e[1;33mSTEP 2:\e[0m Cerco cartella *_backend"
  BACKEND_DIR=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_backend" | head -n1)
  if [ -z "$BACKEND_DIR" ]; then
    echo "❌ Nessuna cartella *_backend trovata in $PROJECT_PATH"
    exit 1
  fi
  PROJECT_NAME=$(basename "$BACKEND_DIR" | cut -d'_' -f1)
}

step3_show_summary() {
  echo -e "\nℹ️   \e[1;32mRiepilogo del progetto\e[0m"
  echo -e "  ➤ Modalità di deploy: \e[1;33m$MODE\e[0m"
  echo -e "  ➤ Nome progetto:      \e[1;33m$PROJECT_NAME\e[0m"
  echo -e "  ➤ Percorso progetto:  \e[1;33m$PROJECT_PATH\e[0m"
  echo -e "  ➤ Backend trovato:    \e[1;33m$BACKEND_DIR\e[0m"
}

step4_confirm_deploy() {
  read -rp $'\n⚠️   Confermi di procedere con il deploy? [y/N]: ' CONFIRM
  CONFIRM=${CONFIRM:-n}; CONFIRM=${CONFIRM,,}
  if [[ "$CONFIRM" != "y" ]]; then
    echo "⏹️  Operazione annullata"
    exit 1
  fi
}

step5_detect_main() {
  IS_MAIN_FILE="$SCRIPT_DIR/deploy/is_main.env"
  IS_MAIN="n"
  if [[ -f "$IS_MAIN_FILE" ]]; then
    source "$IS_MAIN_FILE"
    IS_MAIN=${IS_MAIN,,}
  fi
  if [[ "$IS_MAIN" != "y" && "$IS_MAIN" != "n" ]]; then
    read -rp $'\n📌  È il progetto principale? [y/N]: ' IS_MAIN
    IS_MAIN=${IS_MAIN:-n}; IS_MAIN=${IS_MAIN,,}
    if [[ "$IS_MAIN" != "y" && "$IS_MAIN" != "n" ]]; then
      echo "❌ Risposta non valida"
      exit 1
    fi
    echo "IS_MAIN=$IS_MAIN" > "$IS_MAIN_FILE"
  fi
}

step6_prepare_base_dir() {
  if [[ "$IS_MAIN" == "y" ]]; then
    BASE_DIR="$SCRIPT_DIR/deploy/www/wwwroot/$MODE/$PROJECT_NAME"
  else
    BASE_DIR="$SCRIPT_DIR/deploy/www/wwwroot/$MODE/apps/$PROJECT_NAME"
  fi
  BACKEND_DEST="$BASE_DIR/backend"
  echo -e "\n⚙️   \e[1;33mSTEP 3:\e[0m Deploy backend in \e[1;32m$BACKEND_DEST\e[0m"
  rm -rf "$BACKEND_DEST"
  mkdir -p "$BACKEND_DEST"
}

step7_copy_source() {
  rsync -a --exclude .env --exclude vendor "$BACKEND_DIR"/ "$BACKEND_DEST"/
}

step8_copy_env() {
  echo -e "\n🔧  \e[1;33mSTEP 3.1:\e[0m Copia file di configurazione"
  if [[ -f "$BACKEND_DIR/.env.prod" && "$MODE" == "prod" ]]; then
    cp "$BACKEND_DIR/.env.prod" "$BACKEND_DEST/.env"
  elif [[ -f "$BACKEND_DIR/.env.example" ]]; then
    cp "$BACKEND_DIR/.env.example" "$BACKEND_DEST/.env"
  fi
}

step9_install_dependencies() {
  echo -e "\n📦  \e[1;33mSTEP 3.2:\e[0m Installazione dipendenze e key generation"
  pushd "$BACKEND_DEST" >/dev/null
  composer install --no-dev --optimize-autoloader --no-interaction
  php artisan key:generate --ansi --quiet
  popd >/dev/null
}

step10_set_permissions() {
  echo -e "\n🔐   \e[1;33mSTEP 3.3:\e[0m Imposto permessi"
  chown -R www:www "$BACKEND_DEST/storage" "$BACKEND_DEST/bootstrap/cache"
  chmod -R 775 "$BACKEND_DEST/storage" "$BACKEND_DEST/bootstrap/cache"
}

step11_summary() {
  echo -e "\n✅   \e[1;32mBackend pronto in $BACKEND_DEST\e[0m"
}

# ─── Main ───────────────────────────────────────────────────────────────────

require_root "$@"
parse_args "$@"
step1_verify_project
step2_detect_backend_dir
step3_show_summary
step4_confirm_deploy
step5_detect_main
step6_prepare_base_dir
step7_copy_source
step8_copy_env
step9_install_dependencies
step10_set_permissions
step11_summary
