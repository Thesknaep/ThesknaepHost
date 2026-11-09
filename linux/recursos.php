<?php
// ThesknaepHost - ayudante para Pterodactyl. Siempre responde una linea JSON.
//   php recursos.php list
//   php recursos.php set <id> <ram_mb> <disco_mb>
//   php recursos.php create <json_en_base64>
//   php recursos.php setvar <id> <VARIABLE> <valor_en_base64>
require '/var/www/pterodactyl/vendor/autoload.php';
$app = require '/var/www/pterodactyl/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Http\UploadedFile;
use Pterodactyl\Models\{Allocation, ApiKey, Egg, EggVariable, Nest, Schedule, Server, ServerVariable, Task, User};
use Pterodactyl\Services\Servers\BuildModificationService;

const EGGS = [
    'vanilla'    => ['name' => 'Terraria Vanilla', 'url' => 'terraria/vanilla/egg-terraria-vanilla.json'],
    'tshock'     => ['name' => 'tshock',           'url' => 'terraria/tshock/egg-tshock.json'],
    'tmodloader' => ['name' => 'tModloader',       'url' => 'terraria/tmodloader/egg-t-modloader.json'],
];

// TShock 6.x (Terraria 1.4.5) esta hecho para .NET 9, pero el egg oficial trae solo la imagen de .NET 6,
// con la que TShock 6 no arranca. TShock 5.x (Terraria 1.4.4) si usa .NET 6.
const IMAGEN_TSHOCK6 = 'ghcr.io/ptero-eggs/yolks:dotnet_9';
const IMAGEN_TSHOCK5 = 'ghcr.io/ptero-eggs/yolks:dotnet_6';

// Variable del egg donde va la version elegida
const VAR_VERSION = ['vanilla' => 'TERRARIA_VERSION', 'tshock' => 'TSHOCK_VERSION', 'tmodloader' => 'VERSION'];

function imagenPara(string $tipo, Egg $egg, string $version): string {
    if ($tipo === 'tshock') {
        if (preg_match('/^v?5\./', $version)) return IMAGEN_TSHOCK5;
        $imgs = $egg->docker_images ?? [];
        if (!in_array(IMAGEN_TSHOCK6, $imgs, true)) {
            // la agregamos a la lista del egg para que tambien se vea en el panel
            $egg->docker_images = array_merge(['.NET 9 (TShock 6)' => IMAGEN_TSHOCK6], $imgs);
            $egg->save();
        }
        return IMAGEN_TSHOCK6;
    }
    return array_values($egg->docker_images)[0];
}

// El instalador del egg Vanilla busca la version con grep "1448", que tambien encaja con "14481"
// y rompe la descarga. Lo dejamos buscando el nombre exacto del zip.
function arreglarEggVanilla(Egg $egg) {
    $s = $egg->script_install;
    $nuevo = str_replace('grep "${CLEAN_VERSION}"', 'grep -- "-${CLEAN_VERSION}.zip"', $s);
    if ($nuevo !== $s) { $egg->script_install = $nuevo; $egg->save(); }
}

// ------------------------------------------------------------------ Minecraft (eggs que trae el panel)
const MC = [
    'mc-vanilla' => ['egg' => 'Vanilla Minecraft', 'var' => 'VANILLA_VERSION'],
    'mc-paper'   => ['egg' => 'Paper',             'var' => 'MINECRAFT_VERSION'],
    'mc-forge'   => ['egg' => 'Forge Minecraft',   'var' => 'MC_VERSION'],
];

// "26.3" -> [26,3,0]; "1.20.4" -> [1,20,4]; "latest" -> la mas nueva
function mcVer(string $v): array {
    if ($v === '' || $v === 'latest') return [99, 0, 0];
    $p = array_map('intval', explode('.', $v));
    while (count($p) < 3) $p[] = 0;
    return array_slice($p, 0, 3);
}
function mcAntesDe(array $v, string $ref): bool { return version_compare(implode('.', $v), $ref, '<'); }

// Java que necesita cada version de Minecraft (imagenes que trae el egg)
function javaPara(array $v): string {
    if ($v[0] >= 26)                return 'java_25';   // 26.x pide Java 25
    if (!mcAntesDe($v, '1.20.5'))   return 'java_21';
    if (!mcAntesDe($v, '1.18'))     return 'java_17';
    if (!mcAntesDe($v, '1.17'))     return 'java_16';
    return 'java_8';
}

