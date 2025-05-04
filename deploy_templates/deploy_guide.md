# Guida al Deploy

1. **`PANEL_URL`**
   – URL di aaPanel (es. `https://123.45.67.89:8888` o dominio)

2. **`PANEL_USER`** e **`PANEL_PASS`**
   – Credenziali di login all’interfaccia aaPanel

3. **`DOMAIN`**
   – Il tuo dominio principale (es. `wyrmrest.com`)

4. **`ROOT_DIR`**
   – Cartella in produzione dove risiede il `public` di Laravel
   (es. `/www/wwwroot/wyrmrest/backend/public`)

5. **`PHP_VERSION`**
   – Versione PHP configurata in aaPanel (es. `php-81`, `php-82`)

6. **`FRONT_SRC`** e **`BACK_SRC`**
   – Percorsi locali al codice sorgente di Angular e Laravel
   (es. `~/portfolio/wyrmrest.com/frontend` e `~/portfolio/wyrmrest.com/backend`)

7. **`PROD_FE`** e **`PROD_BE`**
   – Cartelle di destinazione per i file buildati e per il backend
   (es. `/www/wwwroot/wyrmrest/frontend` e `/www/wwwroot/wyrmrest/backend`)

8. **`PHP_FPM_SERVICE`**
   – Nome del servizio PHP-FPM da ricaricare (es. `php8.1-fpm`)

9. **aaPanel → Websites → Edit**
   – Verifica che il sito `wyrmrest.com` esista e punti a `ROOT_DIR`
   – Controlla che SSL (Let’s Encrypt) e PHP-FPM siano abilitati

10. **DNS / A record**
    – Assicurati che `wyrmrest.com` punti all’IP del server

Una volta aggiornati questi valori nello script, rendilo eseguibile e lancialo per eseguire il deploy.
