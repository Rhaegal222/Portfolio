#!/bin/bash
#
# simb-build-deploy.sh
# Esegue build reale di frontend Angular e backend Laravel, popola
# la cartella deploy/www/wwwroot/{dev,prod}/<project> per un'anteprima completa.
# Uso: ./simb-build-deploy.sh -dev | -prod <progetto>

set -e

# 📝 STEP 0: Verifica parametro environment
echo -e "\n🔍 \e[1;33mSTEP 0:\e[0m Verifico parametro environment"
if [[ "$1" != "-dev" && "$1" != "-prod" ]]; then
  echo -e "❌ \e[1;31mUso corretto:\e[0m $0 -dev|-prod <progetto>"
  echo "    esempio: $0 -dev /path/to/progetto o $0 -prod progetto.com"
  exit 1
fi
MODE=${1#-}
shift

# 🚀 STEP 1: Imposta variabili di deploy
echo -e "\n🚀 \e[1;33mSTEP 1:\e[0m Imposto MODE=$MODE"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# 🔍 STEP 2: Determina PROJECT_PATH
echo -e "\n🔍 \e[1;33mSTEP 2:\e[0m Determino percorso progetto"
if [ -z "$1" ]; then
  echo -e "❌ \e[1;31mErrore:\e[0m Specificare percorso o nome progetto"
  exit 1
elif [ -d "$1" ]; then
  PROJECT_PATH=$(realpath "$1")
elif [ -d "$SCRIPT_DIR/$1" ]; then
  PROJECT_PATH=$(realpath "$SCRIPT_DIR/$1")
else
  echo -e "❌ \e[1;31mErrore:\e[0m Cartella progetto '$1' non trovata"
  exit 1
fi
PROJECT_NAME=$(basename "$PROJECT_PATH")
echo -e "    ➤ Progetto: $PROJECT_NAME"

# 📂 STEP 3: Verifica directory sorgenti frontend e backend
echo -e "\n📂 \e[1;33mSTEP 3:\e[0m Verifico directory sorgenti"
FRONTEND_SRC=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_frontend")
BACKEND_SRC=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_backend")
if [ ! -d "$FRONTEND_SRC" ] || [ ! -d "$BACKEND_SRC" ]; then
  echo -e "❌ \e[1;31mErrore:\e[0m Directory *_frontend o *_backend non trovate"
  exit 1
fi
echo -e "    ➤ Frontend src: $FRONTEND_SRC"
echo -e "    ➤ Backend src:  $BACKEND_SRC"

# 🧹 STEP 4: Pulisci dist Angular e resetta permessi
echo -e "\n🧹 \e[1;33mSTEP 4:\e[0m Pulizia della directory dist e reset permessi"
if [ -d "$FRONTEND_SRC/dist" ]; then
  sudo rm -rf "$FRONTEND_SRC/dist"
fi
sudo chown -R $(id -u):$(id -g) "$FRONTEND_SRC"

# 🗂️ STEP 5: Preparo cartelle di destinazione
echo -e "\n🗂️  \e[1;33mSTEP 5:\e[0m Preparo cartelle di deploy"
DEPLOY_ROOT="$SCRIPT_DIR/deploy/www/wwwroot/$MODE/$PROJECT_NAME"
FRONTEND_DEST="$DEPLOY_ROOT/frontend"
BACKEND_DEST="$DEPLOY_ROOT/backend"
sudo rm -rf "$FRONTEND_DEST" "$BACKEND_DEST"
mkdir -p "$FRONTEND_DEST" "$BACKEND_DEST"
echo -e "    ➤ Frontend dest: $FRONTEND_DEST"
echo -e "    ➤ Backend dest:  $BACKEND_DEST"

# 🔨 STEP 6: Build Frontend Angular
echo -e "\n🔨 \e[1;33mSTEP 6:\e[0m Build Angular"
cd "$FRONTEND_SRC"
npm install --silent
npm run build -- --configuration production

# 📦 STEP 7: Trova directory di output Angular
echo -e "\n📦 \e[1;33mSTEP 7:\e[0m Trovo dist directory"
if [ -d "dist/frontend" ]; then
  DIST_DIR="dist/frontend"
else
  DIST_DIR=$(find dist -maxdepth 1 -type d ! -name dist | head -n1)
fi
if [ -z "$DIST_DIR" ] || [ ! -d "$DIST_DIR" ]; then
  echo -e "❌ \e[1;31mErrore:\e[0m Output Angular non trovato"
  exit 1
fi
echo -e "    ➤ DIST_DIR: $DIST_DIR"

# 🚀 STEP 8: Copio frontend statico
echo -e "\n🚀 \e[1;33mSTEP 8:\e[0m Copio frontend statico"
cp -r "$DIST_DIR/"* "$FRONTEND_DEST/"

# 📂 STEP 9: Popolo backend Laravel
echo -e "\n📂 \e[1;33mSTEP 9:\e[0m Popolo backend Laravel"
rsync -a --exclude .env --exclude vendor "$BACKEND_SRC/" "$BACKEND_DEST/"

# ⚙️ STEP 10: Imposto file .env
echo -e "\n⚙️  \e[1;33mSTEP 10:\e[0m Configuro file .env"
if [ -f "$BACKEND_SRC/.env.prod" ]; then
  cp "$BACKEND_SRC/.env.prod" "$BACKEND_DEST/.env"
elif [ -f "$BACKEND_SRC/.env.example" ]; then
  cp "$BACKEND_SRC/.env.example" "$BACKEND_DEST/.env"
fi

# 📦 STEP 11: Composer install
echo -e "\n📦 \e[1;33mSTEP 11:\e[0m Composer install"
cd "$BACKEND_DEST"
composer install --no-dev --optimize-autoloader --no-interaction

# 🔑 STEP 12: Generazione APP_KEY
echo -e "\n🔑 \e[1;33mSTEP 12:\e[0m Generazione APP_KEY"
php artisan key:generate --ansi --quiet

# 🔐 STEP 13: Correzione permessi
echo -e "\n🔐 \e[1;33mSTEP 13:\e[0m Correzione permessi storage/bootstrap/cache"
sudo chown -R www:www storage bootstrap/cache
sudo chmod -R 775 storage bootstrap/cache

# ✅ STEP 14: Completamento
echo -e "\n✅ \e[1;32mSTEP 14:\e[0m Deploy ($MODE) pronto in $DEPLOY_ROOT\e[0m"
echo -e "   • Frontend: $FRONTEND_DEST"
echo -e "   • Backend:  $BACKEND_DEST"
