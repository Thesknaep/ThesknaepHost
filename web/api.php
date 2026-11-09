<?php
// ThesknaepHost web - API para la interfaz del navegador.
// nginx solo escucha en 127.0.0.1:8090, asi que esto solo se puede usar desde este mismo equipo.
// Reutiliza linux/recursos.php (el mismo ayudante que usa la app de Windows).

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

const CONFIG = '/etc/thesknaephost/config';
const PANEL = 'http://127.0.0.1:8088';

function salir($d, int $code = 200) { http_response_code($code); echo json_encode($d, JSON_UNESCAPED_UNICODE); exit; }

// ---------------------------------------------------------------- seguridad: solo la propia interfaz puede dar ordenes
// 1) Host: solo 127.0.0.1 / localhost (bloquea el truco de "DNS rebinding" de paginas maliciosas)
$host = strtolower($_SERVER['HTTP_HOST'] ?? '');
if (!preg_match('/^(127\.0\.0\.1|localhost|\[::1\])(:\d+)?$/', $host)) salir(['ok' => false, 'error' => 'Acceso denegado'], 403);
// 2) Si el navegador dice de que pagina viene la peticion, tiene que ser esta misma
$origen = $_SERVER['HTTP_ORIGIN'] ?? '';
if ($origen !== '' && !preg_match('#^http://(127\.0\.0\.1|localhost|\[::1\])(:\d+)?$#i', $origen)) salir(['ok' => false, 'error' => 'Acceso denegado'], 403);
// 3) Cabecera propia: otra pagina web no puede enviarla sin permiso del navegador, y este servidor nunca lo da
if (($_SERVER['HTTP_X_THESKNAEPHOST'] ?? '') !== '1') salir(['ok' => false, 'error' => 'Acceso denegado'], 403);
// 4) Las ordenes (POST) solo como JSON
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST' && stripos($_SERVER['CONTENT_TYPE'] ?? '', 'application/json') !== 0) salir(['ok' => false, 'error' => 'Acceso denegado'], 403);

function rutaRecursos(): string {
    foreach ([__DIR__ . '/../recursos.php', __DIR__ . '/../linux/recursos.php'] as $r) if (is_file($r)) return realpath($r);
    salir(['ok' => false, 'error' => 'No se encuentra recursos.php'], 500);
}

// Ejecuta el ayudante (como www-data) y devuelve su linea JSON
function recursos(array $args, int $segundos = 120): array {
    $cmd = 'timeout ' . $segundos . ' php ' . escapeshellarg(rutaRecursos());
    foreach ($args as $a) $cmd .= ' ' . escapeshellarg((string) $a);
    $out = (string) shell_exec($cmd . ' 2>/dev/null');
    $json = null;
    foreach (explode("\n", $out) as $l) if (str_starts_with(trim($l), '{')) $json = trim($l);
    return $json ? (json_decode($json, true) ?? ['ok' => false, 'error' => 'Respuesta inválida']) : ['ok' => false, 'error' => 'El ayudante no respondió'];
}

function leerConfig(): array {
    $c = ['MODO' => null];
    if (is_readable(CONFIG)) foreach (file(CONFIG) as $l) if (preg_match('/^(\w+)=(.*)$/', trim($l), $m)) $c[$m[1]] = trim($m[2], "\"'");
    return $c;
}

function tailscale(): array {
    if (trim((string) shell_exec('command -v tailscale 2>/dev/null')) === '') return ['instalado' => false, 'estado' => 'NoInstalado'];
    $j = json_decode((string) shell_exec('timeout 8 tailscale status --json 2>/dev/null'), true);
    if (!$j) return ['instalado' => true, 'estado' => 'SinRespuesta'];
    $ip = null;
    foreach ($j['Self']['TailscaleIPs'] ?? [] as $x) if (preg_match('/^\d+\.\d+\.\d+\.\d+$/', $x)) { $ip = $x; break; }
    $equipos = [];
    foreach ($j['Peer'] ?? [] as $p) $equipos[] = ['nombre' => $p['HostName'] ?? '?', 'so' => $p['OS'] ?? '', 'linea' => (bool) ($p['Online'] ?? false)];
    return ['instalado' => true, 'estado' => $j['BackendState'] ?? '?', 'ip' => $ip,
            'nombre' => rtrim($j['Self']['DNSName'] ?? '', '.'), 'equipos' => $equipos];
}

