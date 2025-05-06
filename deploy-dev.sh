#!/bin/bash

# deploy-dev.sh
# 1. Cancella e ricrea la struttura deploy
# 2. Builda frontend/backend
# 3. Crea i virtual host NGINX (simulati)
# 4. Li sincronizza nel server reale

set -euo pipefail

PROJECT="wyrmrest.com"

echo "🧹 Rimuovo struttura deploy esistente..."
sudo rm -rf ./deploy/www

echo "📁 Ricreo struttura iniziale NGINX..."
sudo ./sima-init-structure.sh "$PROJECT"

echo "🔨 Build e deploy di codice in ambiente DEV..."
sudo ./simb-build-deploy.sh -dev "$PROJECT"

echo "⚙️  Genero configurazione NGINX simulata..."
sudo ./simc-nginx-deploy.sh -dev

echo "🚀 Applico la simulazione come configurazione reale..."
sudo ./sim-to-live.sh -dev

echo "✅ Deploy completo per '$PROJECT' in ambiente DEV"
