#!/usr/bin/env bash
# ThesknaepHost - instala Pterodactyl Panel + Wings dentro de WSL2 (Ubuntu 24.04)
# Lo ejecuta Instalar.ps1 desde Windows. Se puede volver a ejecutar sin romper nada.
#   Uso: bash instalar-pterodactyl.sh <carpeta-de-salida-para-credenciales>
set -euo pipefail

OUT_DIR="${1:-/root}"
PANEL_PORT=8088
# 127.0.0.1 y no "localhost": Windows prueba primero IPv6 (::1) y WSL no lo reenvia, la conexion se cuelga
PANEL_URL="http://127.0.0.1:${PANEL_PORT}"
WINGS_PORT=8080
SFTP_PORT=2022
DIR=/var/www/pterodactyl
STATE=/root/.thesknaephost
export DEBIAN_FRONTEND=noninteractive
export COMPOSER_ALLOW_SUPERUSER=1

log()  { echo -e "\n\033[1;36m==> $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }
randpw() { head -c 96 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c "${1:-20}"; }
sql()  { mysql -N -u root panel -e "$1"; }

# --- Fase 0: Pterodactyl necesita systemd. Si no esta activo, lo activamos y pedimos reinicio (codigo 42).
if [ "$(ps -p 1 -o comm=)" != "systemd" ]; then
  log "Activando systemd en WSL (se reiniciara la maquina Linux)"
  cat > /etc/wsl.conf <<'EOF'
[boot]
systemd=true

[user]
default=root
EOF
  exit 42
fi

mkdir -p "$STATE" && chmod 700 "$STATE"
if [ -f "$STATE/secrets" ]; then
  # shellcheck disable=SC1091
  source "$STATE/secrets"
else
  DB_PASS="$(randpw 24)"
  ADMIN_PASS="$(randpw 16)"
  printf 'DB_PASS=%q\nADMIN_PASS=%q\n' "$DB_PASS" "$ADMIN_PASS" > "$STATE/secrets"
  chmod 600 "$STATE/secrets"
fi

# --- Paquetes
log "Instalando paquetes (PHP 8.3, MariaDB, Redis, Nginx)"
# Si archive.ubuntu.com no responde desde tu red, se usa otro espejo oficial que si responda
responde() { timeout 8 bash -c "exec 3<>/dev/tcp/$1/80" 2>/dev/null; }
FUENTES=/etc/apt/sources.list.d/ubuntu.sources; [ -f "$FUENTES" ] || FUENTES=/etc/apt/sources.list
ACTUAL="$(grep -E '^[[:space:]]*(URIs:|deb )' "$FUENTES" | grep -oE 'https?://[^/ ]+' | grep -v security | head -1 | sed -E 's#https?://##')"
if [ -n "$ACTUAL" ] && ! responde "$ACTUAL"; then
  for h in archive.ubuntu.com us.archive.ubuntu.com cl.archive.ubuntu.com br.archive.ubuntu.com mirrors.edge.kernel.org; do
    if responde "$h"; then
      log "$ACTUAL no responde; usando el espejo $h"
      sed -i "s#://$ACTUAL/#://$h/#g" "$FUENTES"; break
    fi
  done
fi
apt-get update -y
apt-get install -y curl ca-certificates gnupg tar unzip git cron jq \
  php8.3-cli php8.3-fpm php8.3-common php8.3-gd php8.3-mysql php8.3-mbstring \
  php8.3-bcmath php8.3-xml php8.3-curl php8.3-zip php8.3-intl \
  mariadb-server nginx redis-server
systemctl enable --now mariadb redis-server php8.3-fpm nginx cron

if ! command -v composer >/dev/null; then
  log "Instalando Composer"
  curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
fi

# --- Base de datos
log "Configurando base de datos"
mysql -u root <<EOF
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
ALTER USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
CREATE DATABASE IF NOT EXISTS panel;
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

# --- Panel
if [ ! -f "$STATE/panel_ok" ]; then
  log "Descargando Pterodactyl Panel"
  mkdir -p "$DIR" && cd "$DIR"
  curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
  tar -xzf panel.tar.gz && rm panel.tar.gz
  chmod -R 755 storage/* bootstrap/cache/
  [ -f .env ] || cp .env.example .env

  log "Instalando dependencias del panel (tarda unos minutos)"
  # Con internet lento la descarga puede cortarse: mas tiempo de espera y hasta 3 intentos
  export COMPOSER_PROCESS_TIMEOUT=1800 COMPOSER_MAX_PARALLEL_HTTP=4
  for intento in 1 2 3; do
    composer install --no-dev --optimize-autoloader --no-interaction && break
    [ "$intento" = 3 ] && { echo "composer install falló 3 veces (revisa tu internet)"; exit 1; }
    log "La descarga se cortó; reintentando ($((intento + 1))/3)"; sleep 10
  done
  grep -q '^APP_KEY=base64' .env || php artisan key:generate --force

  php artisan p:environment:setup -n \
    --author="admin@thesknaephost.local" --url="$PANEL_URL" --timezone="UTC" \
    --cache=redis --session=redis --queue=redis \
    --redis-host=127.0.0.1 --redis-pass="" --redis-port=6379 \
    --settings-ui=true --telemetry=false
  php artisan p:environment:database -n \
    --host=127.0.0.1 --port=3306 --database=panel --username=pterodactyl --password="$DB_PASS"
  # Sin servidor de correo: los emails del panel van al log en vez de fallar contra smtp.example.com
  if grep -q '^MAIL_MAILER=' .env; then sed -i 's/^MAIL_MAILER=.*/MAIL_MAILER=log/' .env; else echo 'MAIL_MAILER=log' >> .env; fi

  log "Creando tablas"
  php artisan migrate --seed --force

  log "Creando usuario administrador"
  php artisan p:user:make -n --email="admin@thesknaephost.local" --username=admin \
    --name-first=Admin --name-last=ThesknaepHost --password="$ADMIN_PASS" --admin=1 \
    || warn "El usuario admin ya existia, se mantiene."

  chown -R www-data:www-data "$DIR"
  touch "$STATE/panel_ok"
fi

# Cron + cola de trabajos
{ crontab -l 2>/dev/null | grep -v 'pterodactyl/artisan' || true; \
  echo "* * * * * php $DIR/artisan schedule:run >> /dev/null 2>&1"; } | crontab -

cat > /etc/systemd/system/pteroq.service <<EOF
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php $DIR/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# Seguridad: en Linux normal el panel, Wings y SFTP solo escuchan dentro de este PC (127.0.0.1).
# En WSL (Windows) se dejan abiertos dentro de la maquina virtual porque Windows llega por ahi,
# pero el firewall Hyper-V de Windows ya los bloquea desde afuera (solo pasan los puertos de juego).
if grep -qi microsoft /proc/version 2>/dev/null; then
  ESCUCHA4="${PANEL_PORT}"; ESCUCHA6="[::]:${PANEL_PORT}"; SOLO_LOCAL=0
else
  ESCUCHA4="127.0.0.1:${PANEL_PORT}"; ESCUCHA6="[::1]:${PANEL_PORT}"; SOLO_LOCAL=1
fi

# Nginx (HTTP local, puerto 8088)
log "Configurando Nginx en el puerto $PANEL_PORT"
rm -f /etc/nginx/sites-enabled/default
cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen ${ESCUCHA4};
    listen ${ESCUCHA6};
    server_name _;
    root ${DIR}/public;
    index index.php;
    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    location / { try_files \$uri \$uri/ /index.php?\$query_string; }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }
    location ~ /\.ht { deny all; }
}
EOF
ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
nginx -t
systemctl daemon-reload
systemctl enable --now pteroq
systemctl restart nginx

