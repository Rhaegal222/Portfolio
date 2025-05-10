#!/bin/bash

# simb-build-frontend.sh
# Builda il frontend Angular e lo copia nella directory di deploy

set -e

# 📍 Parametri
if [[ "$1" != "-dev" && "$1" != "-prod" ]]; then
  echo "❌ Uso corretto: $0 -dev|-prod <percorso_progetto>"
  exit 1
fi
MODE=${1#-}
shift

if [ -z "$1" ]; then
  echo "❌ Specificare percorso progetto"
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_PATH=$(realpath "$1")
PROJECT_NAME=$(basename "$PROJECT_PATH")
FRONTEND_SRC=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_frontend")
FRONTEND_DEST="$SCRIPT_DIR/deploy/www/wwwroot/$MODE/$PROJECT_NAME/frontend"

# --- 🔍 STEP 0: Leggo le porte assegnate da file ---
PORTS_FILE="$SCRIPT_DIR/assigned_ports.env"
if [ ! -f "$PORTS_FILE" ]; then
  echo "❌ File porte non trovato: $PORTS_FILE"
  exit 1
fi
source "$PORTS_FILE"

if [ -z "${BACK_PORT:-}" ]; then
  echo "❌ BACK_PORT non trovata nel file"
  exit 1
fi

# --- 🛠️ STEP 1: Aggiorno i file environment ---
ENV_DIR="$FRONTEND_SRC/src/environments"
API_URL="http://localhost:$BACK_PORT/api"
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

echo "🔧 File environment aggiornati con apiUrl: $API_URL"

# --- 🔨 STEP 2: Build Angular ---
echo "📦 Build frontend: $PROJECT_NAME"

rm -rf "$FRONTEND_SRC/dist"
chown -R $(id -u):$(id -g) "$FRONTEND_SRC"

cd "$FRONTEND_SRC"
npm install --silent
npm run build -- --configuration production

# --- 📦 STEP 3: Trova cartella dist ---
if [ -d "dist/frontend" ]; then
  DIST_DIR="dist/frontend"
else
  DIST_DIR=$(find dist -maxdepth 1 -type d ! -name dist | head -n1)
fi

if [ ! -d "$DIST_DIR" ]; then
  echo "❌ Output Angular non trovato"
  exit 1
fi

# --- 🚚 STEP 4: Copia dist ---
mkdir -p "$FRONTEND_DEST"
cp -r "$DIST_DIR/"* "$FRONTEND_DEST/"

echo "✅ Frontend copiato in $FRONTEND_DEST"
