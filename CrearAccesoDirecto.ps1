# Crea los iconos de ThesknaepHost y los accesos directos en el Escritorio y el menu Inicio.
# Se abre como una aplicacion normal: sin ventana de consola.
#
# Hay DOS iconos:
#   thesknaephost-app.ico      -> la aplicacion: Escritorio, menu Inicio, barra de tareas y ventana (diamante con destello)
#   thesknaephost-bandeja.ico  -> notificaciones: icono junto al reloj y avisos (cristal)
# Cada uno en 7 tamanos (16 a 256 px). Si cambia el diseno, se cambia la VERSION en el nombre del archivo
# para que Windows no siga mostrando el icono viejo que guarda en su cache.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$dir = $PSScriptRoot

$Rosa = [Drawing.Color]::FromArgb(255, 46, 151); $RosaS = [Drawing.Color]::FromArgb(255, 160, 220)
$Mag = [Drawing.Color]::FromArgb(170, 30, 160); $Cian = [Drawing.Color]::FromArgb(0, 229, 255)

function Lienzo([int]$n) {
    $bmp = New-Object Drawing.Bitmap $n, $n, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'
    $bmp; $g
}
function Pt([float]$x, [float]$y, [float]$s) { New-Object Drawing.PointF ([float]($x * $s)), ([float]($y * $s)) }
function Brillo($g, $path, $color, [int]$n, [float]$s) {
    if ($n -lt 32) { return }                          # en tamanos chicos el brillo ensucia
    foreach ($w in 9, 6) { $pg = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(38, $color)), ([float]($w * $s)); $pg.LineJoin = 'Round'; $g.DrawPath($pg, $path) }
}
# Diamante facetado. $c: coordenadas de los 5 vertices (x0 = desplazamiento horizontal)
function Diamante($g, [int]$n, [float]$s, [float]$x0, [float]$y0, [float]$alto) {
    $k = $alto / 50.0                                  # 50 = alto del diamante base
    function Q([float]$x, [float]$y) { Pt ($x0 + $x * $k) ($y0 + $y * $k) $s }
    $gema = New-Object Drawing.Drawing2D.GraphicsPath
    $gema.AddPolygon([Drawing.PointF[]]@((Q 14 0), (Q 38 0), (Q 52 16), (Q 26 50), (Q 0 16)))
    Brillo $g $gema $Rosa $n $s
    $g.FillPath((New-Object Drawing.Drawing2D.LinearGradientBrush ((New-Object Drawing.PointF 0, 0), (New-Object Drawing.PointF 0, $n), $Rosa, $Mag)), $gema)
    $l = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(120, 255, 255, 255)), ([float][Math]::Max(0.7, 1.5 * $s))
    foreach ($q in @(@(0, 16, 52, 16), @(14, 0, 20, 16), @(38, 0, 32, 16), @(20, 16, 26, 50), @(32, 16, 26, 50), @(26, 0, 20, 16), @(26, 0, 32, 16))) {
        $g.DrawLine($l, (Q $q[0] $q[1]), (Q $q[2] $q[3]))
    }
    $cara = New-Object Drawing.Drawing2D.GraphicsPath
    $cara.AddPolygon([Drawing.PointF[]]@((Q 14 0), (Q 26 0), (Q 20 16), (Q 0 16)))
    $g.FillPath((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(95, $Cian))), $cara)
    $borde = New-Object Drawing.Pen $RosaS, ([float][Math]::Max(1.1, 2 * $s)); $borde.LineJoin = 'Round'
    $g.DrawPath($borde, $gema)
}

# Icono de la APLICACION: diamante con destello
function DibujarApp([int]$n) {
    $bmp, $g = Lienzo $n; $s = $n / 64.0
    Diamante $g $n $s 2 10 50
    $estrella = New-Object Drawing.Drawing2D.GraphicsPath
    $estrella.AddPolygon([Drawing.PointF[]](0..7 | ForEach-Object {
        $a = [Math]::PI / 4 * $_ - [Math]::PI / 2; $r = if ($_ % 2 -eq 0) { 11 } else { 2.6 }
        Pt (52 + $r * [Math]::Cos($a)) (11 + $r * [Math]::Sin($a)) $s
    }))
    $g.FillPath((New-Object Drawing.SolidBrush ([Drawing.Color]::White)), $estrella)
    Brillo $g $estrella $Cian $n $s
    $g.Dispose(); $bmp
}
# Icono de NOTIFICACIONES (junto al reloj): el cristal
function DibujarBandeja([int]$n) {
    $bmp, $g = Lienzo $n; $s = $n / 64.0
    Diamante $g $n $s 6 8 50
    $g.Dispose(); $bmp
}