# --- Docker
if ! command -v docker >/dev/null; then
  log "Instalando Docker (ignora el aviso de WSL, es normal)"
  curl -sSL https://get.docker.com/ | CHANNEL=stable bash
fi
systemctl enable --now docker

# --- Wings
if [ ! -x /usr/local/bin/wings ]; then
  log "Instalando Wings"
  mkdir -p /etc/pterodactyl
  curl -L -o /usr/local/bin/wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
  chmod u+x /usr/local/bin/wings
fi

cd "$DIR"

# --- Ubicacion, nodo y puertos
LOC_ID="$(sql "SELECT id FROM locations WHERE short='local' LIMIT 1")"
if [ -z "$LOC_ID" ]; then
  php artisan p:location:make -n --short=local --long="Mi PC"
  LOC_ID="$(sql "SELECT id FROM locations WHERE short='local' LIMIT 1")"
fi

NODE_ID="$(sql "SELECT id FROM nodes WHERE name='Mi PC' LIMIT 1")"
if [ -z "$NODE_ID" ]; then
  log "Creando nodo local"
  MEM=$(( $(free -m | awk '/^Mem:/{print $2}') - 1024 )); [ "$MEM" -lt 1024 ] && MEM=1024
  DISK=$(( $(df -m --output=avail / | tail -1) - 5120 )); [ "$DISK" -lt 10240 ] && DISK=10240
  php artisan p:node:make -n --name="Mi PC" --description="Nodo local en WSL" \
    --locationId="$LOC_ID" --fqdn=127.0.0.1 --public=1 --scheme=http --proxy=0 \
    --maintenance=0 --maxMemory="$MEM" --overallocateMemory=0 --maxDisk="$DISK" \
    --overallocateDisk=0 --uploadSize=100 --daemonListeningPort=$WINGS_PORT \
    --daemonSFTPPort=$SFTP_PORT --daemonBase=/var/lib/pterodactyl/volumes
  NODE_ID="$(sql "SELECT id FROM nodes WHERE name='Mi PC' LIMIT 1")"