function eggMinecraft(string $tipo): Egg {
    $egg = Egg::whereHas('nest', function ($q) { $q->where('name', 'Minecraft'); })
        ->where('name', MC[$tipo]['egg'])->first();
    if (!$egg) throw new RuntimeException('El panel no tiene el egg "' . MC[$tipo]['egg'] . '" (Admin > Nests > Minecraft).');
    return $egg;
}

// Prepara un servidor de Minecraft: egg, variables, imagen de Java y server.properties del mundo
function prepararMinecraft(array $o, string $tipo, string $version, string $nombre): array {
    $egg = eggMinecraft($tipo);
    $alloc = Allocation::whereNull('server_id')->whereBetween('port', [25565, 25566])->orderBy('port')->first();
    if (!$alloc) responder(['ok' => false, 'error' => 'No quedan puertos libres de Minecraft (25565-25566). Borra un servidor en el panel.'], 1);

    // Forge: la version llega como "1.20.1|recommended" o "26.3|latest"
    $build = 'recommended';
    if ($tipo === 'mc-forge' && strpos($version, '|') !== false) {
        [$version, $build] = explode('|', $version, 2);
        $build = in_array($build, ['recommended', 'latest'], true) ? $build : 'recommended';
    }
    $v = mcVer($version);
    $viejo = mcAntesDe($v, '1.14');            // hasta 1.13 server.properties usa numeros

    $modo = in_array($o['modo'] ?? '', ['survival', 'creative', 'adventure', 'hardcore'], true) ? $o['modo'] : 'survival';
    $dif = in_array($o['dif_mc'] ?? '', ['peaceful', 'easy', 'normal', 'hard'], true) ? $o['dif_mc'] : 'normal';
    $hardcore = $modo === 'hardcore';
    if ($hardcore) { $modo = 'survival'; $dif = 'hard'; }   // hardcore = supervivencia, dificil, una vida
    $tm = in_array($o['tipo_mundo'] ?? '', ['normal', 'flat', 'large_biomes', 'amplified'], true) ? $o['tipo_mundo'] : 'normal';
    $levelType = !mcAntesDe($v, '1.19') ? "minecraft:$tm" : ['normal' => 'default', 'flat' => 'flat', 'large_biomes' => 'largebiomes', 'amplified' => 'amplified'][$tm];

    $mundo   = substr(preg_replace('/[^A-Za-z0-9_-]/', '', (string) ($o['mundo'] ?? 'world')) ?: 'world', 0, 32);
    $semilla = substr(preg_replace('/[^A-Za-z0-9-]/', '', (string) ($o['semilla'] ?? '')), 0, 32);
    $jug     = max(1, min(100, (int) ($o['jugadores'] ?? 10)));
    $motd    = substr(trim(preg_replace('/[^A-Za-z0-9 -]/', '', "ThesknaepHost - $nombre")), 0, 59);

    $props = [
        'server-port' => $alloc->port, 'level-name' => $mundo, 'level-seed' => $semilla,
        'gamemode' => $viejo ? ['survival' => 0, 'creative' => 1, 'adventure' => 2][$modo] : $modo,
        'difficulty' => $viejo ? ['peaceful' => 0, 'easy' => 1, 'normal' => 2, 'hard' => 3][$dif] : $dif,
        'hardcore' => $hardcore ? 'true' : 'false', 'level-type' => $levelType,
        'max-players' => $jug, 'pvp' => empty($o['pvp']) ? 'false' : 'true', 'motd' => $motd,
    ];
    // Se aplica solo en el PRIMER arranque (archivo .thesknaephost-mundo): despues puedes cambiarlo en el panel.
    // Va dentro de $( ) porque la imagen de Java ejecuta un solo comando (igual que hace el egg de Forge).
    $borrar = implode(' ', array_map(function ($k) { return "-e '/^$k=/d'"; }, array_keys($props)));
    $lineas = implode(' ', array_map(function ($k, $val) { return "'$k=$val'"; }, array_keys($props), $props));
    $eula = !empty($o['eula']) ? 'echo eula=true > eula.txt; ' : '';
    $prep = "\$(test -f .thesknaephost-mundo || (touch server.properties; sed -i $borrar server.properties; "
          . "printf '%s\\n' $lineas >> server.properties; {$eula}touch .thesknaephost-mundo) >/dev/null 2>&1)";

    $env = [];
    foreach ($egg->variables as $var) $env[$var->env_variable] = $var->default_value;
    $env[MC[$tipo]['var']] = $version;
    if ($tipo === 'mc-forge') $env['BUILD_TYPE'] = $build;

    return [
        'egg' => $egg, 'alloc' => $alloc, 'env' => $env, 'startup' => $prep . $egg->startup,
        'image' => 'ghcr.io/pterodactyl/yolks:' . javaPara($v),
        'info' => ['mundo' => $mundo, 'semilla' => $semilla, 'modo' => $hardcore ? 'hardcore' : $modo, 'dif_mc' => $dif,
                   'tipo_mundo' => $tm, 'java' => javaPara($v), 'version' => $version, 'jugadores' => $jug],
    ];
}

