$UserSSH = "carlosgc"
$PassSSH = "asir2026"

function Mostrar-Puertos {
  Write-Host "`n=== PUERTOS 9990-9999 ABIERTOS EN $env:COMPUTERNAME ===" -ForegroundColor Cyan
  $res = netstat -ano | findstr ":999"
  if ($res) { $res } else { Write-Host "  (Ningun puerto 9990-9999 abierto)" }
  Write-Host "`n=== PROCESOS SSH ACTIVOS ===" -ForegroundColor Cyan
  Get-Process ssh -ErrorAction SilentlyContinue | Format-Table Id, ProcessName, StartTime -AutoSize
}

while ($true) {
  Write-Host "`n================ ASISTENTE TUNELES WINDOWS ($env:COMPUTERNAME) ================" -ForegroundColor Yellow
  Write-Host " 1) Tunel DIRECTO (-L)  -> Traer servicio remoto a 127.0.0.1:999x"
  Write-Host " 2) Montar SSHFS en Z:  -> Conectar carpeta remota (acepta huella antes)"
  Write-Host " 3) Abrir Chromium con Proxy SOCKS5 (Internet tunelizado)"
  Write-Host " 4) Auditoria (VER)     -> Mostrar puertos 9990-9999 y procesos SSH"
  Write-Host " 5) Limpiar             -> Cerrar tuneles SSH y desmontar Z:"
  Write-Host " 0) Salir"
  Write-Host "===============================================================================" -ForegroundColor Yellow
  $opc = Read-Host "Elige opcion"

  switch ($opc) {
    "1" {
      Write-Host "Servidores directos en Red C: 52.52.52.51(51022) | 52.52.52.52(52022) | 52.52.52.54(54022)" -ForegroundColor DarkGray
      $pLoc  = Read-Host "Puerto local del tunel (9990-9999)"
      $ipDst = Read-Host "IP destino final (ej. 127.0.0.1 o 50.50.50.51)"
      $pDst  = Read-Host "Puerto destino final (ej. 9998 o 55080)"
      $ipSrv = Read-Host "IP servidor puente Red C [52.52.52.52]"
      if (-not $ipSrv) { $ipSrv = "52.52.52.52" }
      $pSrv  = Read-Host "Puerto SSH servidor puente [52022]"
      if (-not $pSrv) { $pSrv = "52022" }

      Write-Host "`n>>> COMANDO A EJECUTAR (Ctrl+C para cerrar):" -ForegroundColor Green
      Write-Host "    ssh -N -p $pSrv -L ${pLoc}:${ipDst}:${pDst} ${UserSSH}@${ipSrv}`n" -ForegroundColor White
      ssh -N -p $pSrv -L "${pLoc}:${ipDst}:${pDst}" "${UserSSH}@${ipSrv}"
    }

    "2" {
      $ipSrv = Read-Host "IP servidor o tunel [52.52.52.52]"
      if (-not $ipSrv) { $ipSrv = "52.52.52.52" }
      $pSrv  = Read-Host "Puerto SSH o del tunel [9990]"
      if (-not $pSrv) { $pSrv = "9990" }
      $ruta  = Read-Host "Ruta remota sin barra inicial [mnt\hd_externo_2GB]"
      if (-not $ruta) { $ruta = "mnt\hd_externo_2GB" }

      Write-Host "`n[*] Paso 1: Aceptando huella SSH (escribe 'yes' si pregunta y mete la clave)..." -ForegroundColor Cyan
      ssh -p $pSrv "${UserSSH}@${ipSrv}" "echo Huella_OK"

      $unc = "\\sshfs.r\${UserSSH}@${ipSrv}!${pSrv}\${ruta}"
      Write-Host "`n>>> Paso 2: Montando unidad Z:" -ForegroundColor Green
      Write-Host "    net use Z: $unc /user:$UserSSH $PassSSH`n" -ForegroundColor White
      net use Z: /delete /y 2>$null | Out-Null
      net use Z: $unc /user:$UserSSH $PassSSH
      if (Test-Path "Z:\") { Get-ChildItem Z:\ }
    }

    "3" {
      $ipProxy = Read-Host "IP del proxy SOCKS5 [52.52.52.52]"
      if (-not $ipProxy) { $ipProxy = "52.52.52.52" }
      $pProxy  = Read-Host "Puerto del proxy SOCKS5 [9996]"
      if (-not $pProxy) { $pProxy = "9996" }

      $rutasChrome = @(
        "C:\Program Files\Chromium\Application\chrome.exe",
        "C:\Program Files (x86)\Chromium\Application\chrome.exe",
        "$env:LOCALAPPDATA\Chromium\Application\chrome.exe"
      )
      $chrome = $rutasChrome | Where-Object { Test-Path $_ } | Select-Object -First 1
      if (-not $chrome) { $chrome = Read-Host "No se encontro chrome.exe automaticamente. Pega la ruta completa" }

      Write-Host "[*] Cerrando ventanas previas de Chromium para aplicar el proxy..." -ForegroundColor Cyan
      Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue
      Start-Sleep -Seconds 1

      Write-Host "`n>>> COMANDO A EJECUTAR:" -ForegroundColor Green
      Write-Host "    & `"$chrome`" --proxy-server=`"socks5://${ipProxy}:${pProxy}`"`n" -ForegroundColor White
      Start-Process -FilePath $chrome -ArgumentList "--proxy-server=`"socks5://${ipProxy}:${pProxy}`""
    }

    "4" {
      Mostrar-Puertos
    }

    "5" {
      Stop-Process -Name ssh -Force -ErrorAction SilentlyContinue
      net use Z: /delete /y 2>$null | Out-Null
      Write-Host "[OK] Tuneles SSH cerrados y unidad Z: desmontada." -ForegroundColor Green
    }

    "0" {
      break
    }
  }
}