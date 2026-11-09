# ThesknaepHost - actualizaciones desde GitHub.
# Al abrir la app se compara web\version.json con el de GitHub. Si hay una version nueva se avisa y,
# si la persona acepta, se descarga el proyecto, se reemplazan los archivos de la app y se vuelve a abrir.
# Los servidores, mundos y contraseñas no se tocan (viven en Linux y en %LOCALAPPDATA%\ThesknaepHost).
# Se carga desde ThesknaepHost.ps1.

$Repo        = 'Thesknaep/ThesknaepHost'
$VersionUrl  = "https://raw.githubusercontent.com/$Repo/main/web/version.json"
$ZipUrl      = "https://github.com/$Repo/archive/refs/heads/main.zip"
$script:AvisoVersion = $false

function VersionLocal {
    try { [IO.File]::ReadAllText((Join-Path $Raiz 'web\version.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { $null }
}
function EsMasNueva([string]$remota, [string]$local) {
    try { return ([version]$remota) -gt ([version]$local) } catch { return $false }
}

function BuscarActualizacion([bool]$manual = $false) {
    if ($manual) { Log 'Buscando actualizaciones...' }
    $script:BusquedaManual = $manual
    Async {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        try { (Invoke-WebRequest $A -UseBasicParsing -TimeoutSec 15 -Headers @{ 'Cache-Control' = 'no-cache' }).Content }
        catch { 'ERROR' }
    } {
        param($txt, $err)
        $manual = $script:BusquedaManual
        $rem = $null
        if ($txt -and $txt -ne 'ERROR') { try { $rem = $txt | ConvertFrom-Json } catch {} }
        if (-not $rem) {
            if ($manual) { Aviso 'No se pudo revisar si hay una versión nueva. Revisa tu conexión a internet e inténtalo de nuevo.' 'ACTUALIZACIONES' }
            return
        }
        $loc = VersionLocal
        $vLoc = if ($loc) { $loc.version } else { '0.0.0' }
        if (-not (EsMasNueva $rem.version $vLoc)) {
            if ($manual) { Aviso "Ya tienes la última versión ($vLoc)." 'ACTUALIZACIONES' }
            return
        }
        if ($script:AvisoVersion -and -not $manual) { return }
        $script:AvisoVersion = $true
        Notificar "NUEVA VERSIÓN $($rem.version)" 'Hay una actualización de ThesknaepHost lista para instalar.' ([TH.Pal]::Cyan) 7000
        $msg = "Hay una versión nueva de ThesknaepHost: $($rem.version) (tienes la $vLoc).`n`n$($rem.notas)`n`n" +
               "Tus servidores, mundos y contraseñas no se tocan. La app se cerrará y se abrirá sola en unos segundos."
        if ($rem.reparar) { $msg += "`n`nDespués tendrás que pulsar INSTALAR / REPARAR una vez." }
        if (Preguntar $msg 'ACTUALIZACIÓN' 'ACTUALIZAR AHORA' 'MÁS TARDE') { InstalarActualizacion $rem }
        else { Log 'Actualización pospuesta. Búscala en el icono junto al reloj → Buscar actualizaciones.' }
    } $VersionUrl
}

function InstalarActualizacion($rem) {
    Ocupar $true "Descargando la versión $($rem.version)..."
    Async {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $tmp = Join-Path $env:TEMP ('thesknaephost-act-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force $tmp | Out-Null
        try {
            $zip = Join-Path $tmp 'main.zip'
            Invoke-WebRequest $A.zip -OutFile $zip -UseBasicParsing -TimeoutSec 300
            Expand-Archive $zip (Join-Path $tmp 'x') -Force
            $src = Get-ChildItem (Join-Path $tmp 'x') -Directory | Select-Object -First 1
            # Solo se instala si de verdad es ThesknaepHost
            if (-not $src -or -not (Test-Path (Join-Path $src.FullName 'ThesknaepHost.ps1')) -or -not (Test-Path (Join-Path $src.FullName 'web\version.json'))) {
                throw 'El archivo descargado no es una versión válida de ThesknaepHost.'
            }
            Get-ChildItem $src.FullName -Force | Copy-Item -Destination $A.raiz -Recurse -Force
            'ok'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    } {
        param($r, $err)
        if ($err -or $r -ne 'ok') {
            Ocupar $false ''
            Aviso "No se pudo actualizar:`n$err`n`nVuelve a intentarlo más tarde desde el icono junto al reloj → Buscar actualizaciones." 'ACTUALIZACIÓN'
            return
        }
        if ($script:VersionNueva.reparar) {
            New-Item -ItemType Directory -Force $Base | Out-Null
            Set-Content (Join-Path $Base 'reparar-pendiente.txt') $script:VersionNueva.version -Encoding ASCII
        }
        Log 'Actualización instalada. Reabriendo ThesknaepHost...'
        # Se abre la version nueva cuando esta ya se cerro (solo puede haber una copia abierta)
        $bat = Join-Path $Raiz 'ThesknaepHost.bat'
        Start-Process cmd.exe -WindowStyle Hidden -ArgumentList '/c', "timeout /t 3 /nobreak >nul & call `"$bat`""
        $script:Saliendo = $true
        $f.Close()
    } @{ zip = $ZipUrl; raiz = $Raiz }
    $script:VersionNueva = $rem
}

# Despues de actualizar: si la version nueva trae arreglos de Linux, se pide INSTALAR / REPARAR una vez
function RevisarReparacionPendiente {
    $m = Join-Path $Base 'reparar-pendiente.txt'
    if (-not (Test-Path $m)) { return }
    Remove-Item $m -Force -ErrorAction SilentlyContinue
    Aviso "ThesknaepHost se actualizó. Esta versión trae arreglos para Linux.`n`nPulsa INSTALAR / REPARAR una vez (no borra tus servidores ni mundos)." 'ACTUALIZADO'
}
