param(
  [ValidateSet("1", "2", "Todo", "Verificar")]
  [string]$Fase = "Todo"
)

$ErrorActionPreference = "Stop"
$MacNet3 = "BC-24-11-81-3D-27"   # MAC de net3 (vmbr229, tag=27, Red C) en VM 511
$IpWin   = "52.52.52.59"

function Ejecutar-Fase1 {
  Write-Host "=== FASE 1 WINDOWS: Nombre, hosts, firewall y clientes SSH/SSHFS ===" -ForegroundColor Cyan

  # 1. Renombrar equipo (requiere reinicio al final)
  if ($env:COMPUTERNAME -ne "CGC-Hwin") {
    Rename-Computer -NewName "CGC-Hwin" -Force
    Write-Host "[OK] Equipo renombrado a CGC-Hwin (se aplicará tras reiniciar)."
  }

  # 2. Actualizar archivo hosts (limpiando ejecuciones previas)
  $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
  $contenido = Get-Content $hostsPath -Raw
  $contenido = $contenido -replace "(?s)# === INI ESCENARIO SSH ===.*?# === FIN ESCENARIO SSH ===\r?\n?", ""
  $bloqueHosts = @"

# === INI ESCENARIO SSH ===
52.52.52.51 CGC-Subu51.r52carrera.org CGC-Subu51
52.52.52.52 CGC-Sdeb52.r52carrera.org CGC-Sdeb52
52.52.52.54 CGC-Sdeb54.r52carrera.org CGC-Sdeb54
52.52.52.59 CGC-Hwin.r52carrera.org CGC-Hwin
# === FIN ESCENARIO SSH ===
"@
  Set-Content -Path $hostsPath -Value ($contenido.TrimEnd() + "`r`n" + $bloqueHosts) -Encoding ASCII
  Write-Host "[OK] Archivo hosts actualizado."

  # 3. Permitir ping entrante (ICMPv4) para poder verificar conectividad desde Linux
  if (-not (Get-NetFirewallRule -Name "Escenario-ICMPv4" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name "Escenario-ICMPv4" -DisplayName "Escenario SSH - Permitir Ping ICMPv4" `
      -Protocol ICMPv4 -IcmpType 8 -Direction Inbound -Action Allow | Out-Null
  }

  # 4. Instalar PuTTY, WinFsp y SSHFS-Win
  $tmp = "C:\TempSSH"
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

  Write-Host "[*] Descargando e instalando PuTTY..."
  Invoke-WebRequest -Uri "https://the.earth.li/~sgtatham/putty/latest/w64/putty-64bit-0.81-installer.msi" -OutFile "$tmp\putty.msi"
  Start-Process msiexec.exe -Wait -ArgumentList "/i `"$tmp\putty.msi`" /qn"

  Write-Host "[*] Descargando e instalando WinFsp..."
  Invoke-WebRequest -Uri "https://github.com/winfsp/winfsp/releases/download/v2.0/winfsp-2.0.23075.msi" -OutFile "$tmp\winfsp.msi"
  Start-Process msiexec.exe -Wait -ArgumentList "/i `"$tmp\winfsp.msi`" /qn"

  Write-Host "[*] Descargando e instalando SSHFS-Win..."
  Invoke-WebRequest -Uri "https://github.com/winfsp/sshfs-win/releases/download/v3.5.20357/sshfs-win-3.5.20357-x64.msi" -OutFile "$tmp\sshfs-win.msi"
  Start-Process msiexec.exe -Wait -ArgumentList "/i `"$tmp\sshfs-win.msi`" /qn"

  Write-Host "[OK] FASE 1 completada." -ForegroundColor Green
}

function Ejecutar-Fase2 {
  Write-Host "=== FASE 2 WINDOWS: Configurar net3 ($IpWin/24) y desactivar el resto ===" -ForegroundColor Cyan

  $encontrada = $false
  Get-NetAdapter | ForEach-Object {
    if ($_.MacAddress -eq $MacNet3) {
      $encontrada = $true
      Write-Host "[*] Activando $($_.Name) [$($_.MacAddress)] -> $IpWin/24 (Sin Gateway)"
      Enable-NetAdapter -Name $_.Name -Confirm:$false
      Start-Sleep -Seconds 2
      Remove-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
      Remove-NetRoute -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
      Set-NetIPInterface -InterfaceIndex $_.ifIndex -Dhcp Disabled
      New-NetIPAddress -InterfaceIndex $_.ifIndex -IPAddress $IpWin -PrefixLength 24 | Out-Null
    } else {
      Write-Host "[*] Desactivando $($_.Name) [$($_.MacAddress)]"
      Disable-NetAdapter -Name $_.Name -Confirm:$false
    }
  }

  if (-not $encontrada) {
    Write-Error "No se encontró ninguna tarjeta con MAC $MacNet3. Revisa Get-NetAdapter."
  }

  Write-Host "[OK] FASE 2 completada. Reinicia el equipo (Restart-Computer) para aplicar el nombre CGC-Hwin." -ForegroundColor Green
}

function Ejecutar-Verificar {
  Write-Host "=== AUDITORÍA WINDOWS ($env:COMPUTERNAME) ===" -ForegroundColor Cyan
  Get-NetAdapter | Format-Table Name, Status, MacAddress -AutoSize
  Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback" } |
    Format-Table InterfaceAlias, IPAddress, PrefixLength -AutoSize

  Write-Host "--- Ping a vecinos Red C (deben responder OK) ---"
  foreach ($ip in @("52.52.52.51", "52.52.52.52", "52.52.52.54")) {
    if (Test-Connection -ComputerName $ip -Count 1 -Quiet) {
      Write-Host "  [OK]    $ip accesible" -ForegroundColor Green
    } else {
      Write-Host "  [FALLO] $ip NO responde" -ForegroundColor Red
    }
  }

  Write-Host "--- Ping a red remota (debe FALLAR) ---"
  if (Test-Connection -ComputerName "50.50.50.56" -Count 1 -Quiet) {
    Write-Host "  [ERROR AISLAMIENTO] 50.50.50.56 responde" -ForegroundColor Red
  } else {
    Write-Host "  [OK AISLADO]        50.50.50.56 inalcanzable" -ForegroundColor Green
  }
}

switch ($Fase) {
  "1"         { Ejecutar-Fase1 }
  "2"         { Ejecutar-Fase2 }
  "Todo"      { Ejecutar-Fase1; Ejecutar-Fase2 }
  "Verificar" { Ejecutar-Verificar }
}