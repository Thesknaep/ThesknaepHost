#!/usr/bin/env bash
# =====================================================================================
#  ThesknaepHost para Linux - instalador
#  Uso:   sudo bash instalar-linux.sh
#  Sin preguntas (avanzado):  sudo THESKNAEPHOST_MODO=local bash instalar-linux.sh
#                             sudo THESKNAEPHOST_MODO=remoto bash instalar-linux.sh
#
#  Instala Pterodactyl (panel + Wings + Docker) y la interfaz web de ThesknaepHost,
#  que se abre en el navegador en http://127.0.0.1:8090 (solo desde este equipo).
# =====================================================================================
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"      # carpeta linux/
RAIZ="$(dirname "$AQUI")"                                   # carpeta ThesknaepHost/
APP=/opt/thesknaephost
CONF_DIR=/etc/thesknaephost
CONF=$CONF_DIR/config
PUERTO_APP=8090

rosa=$'\033[1;95m'; cian=$'\033[1;96m'; verde=$'\033[1;92m'; ambar=$'\033[1;93m'; rojo=$'\033[1;91m'; fin=$'\033[0m'
paso()  { echo -e "\n${cian}==> $*${fin}"; }
ok()    { echo -e "${verde}✔ $*${fin}"; }
aviso() { echo -e "${ambar}⚠ $*${fin}"; }
error() { echo -e "${rojo}✖ $*${fin}" >&2; exit 1; }

echo -e "${rosa}"
cat <<'EOF'
 _____ _               _                         _   _           _
