#!/bin/bash

# simb-build-frontend.sh
# Builda il frontend Angular e lo copia nella directory di deploy

set -e

# 📍 Parametri
echo -e "\n🔧 STEP 0: Verifica dei parametri"
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
  shift
fi

# Recupero percorso del progetto
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_PATH=$(realpath "$PROJECT")
PROJECT_NAME=$(basename "$PROJECT_PATH")

# Controlli preliminari sull’input
echo -e "\n🔍 STEP 1: Verifica cartella del progetto"
if [ ! -d "$PROJECT_PATH" ]; then
  echo "❌ La cartella del progetto non esiste: $PROJECT_PATH"
  exit 1
fi

# Cerchiamo la cartella *_frontend
FRONTEND_DIR=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_frontend")
if [ -z "$FRONTEND_DIR" ]; then
  echo "❌ Nessuna cartella *_frontend trovata in $PROJECT_PATH"
  exit 1
fi

# Estraggo il nome del progetto dal nome della cartella (prima del carattere '_')
PROJECT_NAME=$(basename "$FRONTEND_DIR" | cut -d'_' -f1)

# Riepilogo iniziale
echo -e "\nℹ️ STEP 2: Riepilogo del progetto"
echo "ℹ️  Modalità di deploy:  $MODE"
echo "ℹ️  Nome progetto:      $PROJECT_NAME"
echo "ℹ️  Percorso progetto:   $PROJECT_PATH"
echo "ℹ️  Frontend trovato in: $FRONTEND_DIR"

# Conferma per procedere
read -rp $'\e[1;33m⚠️  Confermi di procedere con il deploy del frontend? [\e[1;32my/\e[1;31mN\e[0m] (default N): ' CONFIRM
CONFIRM=${CONFIRM:-n}
CONFIRM=${CONFIRM,,}
if [[ "$CONFIRM" != "y" ]]; then
  echo "⏹️  Operazione annullata."
  exit 1
fi

# 📌 Chiedo se è progetto principale? (default N)
echo -e "\n📌 STEP 3: Chiedi se il progetto è principale"
read -rp $'\e[1;33m📌 È il progetto principale? [\e[1;32my/\e[1;31mN\e[0m] (default N): ' IS_MAIN
IS_MAIN=${IS_MAIN:-n}     # default n
IS_MAIN=${IS_MAIN,,}      # lowercase

if [[ "$IS_MAIN" == "y" ]]; then
  sudo rm -rf "$SCRIPT_DIR/deploy/www/wwwroot/$MODE/apps"
  BASE_DIR="$SCRIPT_DIR/deploy/www/wwwroot/$MODE/$PROJECT_NAME"
else
  BASE_DIR="$SCRIPT_DIR/deploy/www/wwwroot/$MODE/apps/$PROJECT_NAME"
fi

FRONTEND_DEST="$BASE_DIR/frontend"

echo "⚙️ STEP 4: Destinazione del frontend: $FRONTEND_DEST"

# Creazione della cartella di destinazione
echo -e "\n📁 STEP 5: Creazione della cartella di destinazione"
rm -rf "$FRONTEND_DEST"
mkdir -p "$FRONTEND_DEST"

# 🗂️ Carico il file delle porte
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
ENV_DIR="$FRONTEND_DIR/src/environments"
API_URL="http://localhost:$BACK_PORT/api"
mkdir -p "$ENV_DIR"

# Generazione dei file environment
echo -e "\n🔧 STEP 6: Creazione dei file environment.ts"
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

echo "🔧 File environment aggiornati con apiUrl: $API_URL"

# --- 🔨 STEP 7: Build Angular ---
echo -e "\n📦 STEP 7: Eseguo il build del frontend Angular"

# Verifica se la directory del frontend esiste
if [[ ! -d "$FRONTEND_DIR" ]]; then
  echo "❌ Directory del frontend non trovata: $FRONTEND_DIR"
  exit 1
fi

# Pulizia della cartella dist prima di eseguire il build
rm -rf "$FRONTEND_DIR/dist"
chown -R "$(id -u):$(id -g)" "$FRONTEND_DIR"
cd "$FRONTEND_DIR"

# Installazione delle dipendenze e build del progetto
npm install --silent

# Prepara il comando di build
CMD="npx ng build --configuration production --base-href \"$BASE_HREF\" \
  --output-path=dist/frontend --delete-output-path=false"

# Stampa e chiedi conferma per eseguire il build
echo "⚙️ Comando di build: $CMD"
read -p "Procedere con il build? [y/N] " CONFIRM
CONFIRM=${CONFIRM,,}
if [[ "$CONFIRM" != "y" ]]; then
  echo "❌ Build annullato."
  exit 1
fi

# Esegui il comando di build
eval $CMD

# --- 📦 STEP 8: Trova la cartella dist ---
echo -e "\n📂 STEP 8: Trovo la cartella dist"
if [ -d "dist/frontend" ]; then
  DIST_DIR="dist/frontend"
else
  DIST_DIR=$(find dist -maxdepth 1 -type d ! -name dist | head -n1)
fi
if [ ! -d "$DIST_DIR" ]; then
  echo "❌ Output Angular non trovato"
  exit 1
fi

# --- 🚚 STEP 9: Copia i file nella destinazione ---
echo -e "\n🚚 STEP 9: Copio i file di build nella destinazione"
mkdir -p "$FRONTEND_DEST"
cp -r "$DIST_DIR/"* "$FRONTEND_DEST"

echo "✅ Frontend copiato in $FRONTEND_DEST"