function responder(array $d, int $code = 0) { echo json_encode($d, JSON_UNESCAPED_UNICODE) . "\n"; exit($code); }

function tipoDe(?Egg $egg): string {
    if (!$egg) return 'otro';
    foreach (EGGS as $tipo => $e) if (strcasecmp($egg->name, $e['name']) === 0) return $tipo;
    foreach (MC as $tipo => $e) if (strcasecmp($egg->name, $e['egg']) === 0) return $tipo;
    return 'otro';
}

function nestTerraria(): Nest {
    return Nest::where('name', 'Terraria')->first()
        ?? app(Pterodactyl\Services\Nests\NestCreationService::class)
            ->handle(['name' => 'Terraria', 'description' => 'Servidores de Terraria'], 'admin@thesknaephost.local');
}

// Importa el egg desde github.com/pterodactyl/game-eggs la primera vez que se usa
function eggPara(string $tipo): Egg {
    if (!isset(EGGS[$tipo])) throw new RuntimeException("Tipo desconocido: $tipo");
    $nest = nestTerraria();
    $egg = Egg::where('nest_id', $nest->id)->where('name', EGGS[$tipo]['name'])->first();
    if ($egg) return $egg;
    $json = @file_get_contents('https://raw.githubusercontent.com/pterodactyl/game-eggs/main/' . EGGS[$tipo]['url']);
    if (!$json) throw new RuntimeException('No se pudo descargar el egg de ' . $tipo . '. ¿Hay internet?');
    $tmp = tempnam(sys_get_temp_dir(), 'egg') . '.json';
    file_put_contents($tmp, $json);
    $egg = app(Pterodactyl\Services\Eggs\Sharing\EggImporterService::class)
        ->handle(new UploadedFile($tmp, 'egg.json', 'application/json', null, true), $nest->id);
    @unlink($tmp);
    return $egg->refresh();
}

function limpiarNombre(string $s, int $max): string {
    $s = preg_replace('/[^A-Za-z0-9_-]/', '', $s);
    return substr($s !== '' ? $s : 'MiMundo', 0, $max);
}

function ampliarNodo(Server $server, int $mem, int $disk, ?int $excluir = null) {
    $node = $server->node;
    $q = Server::where('node_id', $node->id);
    if ($excluir) $q->where('id', '!=', $excluir);
    $memTotal = (int) (clone $q)->sum('memory') + $mem;
    $diskTotal = (int) (clone $q)->sum('disk') + $disk;
    if ($node->memory < $memTotal) $node->memory = $memTotal;
    if ($node->disk < $diskTotal) $node->disk = $diskTotal;
    $node->save();
}

function totalRam(): int { return (int) Server::sum('memory'); }

