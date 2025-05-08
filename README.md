# Wyrmrest Portfolio

## 📖 Panoramica

`wyrmrest.com` è il progetto principale che ospita tutti i tuoi sotto-progetti client. Quando un utente visita:

- `www.wyrmrest.com` → viene caricata la Single Page App principale in Angular.
- `www.wyrmrest.com/{project_slug}` → Angular richiama via API Laravel i dati del sottoprogetto corrispondente.

Ogni progetto (padre e figli) ha struttura simile e script di deploy dedicati per build e sincronizzazione.

---

## 🗂️ Struttura delle cartelle

```text
portfolio/
├── wyrmrest.com/                  # Progetto principale (contenitore)
│   ├── backend/                   # Codice Laravel (API, logica, DB)
│   ├── frontend/                  # Codice Angular (SPA)
│   └── deploy_wyrmrest.sh         # Script di deploy principale
├── project_example/               # Progetto figlio di esempio
│   ├── backend/                   # Codice backend di test
│   ├── frontend/                  # Codice frontend di test
│   └── deploy_project_example.sh  # Script di deploy del figlio
├── deploy_wyrmrest.sh             # Wrapper che esegue i deploy figli
└── README.md                      # Documentazione e guida
```

```text
/www/wwwroot/
├── default/                    # Cartella default (non in uso)
├── dev/                        # Ambiente di sviluppo (accesso solo via SSH)
│   ├── wyrmrest/           # Progetto principale in dev
│   │   ├── backend/            # Codice Laravel (API, logica, DB)
│   │   └── frontend/           # Codice Angular (SPA)
│   └── project_example/        # Progetto figlio di esempio in dev
│       ├── backend/            # Codice backend di test
│       └── frontend/           # Codice frontend di test
└── prod/                       # Ambiente di produzione (accesso libero)
  ├── wyrmrest.com/           # Progetto principale in prod
  │   ├── backend/            # Codice Laravel (API, logica, DB)
  │   └── frontend/           # Codice Angular (SPA)
  ├── project_example/        # Progetto figlio di esempio in prod
  │   ├── backend/            # Codice backend di test
  │   └── frontend/           # Codice frontend di test
  └── README.md               # Documentazione e guida
```

---

## 🚀 Strategia di deploy generale

1. **Workspace separato**: clona e builda in `~/deploy/{backend,frontend}`, isolando la produzione.
2. **Build locale**: Angular (`ng build --prod`) e Laravel (`composer install --optimize-autoloader`, cache) vengono eseguiti prima della copia.
3. **Sincronizzazione atomica**: usa `rsync` per trasferire solo i file modificati e mantenere un downtime minimo.
4. **Script modulare**: un wrapper chiama automaticamente gli script dedicati di ogni sottoprogetto.

---

## 📄 Script di deploy principale (`deploy_wyrmrest.sh`)

Lo script orchestri:

- Pull o clone di ogni repository figlio
- Esecuzione del deploy di ciascuno
- Ricarica dei servizi

```bash
#!/usr/bin/env bash
set -euo pipefail

# Lista delle directory dei progetti figli
CHILDREN=("wyrmrest.com" "project_example")

for child in "${CHILDREN[@]}"; do
  echo "=== Deploy $child ==="
  "$(dirname "$0")/$child/deploy_${child}.sh"
done

echo "✅ Deploy completo di tutti i progetti"
```

---

## 🛠️ Script di deploy per progetto padre (`wyrmrest.com/deploy_wyrmrest.sh`)

```bash
#!/usr/bin/env bash
set -euo pipefail

# Configurazione
WORKDIR="$HOME/deploy/wyrmrest"
PROD_ROOT="/www/wwwroot/wyrmrest"
BRANCH="main"
PHP_FPM_SERVICE="php8.1-fpm"

# 1. Clone/Pull
mkdir -p "$WORKDIR/backend" "$WORKDIR/frontend"
cd "$WORKDIR/backend"
if [ -d .git ]; then git pull; else git clone -b "$BRANCH" git@github.com:tuo-user/wyrmrest-backend.git .; fi

cd "$WORKDIR/frontend"
if [ -d .git ]; then git pull; else git clone -b "$BRANCH" git@github.com:tuo-user/wyrmrest-frontend.git .; fi

# 2. Build Angular
cd "$WORKDIR/frontend"
npm ci
ng build --configuration=production
rm -rf "$PROD_ROOT/backend/public/app"
cp -r dist/frontend/* "$PROD_ROOT/backend/public/app"

# 3. Prepara Laravel
cd "$WORKDIR/backend"
composer install --no-dev --optimize-autoloader
cp .env.example .env 2>/dev/null || true
php artisan key:generate --force
php artisan config:cache
php artisan route:cache
php artisan view:cache

# 4. Rsync su produzione
rsync -av --delete --exclude='.git' --exclude='node_modules' --exclude='dist' \
  "$WORKDIR/backend/" "$PROD_ROOT/backend/"

# 5. Migrazioni e permessi
cd "$PROD_ROOT/backend"
php artisan migrate --force
chown -R www-data:www-data storage bootstrap/cache

# 6. Reload servizi
sudo systemctl reload "$PHP_FPM_SERVICE"
sudo systemctl reload nginx

echo "✅ Deploy Wyrmrest completato"
```

---

## 🗒️ Template script di deploy per sottoprogetti (es. `project_example/deploy_project_example.sh`)

```bash
#!/usr/bin/env bash
set -euo pipefail

# Configurazione generica
WORKDIR="$HOME/deploy/{project_slug}"
PROD_ROOT="/www/wwwroot/wyrmrest/backend/children/{project_slug}"
BRANCH="main"

# 1. Clone/Pull repository
mkdir -p "$WORKDIR"
cd "$WORKDIR"
if [ -d .git ]; then git pull; else git clone -b "$BRANCH" git@github.com:tuo-user/{project_slug}-backend.git .; fi

# 2. Build frontend (se presente)
if [ -d "$WORKDIR/frontend" ]; then
  cd "$WORKDIR/frontend"
  npm ci
  npm run build -- --prod
  rm -rf "$PROD_ROOT/public/{project_slug}"
  cp -r dist/* "$PROD_ROOT/public/{project_slug}"
fi

# 3. Composer e cache
cd "$WORKDIR"
composer install --no-dev --optimize-autoloader
php artisan config:cache
php artisan route:cache

# 4. Rsync in produzione
rsync -av --delete --exclude='.git' --exclude='node_modules' \
  "$WORKDIR/" "$PROD_ROOT/"

# 5. Migrazioni e permessi
cd "$PROD_ROOT"
php artisan migrate --force
chown -R www-data:www-data storage bootstrap/cache

# 6. Reload servizi
sudo systemctl reload php8.1-fpm
sudo systemctl reload nginx

echo "✅ Deploy {project_slug} completato"
```

---

## 💡 Suggerimenti

- **Customizzazione**: sostituisci `{project_slug}` e URL dei repository.
- **CI/CD**: integra con GitHub Actions per eseguire automaticamente questi script.
- **Zero Downtime**: esegui su cartelle temporanee e swap manuale.
- **Rollback**: mantieni backup DB e tag nel repo.

Con questo setup hai uno scheletro riutilizzabile per tutti i progetti nel tuo portfolio.