function servicio(string $s): string { return trim((string) shell_exec('systemctl is-active ' . escapeshellarg($s) . ' 2>/dev/null')) ?: 'desconocido'; }

function cuerpo(): array { $b = json_decode(file_get_contents('php://input') ?: '{}', true); return is_array($b) ? $b : []; }

// ---------------------------------------------------------------- versiones (se piden desde el servidor y se guardan 1 h)
function bajar(string $url): ?string {
    $ctx = stream_context_create(['http' => ['header' => "User-Agent: ThesknaepHost\r\n", 'timeout' => 20]]);
    $r = @file_get_contents($url, false, $ctx);
    return $r === false ? null : $r;
}
function versiones(string $tipo): array {
    $cache = sys_get_temp_dir() . "/thesknaephost-versiones-$tipo.json";
    if (is_file($cache) && time() - filemtime($cache) < 3600) return json_decode(file_get_contents($cache), true);
    $out = [['v' => 'latest', 'label' => 'ÚLTIMA VERSIÓN (recomendada)']];
    switch ($tipo) {
        case 'vanilla':
            $html = bajar('https://terraria.wiki.gg/wiki/Server') ?? '';
            preg_match_all('/terraria-server-(\d+)\.zip/', $html, $m);
            foreach (array_unique($m[1]) as $n) if (preg_match('/^14[4-9]/', $n)) { $v = implode('.', str_split($n)); $out[] = ['v' => $v, 'label' => "TERRARIA $v"]; }
            break;
        case 'tshock':
            foreach (json_decode(bajar('https://api.github.com/repos/Pryaxis/TShock/releases?per_page=30') ?? '[]', true) ?: [] as $r) {
                if (!empty($r['prerelease']) || !preg_match('/^v[5-9]\./', $r['tag_name'] ?? '')) continue;
                $tv = '';
                foreach ($r['assets'] ?? [] as $a) if (preg_match('/for-Terraria-([\d.]+?)-/', $a['name'], $mm)) { $tv = $mm[1]; break; }
                $out[] = ['v' => $r['tag_name'], 'label' => "TSHOCK {$r['tag_name']}" . ($tv ? " · TERRARIA $tv" : '')];
            }
            break;
        case 'tmodloader':
            $i = 0;
            foreach (json_decode(bajar('https://api.github.com/repos/tModLoader/tModLoader/releases?per_page=30') ?? '[]', true) ?: [] as $r) {
                if (!empty($r['prerelease'])) continue;
                $out[] = ['v' => $r['tag_name'], 'label' => "TMODLOADER {$r['tag_name']}"];
                if (++$i >= 10) break;
            }
            break;
        case 'mc-vanilla':
            $i = 0;
            foreach (json_decode(bajar('https://piston-meta.mojang.com/mc/game/version_manifest_v2.json') ?? '{}', true)['versions'] ?? [] as $v) {
                if (($v['type'] ?? '') !== 'release') continue;
                $out[] = ['v' => $v['id'], 'label' => "MINECRAFT {$v['id']}"];
                if (++$i >= 30) break;
            }
            break;
        case 'mc-paper':
            $i = 0;
            foreach (json_decode(bajar('https://fill.papermc.io/v3/projects/paper') ?? '{}', true)['versions'] ?? [] as $grupo) {
                foreach ($grupo as $v) { if (str_contains($v, '-')) continue; $out[] = ['v' => $v, 'label' => "PAPER $v"]; if (++$i >= 30) break 2; }
            }
            break;
        case 'mc-forge':
            $vers = [];
            foreach (json_decode(bajar('https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json') ?? '{}', true)['promos'] ?? [] as $k => $fv) {
                [$mc, $clase] = array_pad(explode('-', $k, 2), 2, '');
                if (strlen($mc) > 9) continue;
                $vers[$mc][$clase] = $fv;
            }
            foreach (array_slice(array_reverse($vers, true), 0, 25, true) as $mc => $c) {
                $rec = $c['recommended'] ?? null;
                $out[] = ['v' => "$mc|" . ($rec ? 'recommended' : 'latest'), 'label' => "FORGE $mc · " . ($rec ?: ($c['latest'] ?? '')) . ($rec ? ' (recomendada)' : ' (última)')];
            }
            break;
        default:
            salir(['ok' => false, 'error' => 'Tipo desconocido'], 400);
    }
    if (count($out) > 1) @file_put_contents($cache, json_encode($out));
    return $out;
}

