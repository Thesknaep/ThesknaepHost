# ThesknaepHost

**Tu propio host de juegos en casa.** ThesknaepHost convierte tu PC, tu servidor o tu máquina virtual
en un servidor local para alojar partidas de **Terraria** y **Minecraft**. Funciona sin pagar hosting y sin
configurar nada a mano.

Crea un servidor en dos clics y tus amigos se conectan. Puedes jugar en tu red local o desde fuera con
Tailscale, sin abrir puertos en el router.

## Sistemas compatibles

| Sistema | Versión | Cómo funciona |
|---|---|---|
| **Windows 11** | Cualquier versión actual | App de escritorio + Linux ligero (WSL2) con red "mirrored" |
| **Windows 10** | 22H2 (build 19044 o superior) | App de escritorio + WSL2 con reenvío de puertos automático |
| **Linux** | Ubuntu 24.04 o basadas en él: Linux Mint 22, Pop!_OS 24.04, Zorin OS 18, Kubuntu/Xubuntu 24.04 | Instalación directa + interfaz web en el navegador |

En Windows, la app instala sola **Ubuntu 24.04** dentro de WSL2. No hace falta saber Linux.
Requisitos: procesador Intel o AMD de 64 bits, virtualización activada en la BIOS (Windows) y al menos 12 GB libres.

## Qué incluye

- **Pterodactyl** (Panel + Wings), el mismo software que usan muchos hosts profesionales, instalado y configurado automáticamente.
- **App con interfaz neón rosa**, icono en la bandeja del sistema y panel web propio.
- **Terraria**: Vanilla, TShock (plugins) y tModLoader (mods). Eliges mundo, tamaño, dificultad, maldad, semilla, versión y jugadores.
- **Minecraft Java**: Vanilla, Paper (plugins) y Forge (mods), con el Java correcto elegido solo.
- **Control de recursos**: eliges cuánta RAM y almacenamiento usa cada servidor, hasta toda la RAM del equipo.
- **Archivos y mundos**: subir y descargar mundos, consola en vivo, encender, apagar y reiniciar.
- **Acceso remoto con Tailscale**: tus amigos entran desde cualquier lugar sin abrir puertos.
- **Reparación automática**: si una instalación se corta, el servidor se reinstala solo al iniciar.
- **Seguridad**: el panel y la API solo escuchan en tu propio equipo (127.0.0.1) y bloquean peticiones de otras páginas web (CSRF).

## Instalación rápida

**Windows 10 / 11**
1. Descarga el proyecto (botón **Code → Download ZIP**). Antes de descomprimir: clic derecho en el ZIP →
   **Propiedades → Desbloquear → Aceptar** (si no, Windows puede bloquear la app).
2. Doble clic en `ThesknaepHost.bat`.
3. Pulsa **INSTALAR / REPARAR** y acepta el permiso de administrador. La primera vez tarda 10–20 min.
4. Pulsa **INICIAR** y luego **+ CREAR SERVIDOR**.

**Linux**
```bash
sudo apt install -y git
git clone https://github.com/Thesknaep/ThesknaepHost.git
cd ThesknaepHost
sudo bash linux/instalar-linux.sh
```
Se abre sola en el navegador (`http://127.0.0.1:8090`).

## Puertos

| Juego | Puertos |
|---|---|
| Terraria | 7777–7780 (hasta 4 servidores) |
| Minecraft | 25565–25566 (hasta 2 servidores) |

## Estado de las pruebas

| Sistema | Estado |
|---|---|
| Windows 11 | ✅ Probado y funcionando |
| Windows 10 (22H2) | ⚠️ Soportado, con menos pruebas: pueden aparecer errores |
| Linux | ⚠️ Soportado, con menos pruebas: pueden aparecer errores |

Dentro de la app, el botón **? AYUDA** tiene el modo de uso, las reglas y los **errores conocidos con su solución**
para cada sistema.

## Actualizaciones

- **Windows:** la app revisa GitHub cada vez que se abre. Si hay una versión nueva, avisa y la instala con un clic
  (**ACTUALIZAR AHORA**) y se vuelve a abrir sola. También puedes buscarla en el icono junto al reloj →
  **Buscar actualizaciones**. Tus servidores, mundos y contraseñas no se tocan.
- **Linux:** la interfaz muestra un aviso cuando hay una versión nueva. Para instalarla:
  ```bash
  cd ThesknaepHost && git pull && sudo bash linux/instalar-linux.sh
  ```

## Soporte y contacto

¿Algo no funciona, encontraste un error o tienes una idea? **Escríbeme y lo soluciono.**

1. Entra en la pestaña [**Issues**](https://github.com/Thesknaep/ThesknaepHost/issues) de este repositorio y pulsa **New issue**.
2. Cuenta tu sistema (Windows 10, Windows 11 o Linux y versión), qué hiciste, qué esperabas y qué pasó.
3. Adjunta una foto del error y, en Windows, los archivos `instalar.log` y `puertos.log` de
   `%LOCALAPPDATA%\ThesknaepHost` (en la app: **? AYUDA → ABRIR REGISTROS**).

No compartas el archivo `credenciales.txt`: tiene tus contraseñas.

## Documentación

- [LEEME.md](LEEME.md): guía completa para Windows.
- [LEEME-LINUX.md](LEEME-LINUX.md): guía completa para Linux.

## Aviso

ThesknaepHost es un proyecto independiente. No está afiliado a Pterodactyl, Re-Logic (Terraria) ni
Mojang/Microsoft (Minecraft). Necesitas tu propia copia de los juegos para jugar.