|_   _| |__   ___  ___| | ___ __   __ _  ___ _ __ | | | | ___  ___| |_
  | | | '_ \ / _ \/ __| |/ / '_ \ / _` |/ _ \ '_ \| |_| |/ _ \/ __| __|
  | | | | | |  __/\__ \   <| | | | (_| |  __/ |_) |  _  | (_) \__ \ |_
  |_| |_| |_|\___||___/_|\_\_| |_|\__,_|\___| .__/|_| |_|\___/|___/\__|
                                            |_|      para Linux
EOF
echo -e "${fin}"

# ------------------------------------------------------------------ 1. comprobaciones
[ "$(id -u)" -eq 0 ] || error "Ejecútalo con sudo:  sudo bash $0"
USUARIO="${SUDO_USER:-root}"
HOME_USUARIO="$(getent passwd "$USUARIO" | cut -d: -f6)"
[ -n "$HOME_USUARIO" ] || HOME_USUARIO=/root

grep -qi microsoft /proc/version 2>/dev/null && error "Esto es WSL (Windows). En Windows usa ThesknaepHost.bat, no este instalador."
[ "$(ps -p 1 -o comm=)" = "systemd" ] || error "Este equipo no usa systemd. ThesknaepHost necesita systemd (Ubuntu, Mint, Pop!_OS…)."
[ "$(uname -m)" = "x86_64" ] || error "Se necesita un procesador Intel o AMD de 64 bits (x86_64). Este es $(uname -m)."
# shellcheck disable=SC1091
. /etc/os-release
CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
if [ "$CODENAME" != "noble" ]; then
    error "Se necesita Ubuntu 24.04 o una distro basada en él (Linux Mint 22, Pop!_OS 24.04, Zorin OS 18…).
   Este equipo tiene: ${PRETTY_NAME:-desconocido}. (Pterodactyl necesita PHP 8.3, que viene en Ubuntu 24.04.)"
fi
ok "Sistema compatible: ${PRETTY_NAME}"
LIBRE_GB=$(( $(df -m --output=avail / | tail -1) / 1024 ))
[ "$LIBRE_GB" -ge 12 ] || aviso "Tienes $LIBRE_GB GB libres. Se recomiendan al menos 12 GB (más lo que ocupen tus servidores)."
command -v curl >/dev/null || { apt-get update -y && apt-get install -y curl; }

# ------------------------------------------------------------------ 2. modo de uso (LOCAL o REMOTO)
MODO="${THESKNAEPHOST_MODO:-}"
if [ -z "$MODO" ] && [ -f "$CONF" ]; then MODO="$(sed -n 's/^MODO=//p' "$CONF")"; fi
if [ -z "$MODO" ]; then
    echo -e "${rosa}¿Cómo vas a usar ThesknaepHost?${fin}"
    echo -e "  ${verde}1) LOCAL${fin}   Solo personas en tu misma red (mismo WiFi o cable)."
    echo -e "  ${cian}2) REMOTO${fin}  Tú y tus amigos desde cualquier lugar (datos móviles, otras casas)."
    echo -e "            ${ambar}Requiere Tailscale${fin} (gratis): una red privada entre tus equipos y los de tus amigos."
    echo -e "            Funciona aunque tu internet tenga CGNAT. Sin Tailscale el modo REMOTO no funciona."
    while :; do
        read -rp "Elige 1 o 2: " r </dev/tty
        case "$r" in 1) MODO=local; break ;; 2) MODO=remoto; break ;; *) echo "Escribe 1 o 2." ;; esac
    done
fi
[ "$MODO" = "local" ] || [ "$MODO" = "remoto" ] || error "Modo inválido: $MODO (usa local o remoto)"
ok "Modo elegido: ${MODO^^}"

# ------------------------------------------------------------------ 3. Tailscale (obligatorio en modo REMOTO)
IP_TS=""
if [ "$MODO" = "remoto" ]; then
    paso "Tailscale (obligatorio para el modo REMOTO)"
    if ! command -v tailscale >/dev/null; then
        echo "Se instalará Tailscale con su instalador oficial (tailscale.com/install.sh)."
        echo "Al instalarlo aceptas sus términos de uso: https://tailscale.com/terms"
        curl -fsSL https://tailscale.com/install.sh | sh
    fi
    systemctl enable --now tailscaled
    estado_ts() { tailscale status --json 2>/dev/null | sed -n 's/.*"BackendState": *"\([A-Za-z]*\)".*/\1/p' | head -1; }
    intentos=0
    while [ "$(estado_ts)" != "Running" ]; do
        intentos=$((intentos + 1))
        echo -e "${ambar}Inicia sesión en Tailscale:${fin} abre el enlace que aparece abajo en tu navegador (cuenta Google, Microsoft, Apple o GitHub)."
        # --operator: tu usuario puede manejar Tailscale sin sudo
        tailscale up --operator="$USUARIO" --timeout=10m || true
        if [ "$(estado_ts)" != "Running" ]; then
            [ "$intentos" -ge 3 ] && error "Tailscale no se conectó. Sin Tailscale el modo REMOTO no funciona.
   Vuelve a ejecutar el instalador, o usa el modo LOCAL:  sudo THESKNAEPHOST_MODO=local bash $0"
            aviso "Tailscale todavía no está conectado. Intento $intentos de 3."
        fi
    done
    IP_TS="$(tailscale ip -4 2>/dev/null | head -1)"
    ok "Tailscale conectado. IP de este equipo: $IP_TS"
fi

mkdir -p "$CONF_DIR"
printf 'MODO=%s\nUSUARIO=%s\n' "$MODO" "$USUARIO" > "$CONF"

# ------------------------------------------------------------------ 4. Pterodactyl (panel + Wings + Docker)
paso "Instalando Pterodactyl, Wings y Docker (10-20 minutos la primera vez)"
DATOS="$HOME_USUARIO/ThesknaepHost"
mkdir -p "$DATOS"
tr -d '\r' < "$AQUI/instalar-pterodactyl.sh" > /tmp/thesknaephost-pterodactyl.sh
bash /tmp/thesknaephost-pterodactyl.sh "$DATOS"
chown -R "$USUARIO": "$DATOS"; chmod 700 "$DATOS"; chmod 600 "$DATOS/credenciales.txt" 2>/dev/null || true

# ------------------------------------------------------------------ 5. Interfaz web de ThesknaepHost (127.0.0.1:8090)
paso "Instalando la interfaz de ThesknaepHost"
install -d "$APP"
rm -rf "$APP/web"; cp -r "$RAIZ/web" "$APP/web"
tr -d '\r' < "$AQUI/recursos.php" > "$APP/recursos.php"
chown -R root:www-data "$APP"; chmod -R a+rX "$APP"
# la interfaz puede cambiar el modo (LOCAL/REMOTO) desde el navegador
chown root:www-data "$CONF"; chmod 664 "$CONF"; chmod 755 "$CONF_DIR"
cat > /etc/nginx/sites-available/thesknaephost.conf <<EOF
# ThesknaepHost: solo desde este equipo (127.0.0.1)
server {
    listen 127.0.0.1:${PUERTO_APP};
    root ${APP}/web;
    index index.html;
    location / { try_files \$uri \$uri/ =404; }
    location ~ \.php\$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_read_timeout 300;
    }
}
EOF
ln -sf /etc/nginx/sites-available/thesknaephost.conf /etc/nginx/sites-enabled/thesknaephost.conf
nginx -t && systemctl reload nginx
ok "Interfaz lista en http://127.0.0.1:${PUERTO_APP}"

# ------------------------------------------------------------------ 6. Firewall (solo puertos de juego)
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active\|Estado: activo"; then
    paso "Abriendo los puertos de juego en el firewall (ufw)"
    ufw allow 7777:7780/tcp comment 'ThesknaepHost Terraria' >/dev/null
    ufw allow 7777:7780/udp comment 'ThesknaepHost Terraria' >/dev/null
    ufw allow 25565:25566/tcp comment 'ThesknaepHost Minecraft' >/dev/null
    ufw allow 25565:25566/udp comment 'ThesknaepHost Minecraft' >/dev/null
    ok "Puertos 7777-7780 y 25565-25566 abiertos"
fi

# ------------------------------------------------------------------ 7. Acceso en el menu de aplicaciones + comando
cat > /usr/local/bin/thesknaephost <<EOF
#!/bin/sh
# Abre ThesknaepHost en el navegador
exec xdg-open "http://127.0.0.1:${PUERTO_APP}" >/dev/null 2>&1
EOF
chmod 755 /usr/local/bin/thesknaephost
cat > /usr/share/applications/thesknaephost.desktop <<EOF
[Desktop Entry]
Type=Application
Name=ThesknaepHost
Comment=Servidores de Terraria y Minecraft con Pterodactyl
Exec=/usr/local/bin/thesknaephost
Icon=${APP}/web/icono.png
Terminal=false
Categories=Game;Network;
EOF
if [ -d "$HOME_USUARIO/Escritorio" ] || [ -d "$HOME_USUARIO/Desktop" ]; then
    ESC="$HOME_USUARIO/Escritorio"; [ -d "$ESC" ] || ESC="$HOME_USUARIO/Desktop"
    install -o "$USUARIO" -m 755 /usr/share/applications/thesknaephost.desktop "$ESC/thesknaephost.desktop"
    sudo -u "$USUARIO" gio set "$ESC/thesknaephost.desktop" metadata::trusted true 2>/dev/null || true
fi

# ------------------------------------------------------------------ listo
IP_LAN="$(hostname -I | tr ' ' '\n' | grep -E '^(192\.168|10\.|172\.(1[6-9]|2[0-9]|3[01]))\.' | grep -v '^172\.1[78]\.' | head -1)"
echo
echo -e "${rosa}=====================================================================${fin}"
echo -e "${verde}  ThesknaepHost está instalado.${fin}"
echo -e "  Abrir:            menú de aplicaciones → ${rosa}ThesknaepHost${fin}  (o el comando: thesknaephost)"
echo -e "  Interfaz:         http://127.0.0.1:${PUERTO_APP}"
echo -e "  Panel avanzado:   http://127.0.0.1:8088   (usuario y clave en $DATOS/credenciales.txt)"
echo -e "  Modo:             ${MODO^^}"
echo -e "  Tus amigos entran a:  ${cian}${IP_TS:-${IP_LAN:-tu-ip}}:PUERTO${fin}  (7777 Terraria, 25565 Minecraft)"
[ "$MODO" = "remoto" ] && echo -e "  Invita amigos en:  https://login.tailscale.com/admin/machines  → este equipo → Share…"
echo -e "${rosa}=====================================================================${fin}"
sudo -u "$USUARIO" xdg-open "http://127.0.0.1:${PUERTO_APP}" >/dev/null 2>&1 || true
