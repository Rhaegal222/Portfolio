#!/bin/bash

# simb-builc-frontend.sh
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

echo "📦 Build frontend: $PROJECT_NAME"

# Cleanup
rm -rf "$FRONTEND_SRC/dist"
chown -R $(id -u):$(id -g) "$FRONTEND_SRC"

# Build Angular
cd "$FRONTEND_SRC"
npm install --silent
npm run build -- --configuration production

# Trova cartella dist
if [ -d "dist/frontend" ]; then
  DIST_DIR="dist/frontend"
else
  DIST_DIR=$(find dist -maxdepth 1 -type d ! -name dist | head -n1)
fi

if [ ! -d "$DIST_DIR" ]; then
  echo "❌ Output Angular non trovato"
  exit 1
fi

# Copia dist
mkdir -p "$FRONTEND_DEST"
cp -r "$DIST_DIR/"* "$FRONTEND_DEST/"

echo "✅ Frontend copiato in $FRONTEND_DEST"