try {
    $cmd = $argv[1] ?? 'list';

    // ------------------------------------------------------------------ list
    if ($cmd === 'list') {
        $lista = [];
        foreach (Server::with('egg')->orderBy('id')->get() as $s) {
            $vars = [];
            foreach ($s->variables as $v) $vars[$v->env_variable] = $v->server_value ?? $v->default_value;
            $lista[] = [
                'id' => $s->id, 'uuid' => $s->uuid, 'short' => $s->uuidShort, 'name' => $s->name,
                'egg' => $s->egg->name ?? '', 'tipo' => tipoDe($s->egg),
                'memory' => (int) $s->memory, 'disk' => (int) $s->disk,
                'world' => $vars['WORLD_NAME'] ?? null,
                'port' => $s->allocation->port ?? null,
                'backups' => Schedule::where('server_id', $s->id)->where('name', 'Backup automatico')->exists(),
            ];
        }
        responder(['ok' => true, 'servers' => $lista]);
    }

    // ------------------------------------------------------------------ set (RAM / disco)
    if ($cmd === 'set') {
        [$id, $mem, $disk] = [(int) ($argv[2] ?? 0), (int) ($argv[3] ?? 0), (int) ($argv[4] ?? 0)];
        if ($mem < 256 || $disk < 512) responder(['ok' => false, 'error' => 'Valores demasiado bajos.'], 1);
        $server = Server::findOrFail($id);
        ampliarNodo($server, $mem, $disk, $server->id);
        $aviso = null;
        try {
            app(BuildModificationService::class)->handle($server, [
                'memory' => $mem, 'disk' => $disk, 'swap' => $server->swap, 'io' => $server->io, 'cpu' => $server->cpu,
                'threads' => $server->threads, 'oom_disabled' => $server->oom_disabled, 'allocation_id' => $server->allocation_id,
                'database_limit' => $server->database_limit, 'allocation_limit' => $server->allocation_limit,
                'backup_limit' => $server->backup_limit,
            ]);
        } catch (Pterodactyl\Exceptions\Http\Connection\DaemonConnectionException $e) {
            $aviso = 'Guardado, pero Wings no respondió. Reinicia el servidor para aplicarlo.';
        }
        responder(['ok' => true, 'aviso' => $aviso, 'memoria_total_servidores' => totalRam()]);
    }

    // ------------------------------------------------------------------ setvar (p. ej. WORLD_NAME)
    if ($cmd === 'setvar') {
        $server = Server::findOrFail((int) ($argv[2] ?? 0));
        $nombre = $argv[3] ?? '';
        $valor = base64_decode($argv[4] ?? '');
        $var = EggVariable::where('egg_id', $server->egg_id)->where('env_variable', $nombre)->firstOrFail();
        ServerVariable::updateOrCreate(['server_id' => $server->id, 'variable_id' => $var->id], ['variable_value' => $valor]);
        responder(['ok' => true]);
    }

    // ------------------------------------------------------------------ estado: cada servidor con su estado real (Wings)
    if ($cmd === 'estado') {
        $repo = app(Pterodactyl\Repositories\Wings\DaemonServerRepository::class);
        $lista = [];
        foreach (Server::with(['egg', 'allocation'])->orderBy('id')->get() as $s) {
            $e = ['estado' => 'offline', 'ram' => 0, 'cpu' => 0, 'disco_usado' => 0, 'uptime' => 0];
            if ($s->status === 'installing')          $e['estado'] = 'instalando';
            elseif ($s->status === 'install_failed')  $e['estado'] = 'error_instalacion';
            elseif ($s->status === 'suspended')       $e['estado'] = 'suspendido';
            else {
                try {
                    $det = $repo->setServer($s)->getDetails();
                    $u = $det['utilization'] ?? [];
                    $e['estado'] = $det['state'] ?? ($u['state'] ?? 'offline');   // running, starting, stopping, offline
                    $e['ram'] = (int) round(($u['memory_bytes'] ?? 0) / 1048576);
                    $e['cpu'] = round((float) ($u['cpu_absolute'] ?? 0), 1);
                    $e['disco_usado'] = (int) round(($u['disk_bytes'] ?? 0) / 1048576);
                    $e['uptime'] = (int) (($u['uptime'] ?? 0) / 1000);
                } catch (Throwable $ex) {
                    $e['estado'] = 'sin_conexion';
                }
            }
            $lista[] = array_merge([
                'id' => $s->id, 'uuid' => $s->uuid, 'short' => $s->uuidShort, 'name' => $s->name,
                'egg' => $s->egg->name ?? '', 'tipo' => tipoDe($s->egg), 'port' => $s->allocation->port ?? null,
                'memory' => (int) $s->memory, 'disk' => (int) $s->disk,
            ], $e);
        }
        responder(['ok' => true, 'servers' => $lista]);
    }

    // ------------------------------------------------------------------ reparar: reinstala servidores cuya instalacion se corto
    // (p. ej. si Linux se reinicio mientras descargaba el juego). Solo toca los que estan VACIOS de verdad:
    // nunca terminaron de instalarse (installed_at nulo) y su carpeta no tiene ningun archivo.
    if ($cmd === 'reparar') {
        $archivos = app(Pterodactyl\Repositories\Wings\DaemonFileRepository::class);
        $reinstalar = app(Pterodactyl\Services\Servers\ReinstallServerService::class);
        $reparados = []; $errores = [];
        foreach (Server::whereNull('installed_at')->whereNull('status')->orderBy('id')->get() as $s) {
            try {
                $lista = $archivos->setServer($s)->getDirectory('/');
                $hayArchivos = false;
                foreach ($lista as $f) if (!empty($f['file']) || !empty($f['symlink'])) { $hayArchivos = true; break; }
                if ($hayArchivos) continue;
                $reinstalar->handle($s);
                $reparados[] = $s->name;
            } catch (Throwable $e) { $errores[] = $s->name . ': ' . $e->getMessage(); }
        }
        responder(['ok' => true, 'reparados' => $reparados, 'errores' => $errores]);
    }

    // ------------------------------------------------------------------ power: start | stop | restart | kill
    if ($cmd === 'power') {
        $server = Server::findOrFail((int) ($argv[2] ?? 0));
        $accion = $argv[3] ?? '';
        if (!in_array($accion, ['start', 'stop', 'restart', 'kill'], true)) responder(['ok' => false, 'error' => 'Acción inválida.'], 1);
        if ($server->status === 'installing') responder(['ok' => false, 'error' => 'El servidor todavía se está instalando. Espera a que termine.'], 1);
        app(Pterodactyl\Repositories\Wings\DaemonPowerRepository::class)->setServer($server)->send($accion);
        responder(['ok' => true]);
    }

    // ------------------------------------------------------------------ apagar-todos: apaga (guardando) los que esten encendidos
    if ($cmd === 'apagar-todos') {
        $repo = app(Pterodactyl\Repositories\Wings\DaemonServerRepository::class);
        $power = app(Pterodactyl\Repositories\Wings\DaemonPowerRepository::class);
        $apagados = [];
        foreach (Server::orderBy('id')->get() as $s) {
            if ($s->status) continue;                       // instalando, suspendido, etc.
            try {
                $estado = $repo->setServer($s)->getDetails()['state'] ?? 'offline';
                if (in_array($estado, ['running', 'starting'], true)) {
                    $power->setServer($s)->send('stop');     // "stop" normal: el juego guarda el mundo
                    $apagados[] = $s->name;
                }
            } catch (Throwable $e) { }
        }
        responder(['ok' => true, 'apagados' => $apagados]);
    }

    // ------------------------------------------------------------------ preview (Minecraft): calcula sin crear nada
    if ($cmd === 'preview') {
        $o = json_decode(base64_decode($argv[2] ?? ''), true);
        $tipo = $o['tipo'] ?? 'mc-paper';
        if (!isset(MC[$tipo])) responder(['ok' => false, 'error' => 'preview solo para Minecraft'], 1);
        $version = preg_replace('/[^A-Za-z0-9._|-]/', '', (string) ($o['version'] ?? 'latest')) ?: 'latest';
        $mc = prepararMinecraft($o, $tipo, $version, trim((string) ($o['nombre'] ?? 'Minecraft')));
        responder(['ok' => true, 'egg' => $mc['egg']->name, 'puerto' => $mc['alloc']->port, 'imagen' => $mc['image'],
                   'startup' => $mc['startup'], 'env' => $mc['env'], 'info' => $mc['info']]);
    }

    // ------------------------------------------------------------------ create
    if ($cmd === 'create') {
        $o = json_decode(base64_decode($argv[2] ?? ''), true);
        if (!is_array($o)) responder(['ok' => false, 'error' => 'Datos inválidos.'], 1);

        $tipo = $o['tipo'] ?? 'vanilla';
        $version = preg_replace('/[^A-Za-z0-9._|-]/', '', (string) ($o['version'] ?? 'latest')) ?: 'latest';
        $user = User::where('root_admin', true)->orderBy('id')->firstOrFail();
        $nombre = trim((string) ($o['nombre'] ?? '')) ?: (isset(MC[$tipo]) ? 'Minecraft' : 'Terraria');
        $info = [];

      if (isset(MC[$tipo])) {
        // ====================== MINECRAFT ======================
        $mc = prepararMinecraft($o, $tipo, $version, $nombre);
        $egg = $mc['egg']; $alloc = $mc['alloc']; $env = $mc['env']; $startup = $mc['startup']; $imagen = $mc['image'];
        $info = $mc['info']; $version = $info['version'];
        $juego = 'Minecraft';
      } else {
        // ====================== TERRARIA ======================
        $juego = 'Terraria';
        $version = str_replace('|', '', $version);
        $egg = eggPara($tipo);
        if ($tipo === 'vanilla') arreglarEggVanilla($egg);
        $alloc = Allocation::whereNull('server_id')->whereBetween('port', [7777, 7780])->orderBy('port')->first();
        if (!$alloc) responder(['ok' => false, 'error' => 'No quedan puertos libres (7777-7780). Borra un servidor en el panel.'], 1);

        $mundo     = limpiarNombre($o['mundo'] ?? 'MiMundo', 20);
        $jugadores = (string) max(1, min(255, (int) ($o['jugadores'] ?? 8)));
        $tamano    = (string) max(1, min(3, (int) ($o['tamano'] ?? 2)));
        // Dificultad con los valores del servidor de Terraria: 0 clasico, 1 experto, 2 maestro, 3 viaje
        $dific     = (string) max(0, min(3, (int) ($o['dificultad'] ?? 0)));
        // Semilla: vacia = aleatoria. Sin comillas ni simbolos de shell; maximo 20 (limite del egg)
        $semilla   = trim(substr(preg_replace('/[^A-Za-z0-9 ._|-]/', '', (string) ($o['semilla'] ?? '')), 0, 20));
        // Maldad: solo TShock la puede fijar (-worldevil). Vanilla y tModLoader la eligen al azar.
        $maldad    = in_array($o['maldad'] ?? '', ['random', 'corrupt', 'crimson'], true) ? $o['maldad'] : 'random';
        if ($tipo !== 'tshock') $maldad = 'random';
        $clave     = substr((string) ($o['clave'] ?? ''), 0, 20);

        $env = [];
        foreach ($egg->variables as $v) $env[$v->env_variable] = $v->default_value;
        $env['WORLD_NAME'] = $mundo;
        $env['MAX_PLAYERS'] = $jugadores;
        $env['WORLD_SIZE'] = $tamano;
        $env[VAR_VERSION[$tipo]] = $version;
        $startup = $egg->startup;
        if ($tipo === 'vanilla') {
            // El egg escribe estas variables en serverconfig.txt (worldname, autocreate, difficulty, seed)
            $env['WORLD_DIFFICULTY'] = $dific;
            $env['WORLD_SEED'] = $semilla;
            $env['SERVER_MOTD'] = "Bienvenido a $nombre!";
            $env['PASSWORD'] = $clave;
        } elseif ($tipo === 'tshock') {
            // El egg de TShock no tiene dificultad ni semilla: las pasamos con un archivo de config
            // del servidor (-config, lo lee igual que Vanilla) y la maldad con -worldevil.
            // Ojo: usar echo, no printf '\n' (la imagen hace "echo -e" + eval y los \n se convierten en espacios)
            $prep = "echo 'difficulty=$dific' > thesknaephost-mundo.txt";
            if ($semilla !== '') $prep .= "; echo 'seed=$semilla' >> thesknaephost-mundo.txt";
            $startup = "$prep; ./TShock.Server -config thesknaephost-mundo.txt -ip 0.0.0.0 -port {{SERVER_PORT}}"
                     . " -maxplayers {{MAX_PLAYERS}} -world {{WORLD_NAME}}.wld -worldname {{WORLD_NAME}}"
                     . " -autocreate {{WORLD_SIZE}} -worldevil $maldad";
        } elseif ($tipo === 'tmodloader') {
            $env['DIFFICULTY'] = $dific;
            $env['SERVER_PASSWORD'] = $clave;
            $env['MOTD'] = substr("Bienvenido a $nombre!", 0, 40);
            $env['LANGUAGE'] = '5'; // espanol
            // El egg no maneja la semilla: la escribimos en serverconfig.txt (que tModLoader lee con -config)
            if ($semilla !== '') {
                $startup = "sed -i -e '/^#*seed=/d' serverconfig.txt; echo 'seed=$semilla' >> serverconfig.txt; " . $startup;
            }
        }
        $imagen = imagenPara($tipo, $egg, $version);
        $info = ['mundo' => $mundo, 'semilla' => $semilla, 'maldad' => $maldad, 'dificultad' => (int) $dific, 'tamano' => (int) $tamano];
      }

        $mem = max(512, (int) ($o['ram'] ?? 2048));
        $disk = max(1024, (int) ($o['disco'] ?? 5120));
        $backups = !empty($o['backups']);

        $tmp = new Server(['node_id' => $alloc->node_id]);
        $tmp->setRelation('node', $alloc->node);
        ampliarNodo($tmp, $mem, $disk);

        $server = app(Pterodactyl\Services\Servers\ServerCreationService::class)->handle([
            'name' => $nombre, 'description' => "$juego ($tipo) creado con ThesknaepHost",
            'owner_id' => $user->id, 'node_id' => $alloc->node_id, 'allocation_id' => $alloc->id,
            'nest_id' => $egg->nest_id, 'egg_id' => $egg->id,
            'startup' => $startup, 'image' => $imagen,
            'memory' => $mem, 'swap' => 0, 'disk' => $disk, 'io' => 500, 'cpu' => 0, 'threads' => null,
            'oom_disabled' => true, 'database_limit' => 0, 'allocation_limit' => 0,
            'backup_limit' => $backups ? 3 : 1,
            'environment' => $env, 'start_on_completion' => true, 'skip_scripts' => false,
        ]);

        // Backups automaticos: cada 6 horas, guarda los 3 ultimos (los viejos se borran solos)
        if ($backups) {
            try {
                $next = Pterodactyl\Helpers\Utilities::getScheduleNextRunDate('0', '*/6', '*', '*', '*');
            } catch (Throwable $e) {
                $next = now()->addHours(6);
            }
            $sch = Schedule::create([
                'server_id' => $server->id, 'name' => 'Backup automatico',
                'cron_day_of_week' => '*', 'cron_month' => '*', 'cron_day_of_month' => '*',
                'cron_hour' => '*/6', 'cron_minute' => '0',
                'is_active' => true, 'is_processing' => false, 'only_when_online' => false, 'next_run_at' => $next,
            ]);
            Task::create([
                'schedule_id' => $sch->id, 'sequence_id' => 1, 'action' => 'backup', 'payload' => '',
                'time_offset' => 0, 'is_queued' => false, 'continue_on_failure' => false,
            ]);
        }

        // Acceso API: clave de cuenta para controlar tus servidores por la API de Pterodactyl
        $apiToken = null; $apiAviso = null;
        if (!empty($o['api'])) {
            try {
                $key = app(Pterodactyl\Services\Api\KeyCreationService::class)
                    ->setKeyType(ApiKey::TYPE_ACCOUNT)
                    ->handle(['user_id' => $user->id, 'memo' => "ThesknaepHost - $nombre", 'allowed_ips' => []]);
                $apiToken = $key->identifier . decrypt($key->token);
            } catch (Throwable $e) {
                $apiAviso = 'No se pudo crear la clave API automáticamente; créala en el panel: Account > API Credentials.';
            }
        }

        responder(array_merge([
            'ok' => true, 'id' => $server->id, 'uuid' => $server->uuid, 'short' => $server->uuidShort,
            'port' => $alloc->port, 'juego' => $juego, 'tipo' => $tipo, 'version' => $version, 'imagen' => $imagen,
            'api_token' => $apiToken, 'api_aviso' => $apiAviso,
            'memoria_total_servidores' => totalRam(),
        ], $info));
    }

    responder(['ok' => false, 'error' => "Comando desconocido: $cmd"], 1);
} catch (Throwable $e) {
    responder(['ok' => false, 'error' => $e->getMessage()], 1);
}
