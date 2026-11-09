# ThesknaepHost - aplicacion de escritorio para tu servidor Pterodactyl local
# Todo lo lento (WSL, red, Linux) corre en segundo plano: la ventana nunca se congela.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$Raiz = $PSScriptRoot
try {
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $Raiz 'ui\Neon.cs'))) `
        -ReferencedAssemblies System.Windows.Forms, System.Drawing -ErrorAction Stop
} catch {
    [Windows.Forms.MessageBox]::Show("No se pudo cargar la interfaz:`n$($_.Exception.Message)", 'ThesknaepHost') | Out-Null
    return
}

# Identidad propia en Windows: la barra de tareas muestra el icono de ThesknaepHost (no el de PowerShell)
[TH.AppId]::Fijar('Thesknaep.ThesknaepHost')

# Una sola copia abierta: si ya hay una, se trae al frente y esta se cierra.
# (Abrir una segunda copia apagaba los servidores mientras alguien jugaba.)
$creado = $false
$script:Mutex = New-Object Threading.Mutex($true, 'Local\ThesknaepHost-App', [ref]$creado)
if (-not $creado) {
    # Ya hay una copia (quizas escondida en la bandeja): le pedimos que se muestre y esta se cierra
    try { $ev = [Threading.EventWaitHandle]::OpenExisting('Local\ThesknaepHost-Mostrar'); [void]$ev.Set(); $ev.Dispose() }
    catch { [void][TH.Win]::TraerAlFrente('ThesknaepHost') }
    return
}
$script:EvMostrar = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::AutoReset, 'Local\ThesknaepHost-Mostrar')

$Distro   = 'ThesknaepHost'
$Base     = Join-Path $env:LOCALAPPDATA 'ThesknaepHost'
$PanelUrl = 'http://127.0.0.1:8088'
$WslCfg   = Join-Path $env:USERPROFILE '.wslconfig'
# Icono de la aplicacion (ventana, barra de tareas) y de notificaciones (junto al reloj, avisos).
# Se busca la version mas nueva de cada uno; si falta, se usa el otro.
function BuscarIcono([string]$patron) { Get-ChildItem $Raiz -Filter $patron -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName }
$IconPath = BuscarIcono 'thesknaephost-app*.ico'
$IconBandejaPath = BuscarIcono 'thesknaephost-bandeja*.ico'
if (-not $IconPath) { $IconPath = BuscarIcono 'thesknaephost*.ico' }
if (-not $IconBandejaPath) { $IconBandejaPath = $IconPath }

# ------------------------------------------------------------------------------------------
# Funciones comunes: se cargan aqui y tambien en cada tarea de segundo plano
# ------------------------------------------------------------------------------------------
$FuncionesComunes = @'
$env:WSL_UTF8 = '1'

