#!/bin/bash

# simb-build-deploy.sh
# Esegue build reale di frontend Angular e backend Laravel, popola
# la cartella deploy/www/wwwroot/{dev,prod}/<project> per un'anteprima completa.

set -e

# Controllo parametro environment (-dev o -prod)
if [[ "$1" != "-dev" && "$1" != "-prod" ]]; then
  echo "❌ Uso: $0 -dev|-prod <progetto>"
  echo "   esempio: $0 -dev /path/to/wyrmrest.com o $0 -prod wyrmrest.com"
  exit 1
fi
MODE=${1#-}  # dev o prod
shift

# Determina PROJECT_PATH
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
if [ -z "$1" ]; then
  echo "❌ Specifica il percorso o il nome del progetto"
  exit 1
elif [ -d "$1" ]; then
  PROJECT_PATH=$(realpath "$1")
elif [ -d "$SCRIPT_DIR/$1" ]; then
  PROJECT_PATH=$(realpath "$SCRIPT_DIR/$1")
else
  echo "❌ Cartella progetto '$1' non trovata"
  exit 1
fi
PROJECT_NAME=$(basename "$PROJECT_PATH")

# Directory sorgenti
FRONTEND_SRC=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_frontend")
BACKEND_SRC=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_backend")

# Verifica sorgenti
if [ ! -d "$FRONTEND_SRC" ] || [ ! -d "$BACKEND_SRC" ]; then
  echo "❌ Cartelle *_frontend o *_backend non trovate in $PROJECT_PATH"
  exit 1
fi

# Imposta cartelle di deploy in base a MODE
DEPLOY_ROOT="$SCRIPT_DIR/deploy/www/wwwroot/$MODE/$PROJECT_NAME"
FRONTEND_DEST="$DEPLOY_ROOT/frontend"
BACKEND_DEST="$DEPLOY_ROOT/backend"

# Pulisci e crea cartelle
echo "🚧 Preparo deploy ($MODE) per progetto '$PROJECT_NAME' in $DEPLOY_ROOT"
rm -rf "$FRONTEND_DEST" "$BACKEND_DEST"
mkdir -p "$FRONTEND_DEST" "$BACKEND_DEST"

# --- Build Frontend Angular ---
echo "🔨 Build Angular in $FRONTEND_SRC"
cd "$FRONTEND_SRC"
npm install --silent
npm run build -- --configuration production

# Trova dist directory
if [ -d "dist/frontend" ]; then
  DIST_DIR="dist/frontend"
else
  DIST_DIR=$(find dist -maxdepth 1 -type d ! -name dist | head -n1)
fi
if [ -z "$DIST_DIR" ] || [ ! -d "$DIST_DIR" ]; then
  echo "❌ Build Angular fallita: dist non trovata ($DIST_DIR)"
  exit 1
fi

# Copia frontend statico
echo "🚀 Copio frontend da $DIST_DIR in $FRONTEND_DEST"
cp -r "$DIST_DIR/"* "$FRONTEND_DEST/"

# --- Prepara Backend Laravel ---
echo "📂 Popolo backend in $BACKEND_SRC in $BACKEND_DEST"
rsync -a --exclude .env --exclude vendor "$BACKEND_SRC/" "$BACKEND_DEST/"

# Copia .env.prod o .env.example
if [ -f "$BACKEND_SRC/.env.prod" ]; then
  cp "$BACKEND_SRC/.env.prod" "$BACKEND_DEST/.env"
elif [ -f "$BACKEND_SRC/.env.example" ]; then
  cp "$BACKEND_SRC/.env.example" "$BACKEND_DEST/.env"
fi

# Installa dipendenze produzione
echo "🔧 Composer install in $BACKEND_DEST"
cd "$BACKEND_DEST"
composer install --no-dev --optimize-autoloader --no-interaction

# Genera chiave Laravel
echo "🔑 Generazione APP_KEY"
php artisan key:generate --ansi --quiet

# Imposta permessi corretti
echo "🔐 Correzione permessi storage/ e bootstrap/cache/"
sudo chown -R www:www storage bootstrap/cache
sudo chmod -R 775 storage bootstrap/cache

# --- Fine ---

echo "✅ Deploy ($MODE) simulato pronto in $DEPLOY_ROOT"
echo "   • Frontend: $FRONTEND_DEST"
echo "   • Backend:  $BACKEND_DEST"