// ---------------------------------------------------------------- acciones
$a = $_GET['a'] ?? '';
switch ($a) {
    case 'sistema':
        $ips = array_values(array_filter(preg_split('/\s+/', trim((string) shell_exec('hostname -I 2>/dev/null'))),
            fn($ip) => preg_match('/^\d+\.\d+\.\d+\.\d+$/', $ip) && !preg_match('/^(127\.|172\.(1[6-9]|2\d|3[01])\.|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.)/', $ip)));
        $ramTotal = (int) trim((string) shell_exec("free -m | awk '/^Mem:/{print \$2}'"));
        $discoLibre = (int) trim((string) shell_exec("df -m --output=avail /var/lib 2>/dev/null | tail -1"));
        $panel = @file_get_contents(PANEL, false, stream_context_create(['http' => ['timeout' => 3]])) !== false;
        salir(['ok' => true, 'modo' => leerConfig()['MODO'], 'panel' => $panel, 'panelUrl' => PANEL,
               'servicios' => ['nginx' => servicio('nginx'), 'docker' => servicio('docker'), 'wings' => servicio('wings'), 'mariadb' => servicio('mariadb')],
               'ips' => $ips, 'ramMB' => $ramTotal, 'discoLibreMB' => $discoLibre, 'nucleos' => (int) trim((string) shell_exec('nproc')),
               'tailscale' => tailscale()]);

    case 'servidores':
        salir(recursos(['estado'], 60));

    case 'power':
        $b = cuerpo();
        if (!in_array($b['accion'] ?? '', ['start', 'stop', 'restart'], true)) salir(['ok' => false, 'error' => 'Acción inválida'], 400);
        salir(recursos(['power', (int) ($b['id'] ?? 0), $b['accion']], 30));

    case 'recursos':
        $b = cuerpo();
        salir(recursos(['set', (int) ($b['id'] ?? 0), (int) ($b['ram'] ?? 0), (int) ($b['disco'] ?? 0)], 60));

    case 'crear':
        $b = cuerpo();
        salir(recursos(['create', base64_encode(json_encode($b))], 240));

    case 'versiones':
        salir(['ok' => true, 'lista' => versiones((string) ($_GET['tipo'] ?? ''))]);

    case 'modo':
        $b = cuerpo();
        $modo = $b['modo'] ?? '';
        if (!in_array($modo, ['local', 'remoto'], true)) salir(['ok' => false, 'error' => 'Modo inválido'], 400);
        $c = leerConfig(); $c['MODO'] = $modo;
        $txt = ''; foreach ($c as $k => $v) if ($v !== null) $txt .= "$k=$v\n";
        if (@file_put_contents(CONFIG, $txt) === false) salir(['ok' => false, 'error' => 'No se pudo guardar la configuración (permisos de ' . CONFIG . ')'], 500);
        salir(['ok' => true, 'modo' => $modo]);

    default:
        salir(['ok' => false, 'error' => 'Acción desconocida'], 404);
}