function WslInstalado {
    (Test-Path "$env:ProgramFiles\WSL\wsl.exe") -and [bool](Get-Service vmcompute -ErrorAction SilentlyContinue)
}
# Lee el registro en vez de llamar a wsl.exe (wsl.exe se queda esperando si WSL no esta instalado)
function Instalado {
    [bool](Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction SilentlyContinue |
        Where-Object { (Get-ItemProperty $_.PSPath).DistributionName -eq $Distro })
}
function Encendido {
    [bool](Get-CimInstance Win32_Process -Filter "Name='wsl.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*$Marca*" })
}
function PanelOk {
    try { Invoke-WebRequest $PanelUrl -UseBasicParsing -TimeoutSec 3 | Out-Null; $true } catch { $false }
}
function IpsLocales {
    @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.)' -and $_.PrefixOrigin -in 'Dhcp', 'Manual' } |
        Select-Object -ExpandProperty IPAddress)
}
# Ejecuta un programa sin ventana, sin teclado y con tiempo limite
function Ejecutar([string]$exe, [string]$argumentos, [int]$segundos = 20) {
    $psi = New-Object Diagnostics.ProcessStartInfo $exe, $argumentos
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.EnvironmentVariables['WSL_UTF8'] = '1'
    $p = [Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($segundos * 1000)) {
        try { $p.Kill() } catch {}
        return [pscustomobject]@{ code = -1; out = ''; err = 'tiempo agotado'; timeout = $true }
    }
    [pscustomobject]@{ code = $p.ExitCode; out = $o.Result; err = $e.Result; timeout = $false }
}
function Recursos([string[]]$params) {
    $php = (Join-Path $Raiz 'linux\recursos.php') -replace '\\', '/'
    $r = Ejecutar 'wsl.exe' "-d $Distro -u root -e wslpath -a `"$php`"" 20
    if ($r.code -ne 0) { return [pscustomobject]@{ ok = $false; error = 'Linux no responde.' } }
    $linux = $r.out.Trim()
    $r = Ejecutar 'wsl.exe' ("-d $Distro -u www-data -e php `"$linux`" " + ($params -join ' ')) 90
    if ($r.timeout) { return [pscustomobject]@{ ok = $false; error = 'Linux tardó demasiado en responder.' } }
    $linea = $r.out -split "`n" | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1
    if (-not $linea) { return [pscustomobject]@{ ok = $false; error = "Respuesta vacía. $($r.err)".Trim() } }
    $linea | ConvertFrom-Json
}
function LeerEstado {
    $w = WslInstalado
    $i = if ($w) { Instalado } else { $false }
    $on = if ($i) { Encendido } else { $false }
    # WSL instalado pero la Plataforma de Maquina Virtual aun no activa = falta reiniciar
    $reinicio = (-not $w) -and (Test-Path "$env:ProgramFiles\WSL\wsl.exe")
    # IP de Tailscale (acceso remoto), si esta instalado y conectado
    $ts = $null; $exeTs = "$env:ProgramFiles\Tailscale\tailscale.exe"
    if (Test-Path $exeTs) { $x = Ejecutar $exeTs 'ip -4' 5; if ($x.code -eq 0 -and $x.out) { $ts = ($x.out -split "`n")[0].Trim() } }
    [pscustomobject]@{ wsl = $w; reinicio = $reinicio; inst = $i; on = $on; web = $(if ($on) { PanelOk } else { $false }); ips = IpsLocales; tailscale = $ts }
}
function Arrancar {
    if (-not (Encendido)) {
        Start-Process wsl.exe -WindowStyle Hidden -ArgumentList "-d $Distro -u root -e bash -c `"exec -a $Marca sleep infinity`""
    }
    for ($n = 0; $n -lt 40 -and -not (PanelOk); $n++) { Start-Sleep -Seconds 2 }
    # Windows 10: reenviar los puertos de juego a la IP nueva de Linux (tarea creada por el instalador)
    if ([Environment]::OSVersion.Version.Build -lt 22621) { Ejecutar 'schtasks.exe' '/run /tn ThesknaepHost-Puertos' 15 | Out-Null }
}
function Apagar {
    Ejecutar 'wsl.exe' "--terminate $Distro" 30 | Out-Null
    Get-CimInstance Win32_Process -Filter "Name='wsl.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*$Marca*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}
'@

function Literal($s) { "'" + ($s -replace "'", "''") + "'" }
$Comun = "`$Distro = $(Literal $Distro); `$Base = $(Literal $Base); `$PanelUrl = $(Literal $PanelUrl); " +
         "`$Marca = 'thesknaephost-keepalive'; `$Raiz = $(Literal $Raiz)`n" + $FuncionesComunes
. ([scriptblock]::Create($Comun))

# Tareas en segundo plano
$script:Tareas = New-Object Collections.ArrayList
function Async([scriptblock]$trabajo, [scriptblock]$fin, $A = $null) {
    $ps = [PowerShell]::Create()
    [void]$ps.AddScript("param(`$A)`n" + $Comun + "`n" + $trabajo.ToString())
    [void]$ps.AddParameter('A', $A)
    [void]$script:Tareas.Add([pscustomobject]@{ ps = $ps; h = $ps.BeginInvoke(); fin = $fin })
}
function RevisarTareas {
    foreach ($t in @($script:Tareas)) {
        if (-not $t.h.IsCompleted) { continue }
        [void]$script:Tareas.Remove($t)
        $res = $null; $err = $null
        try { $res = $t.ps.EndInvoke($t.h) } catch { $err = $_.Exception.InnerException.Message; if (-not $err) { $err = $_.Exception.Message } }
        $t.ps.Dispose()
        $ultimo = if ($res -and $res.Count -gt 0) { $res[$res.Count - 1] } else { $null }
        try { & $t.fin $ultimo $err } catch { Log "ERROR: $($_.Exception.Message)" }
    }
}

# Limite de RAM que Windows deja usar a Linux (WSL). Por defecto: la mitad de la RAM del PC.
$RamPcMB = [int]((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)
function DiscoLibreGB {
    $letra = (Split-Path $env:LOCALAPPDATA -Qualifier).TrimEnd(':')
    [int]((Get-PSDrive $letra).Free / 1GB)
}
function WslMemoriaMB {
    if (Test-Path $WslCfg) {
        $m = Select-String -Path $WslCfg -Pattern '^\s*memory\s*=\s*(\d+)\s*(GB|MB)' | Select-Object -First 1
        if ($m) {
            $n = [int]$m.Matches[0].Groups[1].Value
            if ($m.Matches[0].Groups[2].Value -eq 'GB') { return $n * 1024 } else { return $n }
        }
    }
    [int]($RamPcMB / 2)
}
function FijarWslMemoriaGB([int]$gb) {
    $txt = if (Test-Path $WslCfg) { [IO.File]::ReadAllText($WslCfg) } else { '' }
    if ($txt -match '(?m)^\s*memory\s*=.*$') { $txt = $txt -replace '(?m)^\s*memory\s*=.*$', "memory=${gb}GB" }
    elseif ($txt -match '(?m)^\[wsl2\]') { $txt = $txt -replace '(?m)^\[wsl2\]', "[wsl2]`r`nmemory=${gb}GB" }
    else { $txt = $txt.TrimEnd() + "`r`n[wsl2]`r`nmemory=${gb}GB`r`n" }
    [IO.File]::WriteAllText($WslCfg, $txt.TrimStart())
}

# ------------------------------------------------------------------------------------------
# Interfaz
# ------------------------------------------------------------------------------------------
$P = [TH.Pal]
function Etiqueta($padre, $texto, $x, $y, $w, $h, $color, $font) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $texto; $l.ForeColor = $color; $l.Font = $font; $l.BackColor = [Drawing.Color]::Transparent
    $l.Location = New-Object Drawing.Point($x, $y); $l.Size = New-Object Drawing.Size($w, $h)
    $padre.Controls.Add($l); $l
}
function Boton($padre, $texto, $x, $y, $w, $h, $color, $relleno, $accion) {
    $b = New-Object TH.NeonButton
    $b.Text = $texto; $b.Accent = $color; $b.Filled = $relleno
    $b.Location = New-Object Drawing.Point($x, $y); $b.Size = New-Object Drawing.Size($w, $h)
    $b.Add_Click($accion)
    $padre.Controls.Add($b); $b
}
function Tarjeta($titulo, $codigo, $x, $y, $w, $h) {
    $p = New-Object TH.NeonPanel
    $p.Titulo = $titulo; $p.Codigo = $codigo
    $p.Location = New-Object Drawing.Point($x, $y); $p.Size = New-Object Drawing.Size($w, $h)
    $f.Controls.Add($p); $p
}
. (Join-Path $Raiz 'ui\Dialogos.ps1')
. (Join-Path $Raiz 'ui\Servidores.ps1')
. (Join-Path $Raiz 'ui\Remoto.ps1')
. (Join-Path $Raiz 'ui\Ayuda.ps1')
. (Join-Path $Raiz 'ui\Actualizar.ps1')

$f = New-Object TH.NeonForm
$f.Text = 'ThesknaepHost'
$f.Sub = '// GAME SERVER CONTROL  ::  PTERODACTYL CORE  ::  TERRARIA / MINECRAFT  ::  v' + $(if ($v = VersionLocal) { $v.version } else { '?' })
$f.ClientSize = New-Object Drawing.Size(960, 620)
$f.StartPosition = 'CenterScreen'
if ($IconPath -and (Test-Path $IconPath)) { try { $f.Icon = New-Object Drawing.Icon($IconPath) } catch {} }
$script:IconoBandeja = $f.Icon
if ($IconBandejaPath -and (Test-Path $IconBandejaPath)) { try { $script:IconoBandeja = New-Object Drawing.Icon($IconBandejaPath) } catch {} }

# Botones de ventana
$bMin = Boton $f '–' 862 14 40 32 $P::PinkSoft $false { $f.WindowState = 'Minimized' }
$bCer = Boton $f '×' 906 14 40 32 $P::Red $false { $f.Close() }
$bMin.Font = $P::F(15, [Drawing.FontStyle]::Bold); $bCer.Font = $P::F(17, [Drawing.FontStyle]::Bold)
$lBusy = Etiqueta $f '' 640 50 300 20 $P::Cyan ($P::Mono(9))
$lBusy.TextAlign = 'TopRight'

# --- SISTEMA
$tSis = Tarjeta 'SISTEMA' 'SYS.01' 24 112 430 220
$pulso = New-Object TH.Pulse
$pulso.Location = New-Object Drawing.Point(16, 52)
$tSis.Controls.Add($pulso)
$lGrande = Etiqueta $tSis 'INICIANDO…' 56 52 360 34 $P::Text ($P::F(18, [Drawing.FontStyle]::Bold))
$lInfo = Etiqueta $tSis '' 20 96 400 116 $P::PinkSoft ($P::Mono(10))

# --- CONTROL
$tCtl = Tarjeta 'CONTROL' 'CMD.02' 24 344 430 252
$botones = @()
$botones += Boton $tCtl 'INICIAR' 18 52 192 44 $P::Pink $true { Iniciar }
$botones += Boton $tCtl 'DETENER' 220 52 192 44 $P::Red $false { Detener }
$botones += Boton $tCtl 'PANEL WEB' 18 104 192 44 $P::Cyan $false { Start-Process $PanelUrl }
$botones += Boton $tCtl 'USUARIO Y CLAVE' 220 104 192 44 $P::Pink $false {
    $c = Join-Path $Base 'credenciales.txt'
    if (Test-Path $c) { Start-Process notepad.exe $c } else { Aviso 'Aún no existe. Termina la instalación primero.' }
}
$botones += Boton $tCtl 'INSTALAR / REPARAR' 18 156 192 44 $P::Pink $false {
    Log 'Abriendo instalador (pedirá permisos de administrador)...'
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$(Join-Path $Raiz 'Instalar.ps1')`""
}
$botones += Boton $tCtl 'ACTUALIZAR' 220 156 192 44 $P::Pink $false { Actualizar }
$botones += Boton $tCtl 'MIS SERVIDORES' 18 208 192 36 $P::Cyan $true { AbrirServidores }
$botones += Boton $tCtl 'ACCESO REMOTO' 220 208 192 36 $P::Cyan $true { AbrirRemoto }
$bAyuda = Boton $f '?  AYUDA' 726 14 130 32 $P::Cyan $false { AbrirAyuda }
$bAyuda.Font = $P::F(10, [Drawing.FontStyle]::Bold)

# --- RECURSOS
$tRec = Tarjeta 'RECURSOS DEL SERVIDOR' 'RES.03' 472 112 464 330
Etiqueta $tRec 'SERVIDOR' 20 50 200 18 $P::Dim ($P::F(9, [Drawing.FontStyle]::Bold)) | Out-Null
# Selector de servidor neon: < NOMBRE >
$script:ServIdx = 0
$bAnt = Boton $tRec '<' 20 66 40 36 $P::PinkSoft $false { CambiarServidor -1 }
$selServ = Boton $tRec '' 66 66 332 36 $P::PinkSoft $false { CambiarServidor 1 }
$bSig = Boton $tRec '>' 404 66 40 36 $P::PinkSoft $false { CambiarServidor 1 }
$selServ.Font = $P::F(10, [Drawing.FontStyle]::Regular)

Etiqueta $tRec 'MEMORIA RAM' 20 116 200 20 $P::Dim ($P::F(9, [Drawing.FontStyle]::Bold)) | Out-Null
$lRam = Etiqueta $tRec '' 244 106 200 34 $P::Pink ($P::F(20, [Drawing.FontStyle]::Bold))
$lRam.TextAlign = 'TopRight'
$slRam = New-Object TH.NeonSlider
$slRam.Numeros = $true; $slRam.Divisor = 2
$slRam.Location = New-Object Drawing.Point(14, 138); $slRam.Size = New-Object Drawing.Size(436, 54)
# De 1 GB hasta TODA la RAM del PC (pasos de 0,5 GB): quien tenga mas RAM puede usarla entera
$slRam.Minimum = 2; $slRam.Maximum = [Math]::Max(4, [int][Math]::Floor($RamPcMB / 512)); $slRam.Value = 4
$tRec.Controls.Add($slRam)
$lRamInfo = Etiqueta $tRec '' 20 194 424 18 $P::Dim ($P::Mono(8.5))

Etiqueta $tRec 'ALMACENAMIENTO' 20 226 200 20 $P::Dim ($P::F(9, [Drawing.FontStyle]::Bold)) | Out-Null
$lDisco = Etiqueta $tRec '' 244 216 200 34 $P::Cyan ($P::F(20, [Drawing.FontStyle]::Bold))
$lDisco.TextAlign = 'TopRight'
$slDisco = New-Object TH.NeonSlider
$slDisco.Accent = $P::Cyan
$slDisco.Numeros = $true
$slDisco.Location = New-Object Drawing.Point(14, 248); $slDisco.Size = New-Object Drawing.Size(436, 54)
$slDisco.Minimum = 1; $slDisco.Maximum = [Math]::Max(2, (DiscoLibreGB) - 5); $slDisco.Value = 5
$tRec.Controls.Add($slDisco)
$lDiscoInfo = Etiqueta $tRec '' 20 304 424 18 $P::Dim ($P::Mono(8.5))

function MostrarValores {
    $lRam.Text = ('{0:0.0} GB' -f ($slRam.Value / 2))
    $lDisco.Text = "$($slDisco.Value) GB"
}
$slRam.Add_ValueChanged({ MostrarValores })
$slDisco.Add_ValueChanged({ MostrarValores })
function InfoPc {
    $lRamInfo.Text   = ('PC {0:0.0} GB // LINUX {1:0.0} GB // TERRARIA 1-2 · MINECRAFT 3-6' -f ($RamPcMB / 1024), ((WslMemoriaMB) / 1024))
    $lDiscoInfo.Text = "LIBRE EN DISCO: $(DiscoLibreGB) GB  //  RECOMENDADO: 5 GB"
}

$btnCrear    = Boton $f '+ CREAR SERVIDOR' 472 452 152 46 $P::Pink $false { CrearServidor }
$btnArchivos = Boton $f 'ARCHIVOS' 630 452 150 46 $P::Cyan $false { Archivos }
$btnAplicar  = Boton $f 'APLICAR' 786 452 150 46 $P::Pink $true { Aplicar }

# --- REGISTRO
$tLog = Tarjeta 'REGISTRO' 'LOG.04' 472 508 464 88
$lLog = Etiqueta $tLog '' 18 44 430 40 $P::Cyan ($P::Mono(8.5))
$script:LogLines = New-Object Collections.Generic.List[string]
function Log($m) {
    $script:LogLines.Add(('[{0:HH:mm:ss}] {1}' -f (Get-Date), $m))
    while ($script:LogLines.Count -gt 3) { $script:LogLines.RemoveAt(0) }
    $lLog.Text = $script:LogLines -join "`n"
}
function Aviso([string]$m, [string]$titulo = 'AVISO') { [void](DialogoNeon $titulo $m @('ACEPTAR')) }
# Notificacion neon sobre el reloj (clic = abrir la app)
function Notificar([string]$titulo, [string]$mensaje, $acento = $null, [int]$ms = 5000) {
    if (-not $acento) { $acento = [TH.Pal]::Pink }
    [TH.NeonToast]::Mostrar($titulo, $mensaje, $acento, $script:IconoBandeja, $ms, [Action]{ MostrarVentana })
}

# ------------------------------------------------------------------------------------------
# Logica
# ------------------------------------------------------------------------------------------
$script:Ocupado = $false
$script:Servidores = @()
$script:Estado = $null
function Ocupar([bool]$si, [string]$txt) {
    $script:Ocupado = $si
    foreach ($b in $botones) { $b.Enabled = -not $si }
    $slRam.Enabled = -not $si; $slDisco.Enabled = -not $si
    foreach ($b in $bAnt, $bSig) { $b.Enabled = (-not $si) -and $script:Servidores.Count -gt 1 }
    $selServ.Enabled = -not $si
    $btnAplicar.Enabled = (-not $si) -and $script:Servidores.Count -gt 0
    $btnArchivos.Enabled = (-not $si) -and $script:Servidores.Count -gt 0
    $btnCrear.Enabled = -not $si
    $script:TextoOcupado = $txt
    if (-not $si) { $lBusy.Text = '' }
    if ($txt) { Log $txt }
}

function MostrarEstado($e) {
    $script:Estado = $e
    if (-not $e) { return }
    if ($script:Bandeja) {
        $script:Bandeja.Text = if ($e.web) { 'ThesknaepHost · en línea' } elseif ($e.on) { 'ThesknaepHost · arrancando' } else { 'ThesknaepHost · Linux apagado' }
    }
    if ($e.reinicio) {
        $pulso.Accent = $P::Amber; $lGrande.ForeColor = $P::Amber; $lGrande.Text = 'REINICIA EL PC'
        $lInfo.Text = "WSL ya está instalado: falta reiniciar para`nactivar la Plataforma de Máquina Virtual.`n`nAl volver a entrar, la instalación sigue sola.`n(Si no se abre, pulsa INSTALAR / REPARAR.)"
        return
    }
    if (-not $e.wsl) {
        $pulso.Accent = $P::Amber; $lGrande.ForeColor = $P::Amber; $lGrande.Text = 'WSL NO INSTALADO'
        $lInfo.Text = "Pulsa INSTALAR / REPARAR.`nInstalará WSL y luego pedirá reiniciar el PC.`nDespués vuelve a pulsar INSTALAR."
        return
    }
    if (-not $e.inst) {
        $pulso.Accent = $P::Amber; $lGrande.ForeColor = $P::Amber; $lGrande.Text = 'NO INSTALADO'
        $lInfo.Text = "Pulsa INSTALAR / REPARAR.`nLa primera vez tarda 10-20 minutos."
        return
    }
    $ips = if ($e.ips) { ($e.ips -join ', ') } else { 'sin red' }
    if ($e.web) { $pulso.Accent = $P::Green; $lGrande.ForeColor = $P::Green; $lGrande.Text = 'EN LÍNEA' }
    elseif ($e.on) { $pulso.Accent = $P::Amber; $lGrande.ForeColor = $P::Amber; $lGrande.Text = 'ARRANCANDO…' }
    else { $pulso.Accent = $P::Red; $lGrande.ForeColor = $P::Red; $lGrande.Text = 'APAGADO' }
    $lInfo.Text = "LINUX     :: $(if ($e.on) {'ENCENDIDO'} else {'APAGADO'})`n" +
                  "PANEL     :: $(if ($e.web) {$PanelUrl} else {'sin respuesta'})`n" +
                  "TU IP     :: $ips`n" +
                  "REMOTO    :: $(if ($script:Modo -ne 'remoto') { 'modo LOCAL (solo tu red)' } elseif ($e.tailscale) { $e.tailscale + ' (Tailscale)' } else { '¡Tailscale desconectado!' })`n" +
                  "TERRARIA  :: puerto 7777`n" +
                  "MINECRAFT :: puerto 25565"
}

function MostrarServidor {
    $n = $script:Servidores.Count
    if ($n -eq 0) { return }
    $s = $script:Servidores[$script:ServIdx]
    $tipo = $NombreTipo[[string]$s.tipo]
    if (-not $tipo) { $tipo = $s.egg }
    $selServ.Text = "$($s.name)  ::  $tipo  ::  :$($s.port)" + $(if ($n -gt 1) { "   [$($script:ServIdx + 1)/$n]" } else { '' })
    $slRam.Value = [int][Math]::Round($s.memory / 512)
    $slDisco.Value = [int][Math]::Ceiling($s.disk / 1024)
    MostrarValores
}
function CambiarServidor([int]$paso) {
    $n = $script:Servidores.Count
    if ($n -lt 2) { return }
    $script:ServIdx = ($script:ServIdx + $paso + $n) % $n
    MostrarServidor
}
function LlenarServidores($r) {
    $script:Servidores = @(); $script:ServIdx = 0
    if (-not $r) { $selServ.Text = 'PULSA INICIAR PARA VER TUS SERVIDORES' }
    elseif (-not $r.ok) { $selServ.Text = 'ERROR AL LEER SERVIDORES'; Log "Recursos: $($r.error)" }
    else {
        $script:Servidores = @($r.servers)
        if ($script:Servidores.Count -eq 0) { $selServ.Text = 'SIN SERVIDORES: CRÉALOS EN EL PANEL WEB' }
        else { MostrarServidor }
    }
    foreach ($b in $bAnt, $bSig) { $b.Enabled = (-not $script:Ocupado) -and $script:Servidores.Count -gt 1 }
    $btnAplicar.Enabled = (-not $script:Ocupado) -and $script:Servidores.Count -gt 0
    $btnArchivos.Enabled = (-not $script:Ocupado) -and $script:Servidores.Count -gt 0
}

# $alAbrir = $true solo al abrir la app: si quedaron servidores encendidos, se apagan (guardando el mundo)
function Actualizar([bool]$alAbrir = $false) {
    Ocupar $true $(if ($alAbrir) { 'Leyendo estado (los servidores empiezan apagados)...' } else { 'Leyendo estado...' })
    Async {
        $e = LeerEstado
        # Arregla permisos de archivos que hayas copiado con el Explorador
        if ($e.on) { Ejecutar 'wsl.exe' "-d $Distro -u root -e chown -R pterodactyl:pterodactyl /var/lib/pterodactyl/volumes" 60 | Out-Null }
        $encendidos = @()
        if ($A -and $e.on -and $e.web) {
            $st = Recursos @('estado')
            if ($st.ok) { $encendidos = @($st.servers | Where-Object { $_.estado -in 'running', 'starting' } | ForEach-Object { $_.name }) }
        }
        $list = if ($e.on -and $e.web) { Recursos @('list') } else { $null }
        [pscustomobject]@{ e = $e; list = $list; encendidos = $encendidos; inicio = [bool]$A }
    } {
        param($r, $err)
        if ($err) { Log "ERROR: $err" }
        if ($r) { MostrarEstado $r.e; LlenarServidores $r.list }
        Ocupar $false $(if ($r -and $r.e.web) { 'Sistema en línea.' } else { 'Estado actualizado.' })
        if ($r -and $r.inicio -and @($r.encendidos).Count -gt 0) {
            $nombres = @($r.encendidos) -join ', '
            $apagar = Preguntar "Estos servidores quedaron encendidos: $nombres`n`n¿Apagarlos ahora? Se guarda el mundo. Si alguien está jugando, se desconectará." `
                'ENCENDIDOS' 'APAGAR' 'DEJARLOS' $true
            if ($apagar) {
                Ocupar $true 'Apagando servidores (guardando el mundo)...'
                Async { Recursos @('apagar-todos') } {
                    param($x, $err2)
                    Ocupar $false $(if ($x -and $x.ok) { "Apagados: $(@($x.apagados) -join ', ')" } else { "No se pudieron apagar: $err2" })
                    RefrescarServidores
                }
            } else { Log "Se dejaron encendidos: $nombres" }
        }
    } $alAbrir
}

function Iniciar {
    if ($script:Estado -and -not $script:Estado.inst) { Aviso 'Primero pulsa INSTALAR / REPARAR.'; return }
    Ocupar $true 'Encendiendo Linux, Docker y Pterodactyl (hasta ~1 min)...'
    $lGrande.Text = 'ARRANCANDO…'; $lGrande.ForeColor = $P::Amber; $pulso.Accent = $P::Amber
    Async { Arrancar; $e = LeerEstado
            $rep = if ($e.web) { Recursos @('reparar') } else { $null }     # servidores que quedaron vacios por una instalacion cortada
            $list = if ($e.web) { Recursos @('list') } else { $null }; [pscustomobject]@{ e = $e; list = $list; rep = $rep } } {
        param($r, $err)
        if ($err) { Log "ERROR: $err" }
        if ($r) { MostrarEstado $r.e; LlenarServidores $r.list }
        if ($r -and $r.rep -and @($r.rep.reparados).Count) {
            $nombres = @($r.rep.reparados) -join ', '
            Log "Reinstalando servidores que habían quedado vacíos: $nombres"
            Notificar 'REPARANDO SERVIDORES' "$nombres quedó vacío por una instalación cortada. Se está reinstalando (1-3 min)." ([TH.Pal]::Amber) 7000
        }
        Ocupar $false $(if ($r -and $r.e.web) { 'Listo: panel en línea.' } else { 'El panel no respondió. Prueba ACTUALIZAR o INSTALAR / REPARAR.' })
    }
}

function Detener {
    Ocupar $true 'Apagando...'
    Async { Apagar; LeerEstado } {
        param($e, $err)
        if ($err) { Log "ERROR: $err" }
        MostrarEstado $e; LlenarServidores $null
        Ocupar $false 'Apagado.'
    }
}

function Aplicar {
    $i = $script:ServIdx
    if ($i -lt 0 -or $i -ge $script:Servidores.Count) { return }
    $s = $script:Servidores[$i]
    $datos = @{ id = $s.id; nombre = $s.name; ram = [int]($slRam.Value * 512); disco = [int]($slDisco.Value * 1024) }
    Ocupar $true "Aplicando a $($s.name): $('{0:0.0}' -f ($datos.ram / 1024)) GB RAM, $($slDisco.Value) GB disco..."
    Async { $r = Recursos @('set', "$($A.id)", "$($A.ram)", "$($A.disco)"); [pscustomobject]@{ r = $r; d = $A } } {
        param($x, $err)
        Ocupar $false $null
        if ($err -or -not $x -or -not $x.r.ok) { $m = if ($err) { $err } else { $x.r.error }; Log "ERROR: $m"; Aviso "No se pudo aplicar:`n$m"; return }
        $d = $x.d; $r = $x.r
        Log "$($d.nombre): $('{0:0.0}' -f ($d.ram / 1024)) GB RAM / $($d.disco / 1024) GB disco."
        if ($r.aviso) { Log $r.aviso }
        if (-not (RevisarMemoriaWsl $r.memoria_total_servidores)) {
            Aviso "Listo: $($d.nombre) tiene ahora $('{0:0.0}' -f ($d.ram / 1024)) GB de RAM y $($d.disco / 1024) GB de almacenamiento.`nSe aplica al momento; si el juego no lo nota, reinícialo en el panel."
        }
    }
}

# Si la RAM de todos los servidores no cabe en lo que Windows deja usar a Linux, sube el limite.
# Devuelve $true si tuvo que hacer algo.
function RevisarMemoriaWsl([int]$totalServidoresMB) {
    $necesarioGB = [int][Math]::Ceiling(($totalServidoresMB + 2048) / 1024)
    if ($necesarioGB * 1024 -le (WslMemoriaMB)) { return $false }
    $nuevo = [Math]::Min($necesarioGB, [int][Math]::Floor($RamPcMB / 1024))   # Linux puede usar hasta toda la RAM del PC
    FijarWslMemoriaGB $nuevo
    InfoPc
    $reiniciar = Preguntar "Tus servidores necesitan que Linux pueda usar $nuevo GB de RAM.`n`nHay que reiniciar WSL: tus servidores se apagarán cerca de 1 minuto (y cualquier otra distro WSL abierta).`nSi un servidor se está instalando, primero se espera a que termine." `
        'MEMORIA' 'REINICIAR' 'MÁS TARDE'
    if ($reiniciar) {
        Ocupar $true 'Esperando a que terminen las instalaciones y reiniciando WSL con más memoria...'
        Async {
            # Nunca apagar Linux mientras un servidor descarga el juego: la instalacion quedaria cortada y vacia
            for ($n = 0; $n -lt 120; $n++) {
                $est = Recursos @('estado')
                if (-not $est.ok -or -not @($est.servers | Where-Object { $_.estado -eq 'instalando' }).Count) { break }
                Start-Sleep -Seconds 10
            }
            Apagar; Ejecutar 'wsl.exe' '--shutdown' 60 | Out-Null; Start-Sleep -Seconds 3; Arrancar; Recursos @('reparar') | Out-Null; $e = LeerEstado
                [pscustomobject]@{ e = $e; list = $(if ($e.web) { Recursos @('list') } else { $null }) } } {
            param($r2, $err2)
            if ($r2) { MostrarEstado $r2.e; LlenarServidores $r2.list }
            Ocupar $false 'WSL reiniciado. Enciende tu servidor en el panel si no arrancó solo.'
        }
    } else { Log 'Memoria guardada: se aplicará la próxima vez que pulses DETENER e INICIAR.' }
    $true
}

function ServidorActual {
    if ($script:ServIdx -ge 0 -and $script:ServIdx -lt $script:Servidores.Count) { $script:Servidores[$script:ServIdx] }
}

# --- Crear servidor (Vanilla / TShock / tModLoader + extras)
function CrearServidor {
    if (-not ($script:Estado -and $script:Estado.web)) { Aviso 'Pulsa INICIAR primero: el panel tiene que estar en línea para crear servidores.'; return }
    $o = DialogoCrear
    if (-not $o) { return }
    $json = ConvertTo-Json $o -Compress
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    Ocupar $true "Creando servidor $($o.tipo.ToUpper()) '$($o.nombre)'..."
    Async { $r = Recursos @('create', $A); $list = Recursos @('list'); [pscustomobject]@{ r = $r; list = $list } } {
        param($x, $err)
        Ocupar $false $null
        if ($err -or -not $x -or -not $x.r.ok) { $m = if ($err) { $err } else { $x.r.error }; Log "ERROR: $m"; Aviso "No se pudo crear el servidor:`n$m"; return }
        $r = $x.r
        LlenarServidores $x.list
        RefrescarServidores
        $idx = [array]::IndexOf(@($script:Servidores | ForEach-Object { $_.id }), $r.id)
        if ($idx -ge 0) { $script:ServIdx = $idx; MostrarServidor }
        Log "Servidor creado ($($r.tipo) $($r.version)) en el puerto $($r.port). Instalando el juego..."
        $extra = ''
        if ($r.api_token) {
            New-Item -ItemType Directory -Force $Base | Out-Null
            $archivo = Join-Path $Base 'api-key.txt'
            Add-Content -Path $archivo -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm')  $($r.tipo)  $($r.short)  $($r.api_token)" -Encoding UTF8
            $extra += "`n`nACCESO API: tu clave quedó guardada en $archivo"
        }
        if ($r.api_aviso) { $extra += "`n`n$($r.api_aviso)" }
        $sinReinicio = -not (RevisarMemoriaWsl $r.memoria_total_servidores)
        if ($sinReinicio -and $r.juego -eq 'Minecraft') {
            $modo = @{ survival = 'Supervivencia'; creative = 'Creativo'; adventure = 'Aventura'; hardcore = 'Hardcore' }[[string]$r.modo]
            $dif = @{ peaceful = 'Pacífico'; easy = 'Fácil'; normal = 'Normal'; hard = 'Difícil' }[[string]$r.dif_mc]
            $ter = @{ normal = 'Normal'; flat = 'Plano'; large_biomes = 'Biomas grandes'; amplified = 'Amplificado' }[[string]$r.tipo_mundo]
            $sem = if ($r.semilla) { $r.semilla } else { 'aleatoria' }
            Aviso ("Servidor de Minecraft creado en el puerto $($r.port) (versión $($r.version), $($r.java -replace 'java_', 'Java ')).`n`n" +
                   "Mundo '$($r.mundo)': $modo · $dif · terreno $ter · semilla $sem`n`n" +
                   "Ahora descarga Minecraft y genera el mundo (2-6 minutos): mira la consola en el PANEL WEB.`n" +
                   "Tus amigos entran con Minecraft Java a tu IP, puerto $($r.port).$extra")
        }
        elseif ($sinReinicio) {
            $tam = @{ 1 = 'Pequeño'; 2 = 'Mediano'; 3 = 'Grande' }[[int]$r.tamano]
            $dif = @{ 0 = 'Clásico'; 1 = 'Experto'; 2 = 'Maestro'; 3 = 'Viaje' }[[int]$r.dificultad]
            $mal = @{ random = 'Aleatoria'; corrupt = 'Corrupción'; crimson = 'Carmesí' }[[string]$r.maldad]
            $sem = if ($r.semilla) { $r.semilla } else { 'aleatoria' }
            Aviso ("Servidor creado en el puerto $($r.port).`n`n" +
                   "Mundo '$($r.mundo)': $tam · $dif · maldad $mal · semilla $sem`n`n" +
                   "Ahora descarga el juego y genera el mundo (3-8 minutos). En la consola del PANEL WEB verás " +
                   "'Creating world - Seed: ..., Evil: ..., Difficulty: ...' con los valores reales.$extra")
        }
    } $b64
}

# --- Archivos: carpeta, mundos (.wld), plugins (.dll) y mods (.tmod)
function Archivos {
    $s = ServidorActual
    if (-not $s) { return }
    if (-not ($script:Estado -and $script:Estado.on)) { Aviso 'Pulsa INICIAR primero.'; return }
    $o = DialogoArchivos $s
    if (-not $o) { return }
    $raizUnc = "\\wsl.localhost\$Distro\var\lib\pterodactyl\volumes\$($s.uuid)"
    if ($o.accion -eq 'carpeta') {
        if (Test-Path $raizUnc) { Start-Process explorer.exe $raizUnc }
        else { Aviso 'La carpeta aún no existe. Espera a que el servidor termine de instalarse.' }
        return
    }
    $datos = @{ accion = $o.accion; archivos = $o.archivos; principal = $o.principal; raiz = $raizUnc
                tipo = $s.tipo; id = $s.id; uuid = $s.uuid }
    Ocupar $true "Subiendo $($o.archivos.Count) archivo(s) a $($s.name)..."
    Async {
        if (-not (Test-Path $A.raiz)) { throw 'No encuentro la carpeta del servidor. ¿Terminó de instalarse?' }
        $msg = @()
        switch ($A.accion) {
            'mundo' {
                $destino = if ($A.tipo -eq 'tshock') { $A.raiz } else { Join-Path $A.raiz 'saves\Worlds' }
                New-Item -ItemType Directory -Force $destino | Out-Null
                $origen = $A.archivos[0]
                $nombre = ([IO.Path]::GetFileNameWithoutExtension($origen) -replace '[^A-Za-z0-9_-]', '')
                if (-not $nombre) { $nombre = 'Mundo' }
                $nombre = $nombre.Substring(0, [Math]::Min(20, $nombre.Length))
                Copy-Item $origen (Join-Path $destino "$nombre.wld") -Force
                $twld = [IO.Path]::ChangeExtension($origen, '.twld')   # datos de mods (tModLoader)
                if (Test-Path $twld) { Copy-Item $twld (Join-Path $destino "$nombre.twld") -Force }
                $msg += "Mundo subido como $nombre.wld"
                if ($A.principal) {
                    $b = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($nombre))
                    $r = Recursos @('setvar', "$($A.id)", 'WORLD_NAME', $b)
                    $msg += $(if ($r.ok) { "Ahora es el mundo principal: reinicia el servidor para cargarlo." } else { "No se pudo marcar como principal: $($r.error)" })
                }
            }
            'plugin' {
                $destino = Join-Path $A.raiz 'ServerPlugins'
                New-Item -ItemType Directory -Force $destino | Out-Null
                foreach ($archivo in $A.archivos) { Copy-Item $archivo $destino -Force }
                $msg += "$($A.archivos.Count) plugin(s) en ServerPlugins. Reinicia el servidor para cargarlos."
            }
            'mod' {
                $destino = Join-Path $A.raiz 'mods'
                New-Item -ItemType Directory -Force $destino | Out-Null
                foreach ($archivo in $A.archivos) { Copy-Item $archivo $destino -Force }
                # tModLoader solo carga los mods listados en enabled.json
                $ej = Join-Path $destino 'enabled.json'
                $lista = @()
                if (Test-Path $ej) { try { $lista = @(Get-Content $ej -Raw | ConvertFrom-Json) } catch {} }
                foreach ($archivo in $A.archivos) { $lista += [IO.Path]::GetFileNameWithoutExtension($archivo) }
                $lista = @($lista | Where-Object { $_ } | Select-Object -Unique)
                [IO.File]::WriteAllText($ej, '[' + (($lista | ForEach-Object { '"' + $_ + '"' }) -join ', ') + ']')
                $msg += "$($A.archivos.Count) mod(s) activados. Reinicia el servidor para cargarlos."
            }
            'mundo-mc' {
                # El mundo de Minecraft es una carpeta (con level.dat): llega en .zip y va a la carpeta level-name
                $props = Join-Path $A.raiz 'server.properties'
                $nivel = 'world'
                if (Test-Path $props) {
                    $l = Select-String -Path $props -Pattern '^level-name=(.+)$' | Select-Object -First 1
                    if ($l) { $nivel = $l.Matches[0].Groups[1].Value.Trim() }
                }
                $tmp = Join-Path $env:TEMP ("thesknaephost-mundo-" + [guid]::NewGuid().ToString('N'))
                Expand-Archive -LiteralPath $A.archivos[0] -DestinationPath $tmp -Force
                $dat = Get-ChildItem $tmp -Recurse -Filter 'level.dat' | Sort-Object { $_.FullName.Length } | Select-Object -First 1
                if (-not $dat) { Remove-Item $tmp -Recurse -Force; throw 'El .zip no tiene un mundo de Minecraft (falta level.dat).' }
                $destino = Join-Path $A.raiz $nivel
                if (Test-Path $destino) {
                    $viejo = "$nivel-anterior-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                    Rename-Item $destino $viejo
                    $msg += "El mundo anterior quedó guardado como '$viejo'."
                }
                Copy-Item $dat.DirectoryName $destino -Recurse -Force
                Remove-Item $tmp -Recurse -Force
                $msg = @("Mundo copiado en '$nivel'. Inicia el servidor para jugarlo.") + $msg
            }
            'plugin-mc' {
                $destino = Join-Path $A.raiz 'plugins'
                New-Item -ItemType Directory -Force $destino | Out-Null
                foreach ($archivo in $A.archivos) { Copy-Item $archivo $destino -Force }
                $msg += "$($A.archivos.Count) plugin(s) en plugins. Reinicia el servidor para cargarlos."
            }
            'mod-mc' {
                $destino = Join-Path $A.raiz 'mods'
                New-Item -ItemType Directory -Force $destino | Out-Null
                foreach ($archivo in $A.archivos) { Copy-Item $archivo $destino -Force }
                $msg += "$($A.archivos.Count) mod(s) en mods. Reinicia el servidor. Tus amigos necesitan los mismos mods."
            }
        }
        Ejecutar 'wsl.exe' "-d $Distro -u root -e chown -R pterodactyl:pterodactyl /var/lib/pterodactyl/volumes/$($A.uuid)" 60 | Out-Null
        $msg -join "`n"
    } {
        param($m, $err)
        Ocupar $false $null
        if ($err) { Log "ERROR: $err"; Aviso "No se pudo subir:`n$err"; return }
        Log ($m -split "`n")[0]
        Aviso $m
        Actualizar
    } $datos
}

# Animacion + revision de tareas (cada 40 ms)
$spin = '|/-\'
# La animacion la hace la propia ventana, sincronizada con los Hz del monitor (ver ui\Neon.cs).
# Este temporizador solo revisa las tareas de segundo plano y el indicador PROCESANDO: no dibuja nada.
$f.Animados.Add($pulso)
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 100
$script:Giro = 0
$timer.Add_Tick({
    if ($script:Ocupado) { $script:Giro++; $lBusy.Text = "$($spin[$script:Giro % $spin.Length])  PROCESANDO" }
    if ($script:EvMostrar.WaitOne(0)) { MostrarVentana }
    RevisarTareas
})

$f.Add_Shown({
    MostrarValores; InfoPc; LlenarServidores $null
    Log 'ThesknaepHost listo.'
    $timer.Start()
    Actualizar $true
    # Modo de uso: se pregunta la primera vez; en modo REMOTO se exige Tailscale
    $script:Modo = LeerModo
    if (-not $script:Modo) { PreguntarModo } else { Log "Modo de uso: $($script:Modo.ToUpper())"; RevisarModoRemoto }
    RevisarReparacionPendiente
    BuscarActualizacion
})
# ------------------------------------------------------------------------------------------
# Icono en la bandeja (junto al reloj, en la flechita): la app sigue activa aunque cierres la ventana
# ------------------------------------------------------------------------------------------
$script:Saliendo = $false
$script:AvisoBandeja = $false
$script:Bandeja = New-Object Windows.Forms.NotifyIcon
$script:Bandeja.Icon = if ($script:IconoBandeja) { $script:IconoBandeja } else { [Drawing.SystemIcons]::Application }
$script:Bandeja.Text = 'ThesknaepHost'
$menu = New-Object Windows.Forms.ContextMenuStrip
$menu.ShowImageMargin = $false
$menu.Renderer = New-Object TH.NeonMenuRenderer
$menu.Font = $P::F(10.5, [Drawing.FontStyle]::Regular)
$menu.Padding = New-Object Windows.Forms.Padding(2, 6, 2, 6)
function ItemMenu($texto, $color, $accion, [bool]$negrita = $false) {
    $it = New-Object Windows.Forms.ToolStripMenuItem($texto)
    $it.Tag = $color
    $it.Padding = New-Object Windows.Forms.Padding(4, 6, 24, 6)
    if ($negrita) { $it.Font = $P::F(10.5, [Drawing.FontStyle]::Bold) }
    $it.Add_Click($accion)
    [void]$menu.Items.Add($it)
}
ItemMenu '▸  ABRIR THESKNAEPHOST' ($P::PinkSoft) { MostrarVentana } $true
ItemMenu '    Mis servidores' ($P::Text) { MostrarVentana; AbrirServidores }
ItemMenu '    Acceso remoto' ($P::Cyan) { MostrarVentana; AbrirRemoto }
ItemMenu '    Panel web' ($P::Cyan) { Start-Process $PanelUrl }
ItemMenu '    Ayuda y soporte' ($P::Cyan) { MostrarVentana; AbrirAyuda }
ItemMenu '    Buscar actualizaciones' ($P::Cyan) { MostrarVentana; BuscarActualizacion $true }
[void]$menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
ItemMenu '    Salir y apagar todo' ($P::Red) { SalirApagando }
$script:Bandeja.ContextMenuStrip = $menu
$script:Bandeja.Add_MouseClick({ param($s, $e) if ($e.Button -eq [Windows.Forms.MouseButtons]::Left) { MostrarVentana } })
$script:Bandeja.Visible = $true

function MostrarVentana {
    if (-not $f.Visible) { $f.Show() }
    if ($f.WindowState -eq [Windows.Forms.FormWindowState]::Minimized) { $f.WindowState = [Windows.Forms.FormWindowState]::Normal }
    $f.Activate()
}
function OcultarEnBandeja {
    if ($script:VentanaServ -and -not $script:VentanaServ.IsDisposed) { $script:VentanaServ.Close() }
    $f.Hide()
    if (-not $script:AvisoBandeja) {
        $script:AvisoBandeja = $true
        Notificar 'THESKNAEPHOST SIGUE ACTIVO' 'Tus servidores siguen funcionando. Ábrelo o ciérralo desde el icono junto al reloj.' ([TH.Pal]::Pink) 6000
    }
}
# Salir de verdad: apaga los servidores (guardando el mundo), espera a que terminen, apaga Linux y cierra
function SalirApagando {
    $salir = Preguntar "Se apagarán tus servidores (guardando el mundo), luego Linux, y se cerrará ThesknaepHost.`n`nPara dejarlos encendidos, cierra solo la ventana con la X: la app sigue en el icono junto al reloj." `
        'SALIR' 'APAGAR Y SALIR' 'CANCELAR' $true
    if (-not $salir) { return }
    $script:Bandeja.Text = 'ThesknaepHost · apagando…'
    Notificar 'APAGANDO…' 'Guardando los mundos y apagando los servidores y Linux. La app se cerrará sola.' ([TH.Pal]::Amber) 6000
    if ($f.Visible) { Ocupar $true 'Apagando servidores y Linux para salir...' }
    Async {
        $e = LeerEstado
        if ($e.on -and $e.web) {
            Recursos @('apagar-todos') | Out-Null
            for ($i = 0; $i -lt 30; $i++) {          # esperar a que guarden y se apaguen (max ~2 min)
                $st = Recursos @('estado')
                if (-not $st.ok -or @($st.servers | Where-Object { $_.estado -in 'running', 'starting', 'stopping' }).Count -eq 0) { break }
                Start-Sleep -Seconds 2
            }
        }
        if ($e.on) { Apagar }
        'ok'
    } {
        param($x, $err)
        $script:Saliendo = $true
        $f.Close()
    }
}

# La X de la ventana (o Alt+F4) la esconde en la bandeja; solo se cierra de verdad desde el icono o al apagar Windows
$f.Add_FormClosing({
    param($s, $e)
    if (-not $script:Saliendo -and $e.CloseReason -eq [Windows.Forms.CloseReason]::UserClosing) { $e.Cancel = $true; OcultarEnBandeja }
})
$f.Add_FormClosed({
    $timer.Stop()
    try { $script:Bandeja.Visible = $false; $script:Bandeja.Dispose() } catch {}
    try { $script:EvMostrar.Dispose(); $script:Mutex.ReleaseMutex(); $script:Mutex.Dispose() } catch {}
})
# Bucle normal de aplicacion (con ShowDialog, esconder la ventana la cerraria)
[Windows.Forms.Application]::Run($f)
