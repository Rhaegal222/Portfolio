#!/bin/bash

# deploy-prod.sh
# Costruisce e copia frontend/backend nella cartella finta di DEV

set -e
trap "echo '❌ Errore durante il finto deploy. Uscita.'; exit 1" ERR

# === Controllo parametro ===
if [ -z "$1" ]; then
    echo "❌ Uso: $0 /percorso/progetto (es: ./wyrmrest.com)"
    exit 1
fi

# Percorsi progetto
PROJECT_PATH=$(realpath "$1")
PROJECT_NAME=$(basename "$PROJECT_PATH")
FRONTEND_SRC=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_frontend")
BACKEND_SRC=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_backend")

# Directory di finto deploy
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DEPLOY_ROOT="$SCRIPT_DIR/deploy/www"
DEPLOY_BASE="$DEPLOY_ROOT/wwwroot/prod/$PROJECT_NAME"

FRONTEND_DEST="$DEPLOY_BASE/frontend"
BACKEND_DEST="$DEPLOY_BASE/backend"

# Backup directory
FRONTEND_BACKUP="$FRONTEND_DEST.bak"
BACKEND_BACKUP="$BACKEND_DEST.bak"

# Informazioni iniziali
echo "📂 Progetto: $PROJECT_NAME"
echo "🌐 Frontend sorgente: $FRONTEND_SRC"
echo "🔧 Backend sorgente: $BACKEND_SRC"

# Verifica sorgenti
if [ ! -d "$FRONTEND_SRC" ] || [ ! -d "$BACKEND_SRC" ]; then
    echo "❌ Cartelle *_frontend o *_backend non trovate!"
    exit 1
fi

# Prepara cartelle e backup
echo "🔄 Preparazione deploy in $DEPLOY_BASE"
mkdir -p "$DEPLOY_BASE"

# Pulisci eventuali backup precedenti
if [ -d "$FRONTEND_BACKUP" ]; then
  rm -rf "$FRONTEND_BACKUP"
fi
if [ -d "$BACKEND_BACKUP" ]; then
  rm -rf "$BACKEND_BACKUP"
fi
# Esegui il backup spostando le cartelle correnti
if [ -d "$FRONTEND_DEST" ]; then
  mv "$FRONTEND_DEST" "$FRONTEND_BACKUP"
fi
if [ -d "$BACKEND_DEST" ]; then
  mv "$BACKEND_DEST" "$BACKEND_BACKUP"
fi

# === Build Angular ===
echo -e "\n🔨 Build Angular..."
cd "$FRONTEND_SRC"
npm install --silent
npm run build -- --configuration production

# Individua dist directory
DIST_DIR=$(find dist -maxdepth 1 -type d -not -name dist | head -n 1)
if [ ! -d "$DIST_DIR" ]; then
    echo "❌ Build Angular fallita (dist non trovata)"
    exit 1
fi

# Se esiste la cartella browser (prerender), usala, altrimenti prendi DIST_DIR
if [ -d "$DIST_DIR/browser" ]; then
  SRC_DIST="$DIST_DIR/browser"
else
  SRC_DIST="$DIST_DIR"
fi

# Copia frontend statico (index.html, assets, ecc.)
echo "🚚 Copia frontend in $FRONTEND_DEST"
mkdir -p "$FRONTEND_DEST"
cp -r "$SRC_DIST/"* "$FRONTEND_DEST"

# Copia backend
echo "🚚 Copia backend in $BACKEND_DEST"
mkdir -p "$BACKEND_DEST"
rsync -a --exclude vendor --exclude .env "$BACKEND_SRC/" "$BACKEND_DEST/"

# Copia .env.prod se presente
if [ -f "$BACKEND_SRC/.env.prod" ]; then
  echo "📄 Copia .env.prod"
  cp "$BACKEND_SRC/.env.prod" "$BACKEND_DEST/.env"
fi

# Messaggio fine deploy
echo "✅ Finto deploy completato: codice pronto in $DEPLOY_BASE"