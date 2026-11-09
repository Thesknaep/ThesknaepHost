# ThesknaepHost para Linux

Host de servidores de **Terraria** y **Minecraft** con Pterodactyl, para tu propio PC con Linux.
Se maneja desde una interfaz web con el mismo estilo neón que la app de Windows.

## Requisitos

- **Ubuntu 24.04** o una distro basada en él: Linux Mint 22, Pop!_OS 24.04, Zorin OS 18, Kubuntu/Xubuntu 24.04.
  (Pterodactyl necesita PHP 8.3, que viene en Ubuntu 24.04.)
- Procesador **Intel o AMD de 64 bits** (no ARM / Raspberry Pi).
- Al menos **12 GB libres** más lo que ocupen tus servidores.
- Internet durante la instalación.

## Instalar

1. Descomprime `ThesknaepHost-linux.tar.gz` (clic derecho → *Extraer aquí*).
2. Abre una terminal en la carpeta `ThesknaepHost` y ejecuta:

   ```bash
   sudo bash linux/instalar-linux.sh
   ```

3. Te pregunta **cómo la vas a usar**:
   - **1) LOCAL**: solo personas en tu misma red (mismo WiFi o cable).
   - **2) REMOTO**: tú y tus amigos desde cualquier lugar (datos móviles, otras casas).
     **Requiere Tailscale** (gratis). El instalador lo instala y te pide **iniciar sesión** con el enlace que
     aparece. **No continúa en modo REMOTO hasta que Tailscale esté conectado** (3 intentos; si no, usa LOCAL).
4. Espera 10–20 minutos (instala Docker, Pterodactyl y Wings).
5. Se abre ThesknaepHost en tu navegador. Desde ahora lo abres desde el **menú de aplicaciones → ThesknaepHost**
   o con el comando `thesknaephost`.

Usuario y contraseña del panel avanzado: `~/ThesknaepHost/credenciales.txt`.

## Usarla

La interfaz está en **http://127.0.0.1:8090** (solo desde este PC):

- **SISTEMA**: estado del panel, Wings y Docker; tu IP local y la de Tailscale.
- **ACCESO REMOTO**: estado de Tailscale y dispositivos conectados.
- **MIS SERVIDORES**: prender, apagar, reiniciar, cambiar RAM/almacenamiento, abrir la consola y
  **COPIAR IP** (en modo REMOTO copia la dirección de Tailscale, en LOCAL la de tu red).
- **+ CREAR SERVIDOR**: Terraria (Vanilla, TShock, tModLoader) o Minecraft (Vanilla, Paper, Forge), con versión,
  mundo, semilla (botón AL AZAR), tamaño, dificultad, maldad / modo de juego, jugadores, RAM y almacenamiento.
- **CAMBIAR MODO** (arriba): pasar de LOCAL a REMOTO o al revés. En REMOTO, si Tailscale no está conectado,
  aparece un aviso rojo con los comandos para arreglarlo.

Los servidores **empiezan apagados** cada vez que se enciende el PC: los prendes tú.
Para subir mundos, plugins o mods usa **CONSOLA** → pestaña *Files* del panel (permite subir archivos).

## Tus amigos (modo REMOTO)

1. En https://login.tailscale.com/admin/machines → este PC → **⋯ → Share…** → mándales el enlace.
2. Ellos instalan Tailscale (Google Play, App Store o tailscale.com/download) y aceptan la invitación.
3. Entran al juego con la dirección que les copiaste (por ejemplo `100.x.x.x:7777`).

## Firewall

Si usas `ufw`, el instalador abre solo los puertos de juego: 7777–7780 (Terraria) y 25565–25566 (Minecraft).
La interfaz (8090), el panel (8088), Wings (8080) y SFTP (2022) **solo escuchan dentro de este PC**
(127.0.0.1): nadie de tu red ni de internet puede llegar a ellos, aunque no tengas firewall.
La interfaz además rechaza órdenes que vengan de otras páginas web abiertas en tu navegador.