# Guarda un .ico con 7 tamanos: 16-128 px en BMP (lo lee todo, incluida la ventana de la app), 256 px en PNG
function GuardarIco([string]$ruta, [scriptblock]$dibujar) {
    $tamanos = 16, 24, 32, 48, 64, 128, 256
    $datos = foreach ($n in $tamanos) {
        $b = & $dibujar $n
        if ($n -ge 256) { $ms = New-Object IO.MemoryStream; $b.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $b.Dispose(); , $ms.ToArray(); continue }
        $bits = $b.LockBits((New-Object Drawing.Rectangle 0, 0, $n, $n), 'ReadOnly', [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $px = New-Object byte[] ($n * $n * 4); [Runtime.InteropServices.Marshal]::Copy($bits.Scan0, $px, 0, $px.Length)
        $b.UnlockBits($bits); $b.Dispose()
        $ms = New-Object IO.MemoryStream; $bw = New-Object IO.BinaryWriter($ms)
        $bw.Write([uint32]40); $bw.Write([int32]$n); $bw.Write([int32]($n * 2)); $bw.Write([uint16]1); $bw.Write([uint16]32)
        $bw.Write([uint32]0); $bw.Write([uint32]0); $bw.Write([int32]0); $bw.Write([int32]0); $bw.Write([uint32]0); $bw.Write([uint32]0)
        for ($y = $n - 1; $y -ge 0; $y--) { $bw.Write($px, $y * $n * 4, $n * 4) }     # filas de abajo hacia arriba (BGRA)
        $bw.Write((New-Object byte[] ([int]([Math]::Ceiling($n / 32.0) * 4) * $n)))    # mascara AND vacia (usa el alfa)
        $bw.Flush(); , $ms.ToArray()
    }
    $out = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter($out)
    $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$tamanos.Count)
    $offset = 6 + 16 * $tamanos.Count
    for ($i = 0; $i -lt $tamanos.Count; $i++) {
        $n = $tamanos[$i]; $len = $datos[$i].Length
        $w.Write([byte]($n % 256)); $w.Write([byte]($n % 256)); $w.Write([byte]0); $w.Write([byte]0)
        $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$len); $w.Write([uint32]$offset)
        $offset += $len
    }
    foreach ($x in $datos) { $w.Write($x) }
    $w.Flush(); [IO.File]::WriteAllBytes($ruta, $out.ToArray()); $w.Dispose()
}

# 1. Iconos (version en el nombre: si cambia el diseno, Windows carga el nuevo)
$icoApp = Join-Path $dir 'thesknaephost-app-v2.ico'
$icoBandeja = Join-Path $dir 'thesknaephost-bandeja-v2.ico'
if (-not (Test-Path $icoApp)) { GuardarIco $icoApp ${function:DibujarApp} }
if (-not (Test-Path $icoBandeja)) { GuardarIco $icoBandeja ${function:DibujarBandeja} }
# limpiar iconos de versiones anteriores
Get-ChildItem $dir -Filter 'thesknaephost*.ico*' | Where-Object { $_.FullName -notin $icoApp, $icoBandeja } | Remove-Item -Force -ErrorAction SilentlyContinue

# 2. Lanzador sin consola
$vbs = Join-Path $dir 'ThesknaepHost.vbs'
$ps1 = Join-Path $dir 'ThesknaepHost.ps1'
@"
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$ps1""", 0, False
"@ | Set-Content -Path $vbs -Encoding Unicode

# 3. Accesos directos con el icono de la APLICACION (y borra los de la version anterior, "PteroHost")
$sh = New-Object -ComObject WScript.Shell
foreach ($d in [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs')) {
    Remove-Item (Join-Path $d 'PteroHost.lnk') -ErrorAction SilentlyContinue
    $lnk = $sh.CreateShortcut((Join-Path $d 'ThesknaepHost.lnk'))
    $lnk.TargetPath = "$env:WINDIR\System32\wscript.exe"
    $lnk.Arguments = "`"$vbs`""
    $lnk.WorkingDirectory = $dir
    $lnk.IconLocation = "$icoApp,0"
    $lnk.Description = 'ThesknaepHost - servidores de juegos con Pterodactyl'
    $lnk.Save()
}
Write-Host 'Iconos y accesos directos listos (Escritorio y menú Inicio).'
