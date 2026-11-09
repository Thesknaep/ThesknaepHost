# ThesknaepHost - ventana "AYUDA": modo de uso, reglas, errores conocidos con su solucion y soporte.
# El texto sale de web\ayuda.json (el mismo que usa la version de Linux). Se carga desde ThesknaepHost.ps1.

$script:Ayuda = $null
$SoporteUrl = 'https://github.com/Thesknaep/ThesknaepHost/issues'

function LeerAyuda {
    if ($script:Ayuda) { return $script:Ayuda }
    $a = Join-Path $Raiz 'web\ayuda.json'
    try { $script:Ayuda = [IO.File]::ReadAllText($a, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { $script:Ayuda = $null }
    $script:Ayuda
}

function MostrarSeccionAyuda([int]$i) {
    $ay = LeerAyuda
    $rt = $script:AyTexto
    $rt.Clear()
    for ($k = 0; $k -lt $script:AyTabs.Count; $k++) {
        $script:AyTabs[$k].Filled = ($k -eq $i); $script:AyTabs[$k].Invalidate()
    }
    if (-not $ay) { $rt.SelectionColor = [TH.Pal]::Red; $rt.AppendText('No se encontró web\ayuda.json. Abre GUÍA COMPLETA.'); return }
    $sec = $ay.secciones[$i]
    $fTit = [TH.Pal]::F(11, [Drawing.FontStyle]::Bold)
    $fTxt = [TH.Pal]::F(10, [Drawing.FontStyle]::Regular)
    $fTag = [TH.Pal]::F(8.5, [Drawing.FontStyle]::Bold)
    $grupo = $null
    foreach ($it in $sec.items) {
        if ($it.s -eq 'LINUX') { continue }      # esta es la app de Windows: los errores de Linux no aplican
        if ($it.s -and $it.s -ne $grupo) {
            $grupo = $it.s
            $rt.SelectionFont = [TH.Pal]::F(12, [Drawing.FontStyle]::Bold); $rt.SelectionColor = [TH.Pal]::Cyan
            $rt.AppendText("// $grupo`n`n")
        }
        $rt.SelectionFont = $fTit; $rt.SelectionColor = [TH.Pal]::Pink
        $rt.AppendText("$($it.t)`n")
        $rt.SelectionFont = $fTxt; $rt.SelectionColor = [TH.Pal]::Text
        $rt.AppendText("$($it.d)`n`n")
    }
    if ($sec.id -eq 'soporte') {
        $rt.SelectionFont = $fTag; $rt.SelectionColor = [TH.Pal]::Dim
        $rt.AppendText("SOPORTE :: $SoporteUrl")
    }
    $rt.SelectionStart = 0; $rt.ScrollToCaret()
}

function AbrirAyuda([string]$seccion = 'uso') {
    $d = NuevaVentana 'AYUDA' '// MODO DE USO  ::  REGLAS  ::  ERRORES Y SOLUCIONES  ::  SOPORTE' 860 640
    $ay = LeerAyuda
    $script:AyTabs = @()
    $nombres = if ($ay) { @($ay.secciones | ForEach-Object { $_.titulo }) } else { @('AYUDA') }
    $ancho = [int]((812 - ($nombres.Count - 1) * 8) / $nombres.Count)
    for ($i = 0; $i -lt $nombres.Count; $i++) {
        $acento = if ($nombres[$i] -like 'ERRORES*') { [TH.Pal]::Amber } elseif ($nombres[$i] -eq 'SOPORTE') { [TH.Pal]::Cyan } else { [TH.Pal]::Pink }
        $b = Boton $d $nombres[$i] (24 + $i * ($ancho + 8)) 108 $ancho 40 $acento $false { MostrarSeccionAyuda ([int]$this.Tag) }
        $b.Tag = $i
        $script:AyTabs += $b
    }

    $t = TarjetaEn $d 'GUÍA' 'HELP' 24 160 812 404
    $rt = New-Object Windows.Forms.RichTextBox
    $rt.ReadOnly = $true; $rt.BorderStyle = 'None'; $rt.DetectUrls = $false
    $rt.BackColor = [TH.Pal]::Panel; $rt.ForeColor = [TH.Pal]::Text
    $rt.ScrollBars = 'Vertical'; $rt.Cursor = [Windows.Forms.Cursors]::Arrow
    $rt.Location = New-Object Drawing.Point(18, 46); $rt.Size = New-Object Drawing.Size(778, 344)
    $t.Controls.Add($rt)
    [TH.Win]::Oscuro($rt)
    $script:AyTexto = $rt

    Boton $d 'ABRIR SOPORTE (GITHUB)' 24 576 260 46 ([TH.Pal]::Pink) $true { Start-Process $SoporteUrl } | Out-Null
    Boton $d 'ABRIR REGISTROS' 296 576 260 46 ([TH.Pal]::Cyan) $false {
        New-Item -ItemType Directory -Force $Base | Out-Null; Start-Process explorer.exe $Base
    } | Out-Null
    Boton $d 'GUÍA COMPLETA' 568 576 268 46 ([TH.Pal]::PinkSoft) $false {
        $l = Join-Path $Raiz 'LEEME.md'; if (Test-Path $l) { Start-Process notepad.exe $l }
    } | Out-Null

    $script:AyIni = 0
    if ($ay) { for ($i = 0; $i -lt $ay.secciones.Count; $i++) { if ($ay.secciones[$i].id -eq $seccion) { $script:AyIni = $i } } }
    $d.Add_Shown({ MostrarSeccionAyuda $script:AyIni })
    [void]$d.ShowDialog($f)
    $d.Dispose()
}
