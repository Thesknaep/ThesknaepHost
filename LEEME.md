# ThesknaepHost

Panel tipo "host de juegos" para tu PC con Windows 10 (22H2) o Windows 11, usando **Pterodactyl** (Panel + Wings).
Pterodactyl solo funciona en Linux, así que ThesknaepHost crea una máquina Linux ligera (WSL2)
llamada `ThesknaepHost` y lo instala todo dentro. Tú solo usas la ventana de ThesknaepHost y el panel web.

## Primer uso

1. Doble clic en **ThesknaepHost.bat**.
2. Pulsa **Instalar / Reparar** y acepta el permiso de administrador.
   - Si WSL no estaba instalado, te pedirá **reiniciar el PC**. Después vuelve a pulsar *Instalar*.
   - La primera instalación tarda 10–20 minutos (descarga Ubuntu, PHP, MariaDB, Docker, Pterodactyl).
3. Cuando diga "Listo", pulsa **INICIAR** y luego **PANEL WEB** (http://127.0.0.1:8088).
4. Pulsa **USUARIO Y CLAVE** para entrar como `admin`. Cambia la contraseña en el panel.
5. Pulsa **+ CREAR SERVIDOR** para crear tu servidor de Terraria.

## Crear un servidor de Terraria

En **+ CREAR SERVIDOR** eliges:

| Tipo | Para qué | Tus amigos entran con |
|---|---|---|
| **Vanilla** | Terraria original, lo más liviano | Terraria normal |
| **TShock** | Plugins (.dll), permisos, grupos, anti-cheat, comandos de admin | Terraria normal |
| **tModLoader** | Mods (.tmod) | tModLoader (gratis en Steam); los mods se descargan solos al entrar |

También: nombre, mundo, jugadores (1–255), tamaño, dificultad, contraseña, RAM y almacenamiento.
Puedes tener hasta 4 servidores de Terraria (puertos 7777–7780). La primera vez que creas uno de cada
tipo, la app descarga su configuración (egg) desde github.com/pterodactyl/game-eggs.

### Mundo: tamaño, dificultad, maldad y semilla

En la columna **MUNDO** eliges nombre, semilla, tamaño (pequeño, mediano, grande), dificultad
(viaje, clásico, experto, maestro) y maldad (aleatoria, corrupción, carmesí). El recuadro
**SE CREARÁ ASÍ** muestra lo que vas a obtener.

| Opción | Vanilla | TShock | tModLoader |
|---|---|---|---|
| Nombre y tamaño | Sí | Sí | Sí |
| Dificultad | Sí | Sí | Sí |
| Semilla | Sí | Sí | Sí |
| Maldad (corrupción / carmesí) | **No: sale al azar** | **Sí** | **No: sale al azar** |

La maldad solo se puede fijar en **TShock** (opción `-worldevil`). El servidor oficial de Terraria
no tiene ninguna opción para elegirla al crear el mundo automáticamente (lo revisé en el propio
programa del servidor 1.4.5.8): solo la pregunta en su menú interactivo. Si necesitas Vanilla con
una maldad concreta, crea el mundo en tu Terraria y súbelo con **ARCHIVOS → SUBIR MUNDO**.

- La semilla acepta hasta 20 caracteres: letras, números, espacios y `. _ - |`. Las semillas
  especiales (`for the worthy`, `not the bees`…) se envían tal cual, pero no está comprobado que el
  servidor las active al crear el mundo automáticamente: revisa la consola al generar.
- El mundo se genera la **primera vez** que arranca el servidor. Después esos valores quedan fijos
  en el mundo: para cambiarlos hay que crear otro servidor (o borrar el `.wld` y reiniciar).
- Para comprobarlo, en la consola del panel web aparece al generar:
  `Creating world - Seed: ..., Width: ..., Height: ..., Evil: ..., Difficulty: ...`
  (Width 4200 = pequeño, 6400 = mediano, 8400 = grande; Evil 0 = corrupción, 1 = carmesí).

### Versión (y jugar desde Android)

Debajo del tipo está el selector **VERSIÓN** (`<` `>` o clic para pasar a la siguiente). La lista se
descarga sola: Terraria desde la wiki oficial (1.4.4 en adelante), TShock y tModLoader desde GitHub.
Para TShock muestra también la versión de Terraria que trae, por ejemplo `TSHOCK v5.2.4 · TERRARIA 1.4.4.9`.

**Para que entren desde Android** (solo Vanilla o TShock; tModLoader no existe en celular):
1. En el celular, abre Terraria y mira la versión en el menú principal (abajo).
2. Crea el servidor eligiendo esa misma versión de Terraria (o la de TShock que diga esa versión).
3. Con el celular en el mismo WiFi: Multijugador → En línea → agrega la IP que muestra la app y el puerto `7777`.

TShock 5 (Terraria 1.4.4) usa .NET 6 y TShock 6 (Terraria 1.4.5) usa .NET 9: la app elige la correcta sola.
Los plugins deben ser para la misma versión de TShock que elijas.

### Extras

| Extra | Qué hace realmente |
|---|---|
| **Backups automáticos** | Copia del servidor cada 6 horas; guarda las 3 últimas y borra la más vieja. Se ven y restauran en el panel web, pestaña *Backups*. Ocupan espacio en tu disco. |
| **Acceso API** | Crea una clave para la API de Pterodactyl (controlar tus servidores desde scripts o bots). Se guarda en `%LOCALAPPDATA%\ThesknaepHost\api-key.txt`. No la compartas. |
| **Slots ilimitados** | Pone 255 jugadores, el máximo que permite Terraria. |
| Sin anuncios | Siempre: es tu propio host, no hay anuncios. |
| Anti-DDoS | **No se puede dar desde un PC de casa**: la protección real la da el proveedor de red. Si juegas con amigos por Internet, usa playit.gg o Tailscale para no mostrar tu IP. |
| Fast DL | No aplica a Terraria (es para juegos tipo Counter-Strike). |
| Soporte prioritario | No aplica: el host eres tú. |

## Mis servidores: prender, apagar y reiniciar

Botón **MIS SERVIDORES** (en CONTROL). Abre una ventana con una tarjeta por cada servidor:
estado (EN LÍNEA, APAGADO, ARRANCANDO, INSTALANDO…), juego y tipo, puerto, tiempo encendido y uso real
de RAM, CPU y disco. Botones **PRENDER**, **APAGAR**, **REINICIAR** y **CONSOLA** (abre la consola del
servidor en el panel web). Se actualiza sola cada 5 segundos y no bloquea la ventana principal.
La **consola de Linux** está al pie de esa ventana.

**Icono junto al reloj (bandeja del sistema):**
- La **X** de la ventana no cierra la app: la esconde en el icono rosado de la bandeja (la flechita `^`
  junto al reloj). Tus servidores siguen funcionando.
- **Clic** en el icono: vuelve a abrir la ventana. **Clic derecho**: *Abrir ThesknaepHost*,
  *Mis servidores*, *Panel web* y **Salir y apagar todo** (apaga los servidores guardando el mundo,
  apaga Linux y cierra la app).
- Si abres el acceso directo con la app escondida, se muestra la misma ventana (no se abre otra).

**Los servidores siempre empiezan apagados:**
- Al abrir la app, si alguno quedó encendido, se apaga con un "stop" normal (el juego guarda el mundo).
- Al arrancar Linux (botón INICIAR o al encender el PC), Wings ya no vuelve a prender los servidores
  que estaban encendidos: se borra su memoria de estados (`states.json`) antes de que arranque.
- Los prendes tú cuando quieras desde **MIS SERVIDORES**. (Al crear un servidor nuevo, ese sí arranca
  solo una vez para instalar el juego y generar el mundo.)

## Crear un servidor de Minecraft

En **+ CREAR SERVIDOR** pulsa **MINECRAFT** arriba a la izquierda. Todo cambia a opciones de Minecraft:

| Tipo | Para qué | Tus amigos entran con |
|---|---|---|
| **Vanilla** | Minecraft Java oficial | Minecraft Java normal |
| **Paper** | Más rápido, acepta plugins (.jar) | Minecraft Java normal |
| **Forge** | Mods (.jar) | Forge con los mismos mods y versión |

- **Versión:** la lista sale de Mojang, PaperMC y Forge. La app elige sola el Java correcto
  (Java 25 para 26.x, 21 para 1.20.5–1.21, 17 para 1.18–1.20.4, 8 para versiones antiguas).
- **Mundo:** nombre, semilla, modo (supervivencia, creativo, aventura, hardcore), dificultad
  (pacífico, fácil, normal, difícil) y tipo de mundo (normal, plano, biomas grandes, amplificado).
  Hardcore fija la dificultad en difícil. Se escriben en `server.properties` **solo en el primer
  arranque**; después puedes cambiarlos en el panel (Files → server.properties).
- **PvP**, jugadores (1–100), RAM y almacenamiento.
- **EULA:** Minecraft exige aceptar el EULA de Mojang (minecraft.net/eula). Sin aceptarlo no se crea.
- Puertos de Minecraft: 25565 y 25566 (hasta 2 servidores). Solo **Minecraft Java** (PC):
  Bedrock (celular/consola) no puede entrar a estos servidores.

## Mapas, plugins y mods (botón ARCHIVOS)

En Minecraft: **SUBIR MUNDO (.zip)** con la carpeta de tu mundo (la que tiene `level.dat`; en tu PC
está en `%APPDATA%\.minecraft\saves`), **SUBIR PLUGIN (.jar)** en Paper y **SUBIR MOD (.jar)** en Forge.
El mundo anterior no se borra: se renombra a `<nombre>-anterior-<fecha>`.

En Terraria:

Elige el servidor con `<` `>` y pulsa **ARCHIVOS**:
- **ABRIR CARPETA DEL SERVIDOR**: se abre en el Explorador de Windows; arrastra lo que quieras.
  Después pulsa **ACTUALIZAR** para que el servidor pueda leer esos archivos.
- **SUBIR MUNDO (.wld)**: copia tu mapa y, si quieres, lo deja como mundo principal. En tModLoader
  también copia el `.twld` (datos de mods) si está junto al `.wld`. Tus mundos de Terraria están en
  `Documentos\My Games\Terraria\Worlds` (tModLoader: `Documentos\My Games\Terraria\tModLoader\Worlds`).
- **SUBIR PLUGIN (.dll)**: solo TShock, van a `ServerPlugins`.
- **SUBIR MOD (.tmod)**: solo tModLoader, van a `mods` y se activan solos.
- **GESTOR DE ARCHIVOS WEB**: el editor de archivos del panel.
- **SFTP** (FileZilla, WinSCP): `127.0.0.1`, puerto `2022`, usuario `admin.<código del servidor>`,
  contraseña la del panel.

Apaga el servidor antes de cambiar el mundo y reinícialo después de subir plugins o mods.

### Plugins de TShock: qué tener en cuenta

- La app instala la **última versión de TShock** (hoy 6.2.1, para Terraria 1.4.5.8) y la corre con **.NET 9**,
  que es lo que necesita. El egg oficial trae .NET 6, con el que TShock 6 no arranca; la app lo corrige sola.
- Usa plugins **hechos para TShock 6**. Los plugins de TShock 5 (Terraria 1.4.4) o de TShock 4 normalmente
  no cargan. Mira la versión en la página del plugin.
- Si el plugin trae otros `.dll` (dependencias), súbelos todos juntos a `ServerPlugins`.
- Muchos plugins crean su configuración en la carpeta `tshock` al primer arranque: edítala ahí y reinicia.
- Si un plugin falla, la consola del panel web muestra el error al arrancar.
- Tus amigos deben tener la **misma versión de Terraria** que el servidor (la última de Steam).

## Abrirlo como aplicación

La primera vez que abres `ThesknaepHost.bat` se crea un acceso directo **ThesknaepHost** (icono rosado)
en el Escritorio y en el menú Inicio. Desde ahí se abre como una aplicación normal, sin consola.
Si mueves la carpeta, borra `ThesknaepHost.vbs` y vuelve a abrir `ThesknaepHost.bat` para rehacer los accesos.

## Elegir RAM y almacenamiento

En la tarjeta **RECURSOS DEL SERVIDOR** (con ThesknaepHost iniciado):
1. Elige el servidor con `<` `>`.
2. Mueve la barra de **MEMORIA RAM** (de 0,5 en 0,5 GB, hasta la RAM de tu PC menos 2 GB).
3. Mueve la barra de **ALMACENAMIENTO** en GB (hasta el espacio libre del disco menos 5 GB).
4. Pulsa **APLICAR**.

Normalmente se aplica al momento. Si la RAM total de tus servidores supera lo que Windows deja
usar a Linux (por defecto, la mitad de la RAM del PC), ThesknaepHost sube el límite `memory=` en
`.wslconfig` y te ofrece reiniciar WSL. Eso apaga tus servidores alrededor de un minuto.

## Cómo se conectan tus amigos

- **Misma red (LAN/WiFi):** en Terraria > Multijugador > Unirse por IP, usa la IP que muestra
  ThesknaepHost (por ejemplo `192.168.1.50`) y el puerto `7777`.
- **Por Internet:** en tu router, redirige (port forwarding) el puerto **7777 TCP** hacia la IP de tu PC
  y comparte tu IP pública. Alternativa sin tocar el router: Tailscale, Radmin VPN o playit.gg.

## Crear más servidores (Minecraft, otro Terraria…)

En el panel: **Admin (icono de engranaje) > Servers > Create New**.
- Nodo: `Mi PC`. Puertos libres: 7778–7780 (Terraria) y 25565–25566 (Minecraft).
- Minecraft ya viene incluido (Nest *Minecraft* > Paper o Vanilla). Dale al menos 2048 MB.
- Más juegos: descarga el egg en https://github.com/pterodactyl/game-eggs e impórtalo en
  **Admin > Nests > Import Egg** (por ejemplo `terraria/tshock` o `terraria/tmodloader`).
- Si necesitas otro puerto: **Admin > Nodes > Mi PC > Allocation** (IP `0.0.0.0`), y ábrelo en el
  firewall de Windows.

## Qué toca en tu PC

- Una distro WSL nueva llamada `ThesknaepHost` (sus datos en `%LOCALAPPDATA%\ThesknaepHost`). No toca otras distros.
- `%USERPROFILE%\.wslconfig`: añade `networkingMode=mirrored` (copia de seguridad en `.wslconfig.bak`).
  Esto afecta a todas tus distros WSL.
- Firewall: reglas "ThesknaepHost Juegos" que abren solo 7777–7780 y 25565–25566 (TCP/UDP).
- El panel (8088) y Wings (8080) **no** se abren en el firewall: solo se usan desde tu PC.

## Problemas comunes

| Problema | Solución |
|---|---|
| El panel no abre | Pulsa *Iniciar* y espera 30 s. Si sigue, *Instalar / Reparar*. |
| El panel no carga o la consola dice "no se puede conectar" | Entra siempre por `http://127.0.0.1:8088`, **no** por `localhost`: Windows prueba primero IPv6 y WSL no lo reenvía, así que `localhost` se queda colgado. |
| Puerto 8088 u 8080 ocupado por otro programa | Cierra ese programa, o cambia el puerto en el script de Linux. |
| Diagnóstico | *Consola Linux* y ejecuta `systemctl status wings` o `journalctl -u wings -n 50`. |

## Desinstalar

Ejecuta `Desinstalar.ps1` como administrador. **Borra todos los mundos y servidores.**
Haz una copia antes desde el panel (pestaña *Files* o *Backups* de cada servidor).

## Windows 10

Funciona en **Windows 10 22H2** (Configuración → Sistema → Acerca de: compilación 19045). Diferencias:

- WSL en Windows 10 no tiene la red *mirrored*, así que el instalador crea la tarea **ThesknaepHost-Puertos**.
  Cada vez que pulsas **INICIAR**, reenvía los puertos de juego (7777–7780, 25565–25566) de Windows a Linux.
- Si al instalar WSL hace falta reiniciar, el instalador te lo pide y **sigue solo** al volver a entrar.
- Registro del reenvío: `%LOCALAPPDATA%\ThesknaepHost\puertos.log`.
