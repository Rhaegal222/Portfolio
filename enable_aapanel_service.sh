#!/bin/bash

# enable_aapanel_service.sh
# Crea e abilita un servizio systemd per avviare aaPanel (bt) al boot
# Se il servizio esiste, è abilitato e aaPanel è attivo, non fa nulla.

set -euo pipefail
trap 'echo "❌ Errore alla riga $LINENO. Comando: $BASH_COMMAND" >&2' ERR

SERVICE_FILE="/etc/systemd/system/aapanel.service"
BT_PATH="/usr/bin/bt"
INIT_SCRIPT="/etc/init.d/bt"
SERVICE_NAME="aapanel"

echo "🔍 Controllo stato attuale..."

if systemctl is-enabled --quiet "$SERVICE_NAME" && systemctl is-active --quiet "$SERVICE_NAME"; then
  PANEL_RUNNING=$("$BT_PATH" status | grep -c "Bt-Panel (pid")
  TASK_RUNNING=$("$BT_PATH" status | grep -c "Bt-Task (pid")
  if [[ "$PANEL_RUNNING" -gt 0 && "$TASK_RUNNING" -gt 0 ]]; then
    echo "✅ aaPanel è già attivo e configurato per l'avvio automatico. Nessuna azione necessaria."
    exit 0
  fi
fi

echo "🔧 Procedo con la configurazione..."

if [[ ! -x "$BT_PATH" ]]; then
  echo "❌ Il comando 'bt' non è stato trovato in $BT_PATH o non è eseguibile."
  echo "➡️  Assicurati che aaPanel sia installato correttamente prima di procedere."
  exit 1
fi

if [[ ! -x "$INIT_SCRIPT" ]]; then
  echo "❌ Lo script init.d di bt non esiste in $INIT_SCRIPT."
  echo "➡️  Potresti dover reinstallare aaPanel per ripristinarlo."
  exit 1
fi

echo "🛠️  Creazione del servizio $SERVICE_NAME..."

sudo tee "$SERVICE_FILE" > /dev/null <<'EOF'
[Unit]
Description=aaPanel via init script
After=network-online.target mysql.service
Wants=network-online.target

[Service]
Type=forking
ExecStart=/bin/bash -lc "/usr/bin/bt restart"
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

echo "🔄 Ricarico configurazione systemd..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload

echo "✅ Abilito il servizio per l'avvio automatico..."
sudo systemctl enable "$SERVICE_NAME"

echo "🚀 Avvio del servizio $SERVICE_NAME..."
sudo systemctl restart "$SERVICE_NAME"

echo "⏳ Attendo 3 secondi per stabilizzare i processi..."
sleep 3

echo "📋 Verifica dello stato del servizio:"
sudo systemctl status "$SERVICE_NAME" --no-pager

echo "✅ Verifica dello stato di aaPanel:"
PANEL_RUNNING=$(sudo "$BT_PATH" status | grep -c "Bt-Panel (pid")
TASK_RUNNING=$(sudo "$BT_PATH" status | grep -c "Bt-Task (pid")

if [[ "$PANEL_RUNNING" -gt 0 && "$TASK_RUNNING" -gt 0 ]]; then
  echo "🎉 aaPanel è attivo e configurato per l'avvio automatico!"
else
  echo "⚠️  Il servizio è stato creato, ma aaPanel non risulta attivo."
  echo "🔧 Usa 'bt start' per avviarlo manualmente e controlla i log."
fi