fi

log "Registrando puertos (Terraria 7777-7780, Minecraft 25565-25566)"
for p in 7777 7778 7779 7780 25565 25566; do
  sql "INSERT IGNORE INTO allocations (node_id, ip, port, created_at, updated_at) VALUES ($NODE_ID, '0.0.0.0', $p, NOW(), NOW())"
done

log "Configurando y arrancando Wings"
php artisan p:node:configuration "$NODE_ID" --format=yaml > /etc/pterodactyl/config.yml
if [ "$SOLO_LOCAL" = 1 ]; then
  # API de Wings (8080) y SFTP (2022) solo dentro de este PC
  sed -i -E '/^api:/,/^[a-z]/ s/^(  host: ).*/\1127.0.0.1/' /etc/pterodactyl/config.yml
  sed -i -E '/^  sftp:/,/^  [a-z_]+:$/ s/^(    bind_address: ).*/\1127.0.0.1/' /etc/pterodactyl/config.yml
fi
chmod 600 /etc/pterodactyl/config.yml
cat > /etc/systemd/system/wings.service <<'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
# Al arrancar Linux los servidores quedan APAGADOS: Wings guarda en states.json cuales estaban
# encendidos y los vuelve a prender; lo borramos antes de iniciar Wings.
mkdir -p /etc/systemd/system/wings.service.d
cat > /etc/systemd/system/wings.service.d/thesknaephost.conf <<'EOF'
[Service]
ExecStartPre=/bin/rm -f /var/lib/pterodactyl/states.json
EOF
systemctl daemon-reload
systemctl enable wings
systemctl restart wings

for i in $(seq 1 30); do
  code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$WINGS_PORT/api/system || true)"
  [ "$code" != "000" ] && break
  sleep 2
done
[ "$code" = "000" ] && warn "Wings no responde todavia. Revisa: journalctl -u wings -n 50"

# Los comandos de arriba corrieron como root: devolvemos los archivos al usuario del panel
chown -R www-data:www-data "$DIR"
log "Crea tu primer servidor (Vanilla, TShock o tModLoader) desde la app ThesknaepHost"

# --- Credenciales
mkdir -p "$OUT_DIR"
cat > "$OUT_DIR/credenciales.txt" <<EOF
ThesknaepHost - acceso al panel
===========================
Panel:      $PANEL_URL
Usuario:    admin
Contrasena: $ADMIN_PASS

Cambia la contrasena desde el panel (icono de usuario > Account).
EOF

log "Instalacion terminada. Panel: $PANEL_URL"
