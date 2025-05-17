#!/usr/bin/env bash
#
# simc-build-frontend.sh
# Builda il frontend Angular e lo copia nella directory di deploy

set -euo pipefail

# ─── Funzioni ────────────────────────────────────────────────────────────────

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "❌ Questo script richiede permessi di root. Uso sudo..."
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

verify_project() {
  echo -e "\n🔍  \e[1;33mSTEP 1:\e[0m Verifica cartella progetto"
  if [ ! -d "$PROJECT_PATH" ]; then
    echo "❌ Cartella non trovata: $PROJECT_PATH"
    exit 1
  fi
}

detect_frontend_dir() {
  echo -e "\n🔍  \e[1;33mSTEP 2:\e[0m Trovo cartella *_frontend"
  FRONTEND_DIR=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_frontend" | head -n1)
  if [ -z "$FRONTEND_DIR" ]; then
    echo "❌ Nessuna cartella *_frontend in $PROJECT_PATH"
    exit 1
  fi
  PROJECT_NAME=$(basename "$FRONTEND_DIR" | cut -d'_' -f1)
}

show_summary() {
  echo -e "\nℹ️   \e[1;32mRiepilogo progetto\e[0m"
  echo -e "  ➤ Modalità:        \e[1;33m$MODE\e[0m"
  echo -e "  ➤ Progetto:        \e[1;33m$PROJECT_NAME\e[0m"
  echo -e "  ➤ Percorso:        \e[1;33m$PROJECT_PATH\e[0m"
  echo -e "  ➤ Frontend dir:    \e[1;33m$FRONTEND_DIR\e[0m"
}

confirm_deploy() {
  read -rp $'\n⚠️   Confermi di procedere con il deploy? [y/N]: ' CONFIRM
  CONFIRM=${CONFIRM:-n}; CONFIRM=${CONFIRM,,}
  if [[ "$CONFIRM" != "y" ]]; then
    echo "⏹️  Operazione annullata"
    exit 1
  fi
}

detect_main_project() {
  echo -e "\n📌  \e[1;33mSTEP 3:\e[0m È il progetto principale?"
  IS_MAIN_FILE="$SCRIPT_DIR/deploy/is_main.env"
  IS_MAIN="n"
  if [[ -f "$IS_MAIN_FILE" ]]; then
    source "$IS_MAIN_FILE"
    IS_MAIN=${IS_MAIN,,}
  fi
  if [[ "$IS_MAIN" != "y" && "$IS_MAIN" != "n" ]]; then
    read -rp $'\n❓  È principale? [y/N]: ' IS_MAIN
    IS_MAIN=${IS_MAIN:-n}; IS_MAIN=${IS_MAIN,,}
    if [[ "$IS_MAIN" != "y" && "$IS_MAIN" != "n" ]]; then
      echo "❌ Risposta non valida"
      exit 1
    fi
    echo "IS_MAIN=$IS_MAIN" > "$IS_MAIN_FILE"
  fi
}

prepare_dest_dirs() {
  echo -e "\n📁  \e[1;33mSTEP 4:\e[0m Preparo directory di destinazione"
  if [[ "$IS_MAIN" == "y" ]]; then
    BASE_DIR="$SCRIPT_DIR/deploy/www/wwwroot/$MODE/$PROJECT_NAME"
    BASE_HREF="/"
    DEPLOY_URL="/"
  else
    BASE_DIR="$SCRIPT_DIR/deploy/www/wwwroot/$MODE/apps/$PROJECT_NAME"
    BASE_HREF="/apps/$PROJECT_NAME/"
    DEPLOY_URL="/apps/$PROJECT_NAME/"
  fi
  FRONTEND_DEST="$BASE_DIR/frontend"

  echo "  ➕ DEST: $FRONTEND_DEST"
  rm -rf "$FRONTEND_DEST"
  mkdir -p "$FRONTEND_DEST"
}

load_ports() {
  echo -e "\n🚚  \e[1;33mSTEP 5:\e[0m Carico porte da assigned_ports.env"
  PORTS_FILE="$SCRIPT_DIR/deploy/assigned_ports.env"
  if [ ! -f "$PORTS_FILE" ]; then
    echo "❌ File porte mancante: $PORTS_FILE"
    exit 1
  fi
  source "$PORTS_FILE"
  if [ -z "${BACK_PORT:-}" ]; then
    echo "❌ BACK_PORT non definita"
    exit 1
  fi
}

setup_environments() {
  echo -e "\n🔧  \e[1;33mSTEP 6:\e[0m Genero environment.ts"
  ENV_DIR="$FRONTEND_DIR/src/environments"
  API_URL="http://localhost:$BACK_PORT"
  mkdir -p "$ENV_DIR"

  cat > "$ENV_DIR/environment.ts" <<EOF
export const environment = {
  production: false,
  apiUrl: '$API_URL'
};
EOF

  cat > "$ENV_DIR/environment.prod.ts" <<EOF
export const environment = {
  production: true,
  apiUrl: '$API_URL'
};
EOF

  echo "  ➤ apiUrl: $API_URL"
}

build_angular() {
  echo -e "\n🔨  \e[1;33mSTEP 7:\e[0m Build Angular"
  cd "$FRONTEND_DIR"
  echo -e "\n🧹  Pulizia dist"
  rm -rf dist
  chown -R "$(id -u):$(id -g)" .

  echo -e "\n🔧  npm install"
  npm install --silent

  CMD="npx ng build \
  --configuration production \
  --base-href \"$BASE_HREF\" \
  --deploy-url \"$DEPLOY_URL\" \
  --output-path=dist/frontend \
  --delete-output-path=false"

echo -e "\nℹ️   \e[1;32mFile environment aggiornati\e[0m\n"
echo -e "  ➤  apiUrl: \e[1;33m$API_URL\e[0m"

# ⚙️ Stampa e chiedi conferma per eseguire il build
echo -e "\nℹ️   \e[1;32mComando di build\e[0m\n"
echo -e "  ➤  \e[1;33m$CMD\e[0m"
  read -rp $'\n⚠️   Confermi build? [y/N]: ' CONFIRM
  CONFIRM=${CONFIRM,,}
  if [[ "$CONFIRM" != "y" ]]; then
    echo "❌ Build annullata"
    exit 1
  fi

  eval $CMD
}

find_dist_folder() {
  echo -e "\n📂  \e[1;33mSTEP 8:\e[0m Individuo cartella dist"
  if [ -d "$FRONTEND_DIR/dist/frontend" ]; then
    DIST_DIR="$FRONTEND_DIR/dist/frontend"
  else
    DIST_DIR=$(find "$FRONTEND_DIR/dist" -maxdepth 1 -type d | head -n1)
  fi
  if [ ! -d "$DIST_DIR" ]; then
    echo "❌ Dist non trovata"
    exit 1
  fi
  echo "  ➤ DIST: $DIST_DIR"
}

copy_dist_to_deploy() {
  echo -e "\n🚚  \e[1;33mSTEP 9:\e[0m Copio in $FRONTEND_DEST"
  cp -r "$DIST_DIR/"* "$FRONTEND_DEST"
}

print_summary() {
  echo -e "\n✅  \e[1;32mFrontend pronto in $FRONTEND_DEST\e[0m"
}

# ─── Main ───────────────────────────────────────────────────────────────────

require_root "$@"
parse_args "$@"
verify_project
detect_frontend_dir
show_summary
confirm_deploy
detect_main_project
prepare_dest_dirs
load_ports
setup_environments
build_angular
find_dist_folder
copy_dist_to_deploy
print_summary
