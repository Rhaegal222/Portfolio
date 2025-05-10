#!/bin/bash

# simb-build-frontend.sh
# Builda il frontend Angular e lo copia nella directory di deploy

set -e

# 📍 Parametri
echo -e "\n🔍  \e[1;33mSTEP 0:\e[0m Verifico modalità di esecuzione: \e[1;32m$1\e[0m"
if [[ "$1" != "-dev" && "$1" != "-prod" ]]; then
  echo "❌ Uso corretto: $0 -dev|-prod <percorso_progetto>"
  exit 1
fi
MODE=${1#-}
shift

# Verifica se è stato specificato un progetto
if [ -z "$1" ]; then
  echo "❌ Specificare nome progetto"
  exit 1
else
  PROJECT="$1"
  echo -e "\n➤  Progetto specificato: \e[1;32m$PROJECT\e[0m"
  shift
fi

# Recupero percorso del progetto
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_PATH=$(realpath "$PROJECT")
PROJECT_NAME=$(basename "$PROJECT_PATH")

# 📂 STEP 1: Verifica cartella del progetto
echo -e "\n🔍  \e[1;33mSTEP 1:\e[0m Verifica cartella del progetto"
if [ ! -d "$PROJECT_PATH" ]; then
  echo "❌ La cartella del progetto non esiste: $PROJECT_PATH"
  exit 1
fi

# Cerchiamo la cartella *_frontend
FRONTEND_DIR=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_frontend")
if [ -n "$FRONTEND_DIR" ]; then
  PROJECT_NAME=$(basename "$FRONTEND_DIR" | cut -d'_' -f1)
else
  echo "❌ Nessuna cartella *_frontend trovata in $PROJECT_PATH"
  exit 1
fi

# Riepilogo
echo -e "\nℹ️   \e[1;32mRiepilogo del progetto\e[0m\n"
echo -e "  ➤  Modalità di deploy: \e[1;33m$MODE\e[0m"
echo -e "  ➤  Nome progetto:      \e[1;33m$PROJECT_NAME\e[0m"
echo -e "  ➤  Percorso progetto:  \e[1;33m$PROJECT_PATH\e[0m"
echo -e "  ➤  Frontend trovato:   \e[1;33m$FRONTEND_DIR\e[0m"

# Verifica che sia un progetto Angular (package.json e angular.json)
echo -e "\n🔍  \e[1;33mSTEP 2:\e[0m Verifico presenza dei file Angular in $FRONTEND_DIR"
if [[ ! -f "$FRONTEND_DIR/package.json" || ! -f "$FRONTEND_DIR/angular.json" ]]; then
  echo "❌ Non sembra un progetto Angular (manca package.json o angular.json) in $FRONTEND_DIR"
  exit 1
fi

# ⚠️ Conferma per procedere
read -rp $'\n\e[1;33m⚠️   Confermi di procedere con il deploy? [\e[1;32my/\e[1;31mN\e[0m] (default N): ' CONFIRM
CONFIRM=${CONFIRM:-n}
CONFIRM=${CONFIRM,,}
if [[ "$CONFIRM" != "y" ]]; then
  echo "⏹️  Operazione annullata"
  exit 1
fi

# 📌 Chiedo se è progetto principale? (default N)
read -rp $'\n\e[1;33m📌  È il progetto principale? [\e[1;32my/\e[1;31mN\e[0m] (default N): ' IS_MAIN
IS_MAIN=${IS_MAIN:-n}     # default n
IS_MAIN=${IS_MAIN,,}      # lowercase

if [[ "$IS_MAIN" == "y" ]]; then
  sudo rm -rf "$SCRIPT_DIR/deploy/www/wwwroot/$MODE/apps"
  BASE_DIR="$SCRIPT_DIR/deploy/www/wwwroot/$MODE/$PROJECT_NAME"
else
  BASE_DIR="$SCRIPT_DIR/deploy/www/wwwroot/$MODE/apps/$PROJECT_NAME"
fi

FRONTEND_DEST="$BASE_DIR/frontend"

# 📁 Creazione della cartella di destinazione
echo -e "\n📁  \e[1;33mSTEP 3:\e[0m Creazione della cartella di destinazione \e[1;32m$FRONTEND_DIR\e[0m"
rm -rf "$FRONTEND_DEST"
mkdir -p "$FRONTEND_DEST"

# 🚚 Carico il file delle porte
echo -e "\n🚚   \e[1;33mSTEP 4:\e[0m Carico il file delle porte"
PORTS_FILE="$SCRIPT_DIR/deploy/assigned_ports.env"
if [ ! -f "$PORTS_FILE" ]; then
  echo "❌ File porte non trovato: $PORTS_FILE"
  exit 1
fi
source "$PORTS_FILE"
if [ -z "${BACK_PORT:-}" ]; then
  echo "❌ BACK_PORT non trovata nel file"
  exit 1
fi

# Imposto la variabile per l'URL dell'API
echo -e "\n🔧  \e[1;33mSTEP 5:\e[0m Imposto la variabile per l'URL dell'API"
ENV_DIR="$FRONTEND_DIR/src/environments"
API_URL="http://localhost:$BACK_PORT/api"
mkdir -p "$ENV_DIR"

echo -e "\n🌱  \e[1;33mSTEP 6:\e[0m Creazione di \e[1;33menvironment.ts\e[0m e \e[1;33menvironment.prod.ts\e[0m"
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

echo -e "\nℹ️   \e[1;32mFile environment aggiornati\e[0m\n"
echo -e "  ➤  apiUrl: \e[1;33m$API_URL\e[0m"

# 🔨 STEP 7: Esegui il build di Angular
echo -e "\n🔨  \e[1;33mSTEP 7:\e[0m Eseguo il build del frontend Angular"

# Verifica se la directory del frontend esiste
if [[ ! -d "$FRONTEND_DIR" ]]; then
  echo "❌ Directory del frontend non trovata: $FRONTEND_DIR"
  exit 1
fi

# Pulizia della cartella dist prima di eseguire il build
echo -e "\n🧹  \e[1;33mSTEP 7.1:\e[0m Pulizia della cartella dist"
rm -rf "$FRONTEND_DIR/dist"
chown -R "$(id -u):$(id -g)" "$FRONTEND_DIR"
cd "$FRONTEND_DIR"

echo -e "\n🔧  \e[1;33mSTEP 7.2:\e[0m Installazione delle dipendenze"
npm install --silent

# Prepara il comando di build
CMD="npx ng build --configuration production --base-href \"$BASE_HREF\" \
  --output-path=dist/frontend --delete-output-path=false"

echo -e "\nℹ️   \e[1;32mFile environment aggiornati\e[0m\n"
echo -e "  ➤  apiUrl: \e[1;33m$API_URL\e[0m"

# ⚙️ Stampa e chiedi conferma per eseguire il build
echo -e "\nℹ️   \e[1;32mComando di build\e[0m\n"
echo -e "  ➤  \e[1;33m$CMD\e[0m"

read -p $'\n\e[1;33m⚠️   Confermi di procedere con la build? [\e[1;32my/\e[1;31mN\e[0m] (default N): ' CONFIRM
CONFIRM=${CONFIRM,,}
if [[ "$CONFIRM" != "y" ]]; then
  echo "❌ Build annullato."
  exit 1
fi

# Esegui il comando di build
eval $CMD

# 📂 STEP 8: Trovo la cartella dist
echo -e "\n📂  \e[1;33mSTEP 8:\e[0m Trovo la cartella dist"
if [ -d "dist/frontend" ]; then
  DIST_DIR="dist/frontend"
else
  DIST_DIR=$(find dist -maxdepth 1 -type d ! -name dist | head -n1)
fi
if [ ! -d "$DIST_DIR" ]; then
  echo "❌ Output Angular non trovato"
  exit 1
fi

# 🚚 STEP 9: Copia i file nella destinazione
echo -e "\n🚚  \e[1;33mSTEP 9:\e[0m Copia i file nella destinazione \e[1;32m$FRONTEND_DEST\e[0m"
mkdir -p "$FRONTEND_DEST"
cp -r "$DIST_DIR/"* "$FRONTEND_DEST"

echo -e "\n✅  Frontend pronto in \e[1;32m$FRONTEND_DEST\e[0m"
