#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# CONFIGURACIÓN GLOBAL (Carlos Gordillo Carrera - 2º ASIR)
# ==========================================================
ALUMNO_NOMBRE="Carlos Gordillo Carrera"
USUARIO_SRV="carlosgc"
PASS_SRV="asir2026"
PREFIJO="CGC"

if [[ $EUID -ne 0 ]]; then
  echo "Error: ejecuta con sudo -> sudo bash $0 <51..58> <todo|fase1|fase2|verificar|internet-on>"
  exit 1
fi

ID="${1:-}"
MODO="${2:-}"

if [[ -z "$ID" || -z "$MODO" ]]; then
  echo "Uso: sudo bash $0 <51..58> <todo|fase1|fase2|verificar|internet-on>"
  exit 1
fi

# ==========================================================
# MAPA DEFINITIVO (coincide con PDF entregado y VLANs Proxmox)
#   net0 = vmbr22  tag 5  (Internet)
#   net1 = vmbr229 tag 25 (Red A=50 / Red G=56)
#   net2 = vmbr229 tag 26 (Red B=51)
#   net3 = vmbr229 tag 27 (Red C=52)
#   net4 = vmbr229 tag 28 (Red D=53)
#   net5 = vmbr229 tag 29 (Red E=54)
#   net6 = vmbr229 tag 30 (Red F=55)
# ==========================================================
case "$ID" in
  51)
    ROL="S"; SO="ubu"; HD_DIR=""; HD_ETIQ=""
    NET_MAP=("DHCP" "50" "OFF" "52" "OFF" "OFF" "OFF")
    VECINOS=("50.50.50.52" "50.50.50.56" "52.52.52.52" "52.52.52.54" "52.52.52.59")
    REMOTOS=("54.54.54.52" "55.55.55.55")
    ;;
  52)
    ROL="S"; SO="deb"; HD_DIR=""; HD_ETIQ=""
    NET_MAP=("OFF" "50" "OFF" "52" "53" "54" "OFF")
    VECINOS=("50.50.50.51" "50.50.50.56" "52.52.52.51" "52.52.52.54" "52.52.52.59" "53.53.53.54" "53.53.53.58" "54.54.54.56" "54.54.54.57" "54.54.54.58")
    REMOTOS=("51.51.51.53" "55.55.55.55" "56.56.56.53")
    ;;
  53)
    ROL="S"; SO="ubu"; HD_DIR="/mnt/hd_externo_2GB"; HD_ETIQ="2GB"
    NET_MAP=("OFF" "56" "51" "OFF" "OFF" "OFF" "OFF")
    VECINOS=("51.51.51.56" "51.51.51.57" "56.56.56.55" "56.56.56.57")
    REMOTOS=("50.50.50.51" "52.52.52.51" "54.54.54.52")
    ;;
  54)
    ROL="S"; SO="deb"; HD_DIR="/mnt/hd_externo_1GB"; HD_ETIQ="1GB"
    NET_MAP=("OFF" "OFF" "OFF" "52" "53" "OFF" "OFF")
    VECINOS=("52.52.52.51" "52.52.52.52" "52.52.52.59" "53.53.53.52" "53.53.53.58")
    REMOTOS=("50.50.50.51" "54.54.54.52" "55.55.55.55")
    ;;
  55)
    ROL="S"; SO="ubu"; HD_DIR=""; HD_ETIQ=""
    NET_MAP=("OFF" "56" "OFF" "OFF" "OFF" "OFF" "55")
    VECINOS=("55.55.55.57" "55.55.55.58" "56.56.56.53" "56.56.56.57")
    REMOTOS=("50.50.50.51" "52.52.52.51" "54.54.54.52")
    ;;
  56)
    ROL="H"; SO="deb"; HD_DIR=""; HD_ETIQ=""
    NET_MAP=("OFF" "50" "51" "OFF" "OFF" "54" "OFF")
    VECINOS=("50.50.50.51" "50.50.50.52" "51.51.51.53" "51.51.51.57" "54.54.54.52" "54.54.54.57" "54.54.54.58")
    REMOTOS=("52.52.52.54" "55.55.55.55" "56.56.56.55")
    ;;
  57)
    ROL="H"; SO="ubu"; HD_DIR=""; HD_ETIQ=""
    NET_MAP=("OFF" "56" "51" "OFF" "OFF" "54" "55")
    VECINOS=("51.51.51.53" "51.51.51.56" "54.54.54.52" "54.54.54.56" "54.54.54.58" "55.55.55.55" "55.55.55.58" "56.56.56.53" "56.56.56.55")
    REMOTOS=("50.50.50.51" "52.52.52.54" "53.53.53.54")
    ;;
  58)
    ROL="H"; SO="deb"; HD_DIR=""; HD_ETIQ=""
    NET_MAP=("OFF" "OFF" "OFF" "OFF" "53" "54" "55")
    VECINOS=("53.53.53.52" "53.53.53.54" "54.54.54.52" "54.54.54.56" "54.54.54.57" "55.55.55.55" "55.55.55.57")
    REMOTOS=("50.50.50.51" "52.52.52.51" "56.56.56.53")
    ;;
  *)
    echo "Error: ID '$ID' no válido. Usa 51..58."
    exit 1
    ;;
esac

HOSTNAME_FINAL="${PREFIJO}-${ROL}${SO}${ID}"
SSH_PORT="${ID}022"
HTTP_PORT="${ID}080"

obtener_interfaces_pci() {
  mapfile -t IFACES < <(
    for dev in /sys/class/net/*; do
      name="$(basename "$dev")"
      [[ "$name" == "lo" ]] && continue
      [[ -e "$dev/device" ]] || continue
      path="$(readlink -f "$dev/device")"
      echo "${path} ${name}"
    done | sort -V | awk '{print $2}'
  )
}

configurar_hosts() {
  echo "[*] Configurando hostname ($HOSTNAME_FINAL) y /etc/hosts..."
  hostnamectl set-hostname "$HOSTNAME_FINAL"

  sed -i '/# === INI ESCENARIO SSH ===/,/# === FIN ESCENARIO SSH ===/d' /etc/hosts
  if grep -q '^127\.0\.1\.1' /etc/hosts; then
    sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t${HOSTNAME_FINAL}/" /etc/hosts
  else
    echo -e "127.0.1.1\t${HOSTNAME_FINAL}" >> /etc/hosts
  fi

  cat << 'EOF' >> /etc/hosts
# === INI ESCENARIO SSH ===
# Red A (50.50.50.0/24 - r50carlos.net)
50.50.50.51 CGC-Subu51.r50carlos.net CGC-Subu51-A
50.50.50.52 CGC-Sdeb52.r50carlos.net CGC-Sdeb52-A
50.50.50.56 CGC-Hdeb56.r50carlos.net CGC-Hdeb56-A

# Red B (51.51.51.0/24 - r51gordillo.sys)
51.51.51.53 CGC-Subu53.r51gordillo.sys CGC-Subu53-B
51.51.51.56 CGC-Hdeb56.r51gordillo.sys CGC-Hdeb56-B
51.51.51.57 CGC-Hubu57.r51gordillo.sys CGC-Hubu57-B

# Red C (52.52.52.0/24 - r52carrera.org)
52.52.52.51 CGC-Subu51.r52carrera.org CGC-Subu51-C
52.52.52.52 CGC-Sdeb52.r52carrera.org CGC-Sdeb52-C
52.52.52.54 CGC-Sdeb54.r52carrera.org CGC-Sdeb54-C
52.52.52.59 CGC-Hwin.r52carrera.org CGC-Hwin

# Red D (53.53.53.0/24 - r53carlos.edu)
53.53.53.52 CGC-Sdeb52.r53carlos.edu CGC-Sdeb52-D
53.53.53.54 CGC-Sdeb54.r53carlos.edu CGC-Sdeb54-D
53.53.53.58 CGC-Hdeb58.r53carlos.edu CGC-Hdeb58-D

# Red E (54.54.54.0/24 - r54gordillo.com)
54.54.54.52 CGC-Sdeb52.r54gordillo.com CGC-Sdeb52-E
54.54.54.56 CGC-Hdeb56.r54gordillo.com CGC-Hdeb56-E
54.54.54.57 CGC-Hubu57.r54gordillo.com CGC-Hubu57-E
54.54.54.58 CGC-Hdeb58.r54gordillo.com CGC-Hdeb58-E

# Red F (55.55.55.0/24 - r55carrera.inf)
55.55.55.55 CGC-Subu55.r55carrera.inf CGC-Subu55-F
55.55.55.57 CGC-Hubu57.r55carrera.inf CGC-Hubu57-F
55.55.55.58 CGC-Hdeb58.r55carrera.inf CGC-Hdeb58-F

# Red G (56.56.56.0/24 - r56carlos.es)
56.56.56.53 CGC-Subu53.r56carlos.es CGC-Subu53-G
56.56.56.55 CGC-Subu55.r56carlos.es CGC-Subu55-G
56.56.56.57 CGC-Hubu57.r56carlos.es CGC-Hubu57-G
# === FIN ESCENARIO SSH ===
EOF
}

# ==========================================================
# FASE 1: PAQUETES, SERVICIOS, USUARIO Y CARPETAS HD
# ==========================================================
ejecutar_fase1() {
  echo "=========================================================="
  echo " FASE 1 -> $HOSTNAME_FINAL (Rol: $ROL | ID: $ID)"
  echo "=========================================================="

  configurar_hosts

  # Asegurar que ningún equipo Linux enruta tráfico IP entre sus interfaces
  echo "net.ipv4.ip_forward = 0" > /etc/sysctl.d/99-escenario-no-routing.conf
  sysctl -p /etc/sysctl.d/99-escenario-no-routing.conf >/dev/null || true

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl wget net-tools iputils-ping openssh-client sshfs spice-vdagent || true

  # Permitir user_allow_other en FUSE (útil para montajes SSHFS)
  if [[ -f /etc/fuse.conf ]]; then
    sed -i 's/^#user_allow_other/user_allow_other/' /etc/fuse.conf
  fi

  if [[ "$ROL" == "S" ]]; then
    echo "[*] Configurando SERVIDOR (SSH ${SSH_PORT} + Apache2 ${HTTP_PORT})..."
    apt-get install -y openssh-server apache2

    # Usuario obligatorio: carlosgc
    if ! id "$USUARIO_SRV" &>/dev/null; then
      useradd -m -s /bin/bash "$USUARIO_SRV"
    fi
    echo "${USUARIO_SRV}:${PASS_SRV}" | chpasswd
    usermod -aG sudo "$USUARIO_SRV" || true

    # SSH preparado para túneles locales (-L), remotos (-R), dinámicos (-D) y X11
    cp -n /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    rm -f /etc/ssh/sshd_config.d/99-escenario.conf
    sed -i -E 's/^[# ]*(Port|PasswordAuthentication|PubkeyAuthentication|AllowTcpForwarding|GatewayPorts|X11Forwarding|PermitOpen|ClientAliveInterval|ClientAliveCountMax)\b.*/#&/' /etc/ssh/sshd_config
    sed -i '/# === INI SSH ESCENARIO ===/,/# === FIN SSH ESCENARIO ===/d' /etc/ssh/sshd_config

    cat << EOF >> /etc/ssh/sshd_config
# === INI SSH ESCENARIO ===
Port ${SSH_PORT}
PasswordAuthentication yes
PubkeyAuthentication yes
AllowTcpForwarding yes
GatewayPorts yes
X11Forwarding yes
PermitOpen any
ClientAliveInterval 60
ClientAliveCountMax 3
# === FIN SSH ESCENARIO ===
EOF

    systemctl disable --now ssh.socket 2>/dev/null || true
    mkdir -p /run/sshd
    sshd -t
    systemctl enable ssh || systemctl enable sshd
    systemctl restart ssh || systemctl restart sshd

    # Apache2 en ?080
    echo "Listen ${HTTP_PORT}" > /etc/apache2/ports.conf
    cat << EOF > /etc/apache2/sites-available/000-default.conf
<VirtualHost *:${HTTP_PORT}>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

    FECHA_HOY="$(date '+%d/%m/%Y')"
    cat << EOF > /var/www/html/index.html
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>${HOSTNAME_FINAL}</title>
  <style>
    body { font-family: Arial, sans-serif; background: #f4f6f8; padding: 40px; }
    .card { max-width: 520px; margin: auto; background: #fff; padding: 24px 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
    h1 { margin-top: 0; color: #1a365d; }
    table { width: 100%; border-collapse: collapse; margin-top: 15px; }
    td { padding: 8px 6px; border-bottom: 1px solid #e2e8f0; }
    td:first-child { font-weight: bold; color: #4a5568; width: 45%; }
  </style>
</head>
<body>
  <div class="card">
    <h1>${HOSTNAME_FINAL}</h1>
    <table>
      <tr><td>Nombre del Equipo</td><td>${HOSTNAME_FINAL}</td></tr>
      <tr><td>Alumno</td><td>${ALUMNO_NOMBRE}</td></tr>
      <tr><td>Fecha</td><td>${FECHA_HOY}</td></tr>
      <tr><td>Puerto SSH</td><td>${SSH_PORT}</td></tr>
      <tr><td>Puerto HTTP</td><td>${HTTP_PORT}</td></tr>
    </table>
  </div>
</body>
</html>
EOF

    a2ensite 000-default.conf >/dev/null
    systemctl enable apache2
    systemctl restart apache2

    # Carpeta HD simulada en servidores 53 (2GB) y 54 (1GB)
    if [[ -n "$HD_DIR" ]]; then
      echo "[*] Creando carpeta de disco externo simulado: ${HD_DIR}..."
      mkdir -p "$HD_DIR"
      echo "Disco externo simulado (${HD_ETIQ}) en ${HOSTNAME_FINAL} - ${ALUMNO_NOMBRE}" > "${HD_DIR}/info_${HD_ETIQ}.txt"
      chown -R "${USUARIO_SRV}:${USUARIO_SRV}" "$HD_DIR"
      chmod 755 "$HD_DIR"
    fi

    # Reglas UFW solo si está activo
    if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
      ufw allow "${SSH_PORT}/tcp"
      ufw allow "${HTTP_PORT}/tcp"
    fi
  else
    echo "[*] Configurando CLIENTE (SSH, SSHFS, punto de montaje /mnt/remoto)..."
    mkdir -p /mnt/remoto
    chmod 777 /mnt/remoto
  fi

  echo "[OK] FASE 1 completada en ${HOSTNAME_FINAL}."
}

# ==========================================================
# FASE 2: TARJETAS net0..net6 Y AISLAMIENTO DE SOBRANTES
# ==========================================================
ejecutar_fase2() {
  echo "=========================================================="
  echo " FASE 2 (REDES net0..net6) -> $HOSTNAME_FINAL"
  echo "=========================================================="

  obtener_interfaces_pci

  if [[ "${#IFACES[@]}" -lt 7 ]]; then
    echo "ERROR: Se esperaban 7 tarjetas (net0..net6) y solo se detectaron ${#IFACES[@]}."
    ip -br link
    exit 1
  fi

  echo "Mapeo detectado (comprueba que la MAC de net0 coincide con Proxmox):"
  for i in {0..6}; do
    IFACE="${IFACES[$i]}"
    MAC="$(cat "/sys/class/net/${IFACE}/address" | tr '[:lower:]' '[:upper:]')"
    DEST="${NET_MAP[$i]}"
    case "$DEST" in
      DHCP) DESC="DHCP (Internet)" ;;
      OFF)  DESC="APAGADA (DOWN)" ;;
      *)    DESC="${DEST}.${DEST}.${DEST}.${ID}/24 (Sin Gateway)" ;;
    esac
    printf "  net%d -> %-8s [%s]  ==>  %s\n" "$i" "$IFACE" "$MAC" "$DESC"
  done

  echo ""
  read -rp "¿La MAC de net0 coincide con Proxmox? Aplicar red (s/N): " CONF
  [[ "$CONF" =~ ^[sS]$ ]] || { echo "Cancelado."; exit 1; }

  if command -v nmcli &>/dev/null && systemctl is-active --quiet NetworkManager; then
    UNMANAGED_LIST=()

    for i in {0..6}; do
      IFACE="${IFACES[$i]}"
      while IFS= read -r uuid; do
        [[ -n "$uuid" ]] && nmcli con delete uuid "$uuid" >/dev/null 2>&1 || true
      done < <(nmcli -t -f UUID,DEVICE con show | awk -F: -v dev="$IFACE" '$2==dev {print $1}')
      nmcli con delete "escenario-net${i}" >/dev/null 2>&1 || true

      if [[ "${NET_MAP[$i]}" == "OFF" ]]; then
        UNMANAGED_LIST+=("interface-name:${IFACE}")
      fi
    done

    rm -f /etc/NetworkManager/conf.d/99-escenario-unmanaged.conf
    if [[ "${#UNMANAGED_LIST[@]}" -gt 0 ]]; then
      mkdir -p /etc/NetworkManager/conf.d
      (IFS=';'; echo -e "[keyfile]\nunmanaged-devices=${UNMANAGED_LIST[*]}") > /etc/NetworkManager/conf.d/99-escenario-unmanaged.conf
    fi

    systemctl restart NetworkManager
    sleep 2

    for i in {0..6}; do
      IFACE="${IFACES[$i]}"
      DEST="${NET_MAP[$i]}"
      if [[ "$DEST" == "OFF" ]]; then
        ip addr flush dev "$IFACE" || true
        ip link set "$IFACE" down || true
      elif [[ "$DEST" == "DHCP" ]]; then
        nmcli con add type ethernet ifname "$IFACE" con-name "escenario-net${i}" \
          ipv4.method auto ipv6.method ignore autoconnect yes >/dev/null
        nmcli con up "escenario-net${i}" >/dev/null
      else
        nmcli con add type ethernet ifname "$IFACE" con-name "escenario-net${i}" \
          ipv4.method manual ipv4.addresses "${DEST}.${DEST}.${DEST}.${ID}/24" \
          ipv4.never-default yes ipv6.method ignore autoconnect yes >/dev/null
        nmcli con up "escenario-net${i}" >/dev/null
      fi
    done
  else
    echo "ERROR: NetworkManager no está activo. Verifica el gestor de red de esta VM."
    exit 1
  fi

  echo "[OK] FASE 2 completada. Estado de red:"
  ip -br a
  echo "[OK] Rutas:"
  ip route
}

# ==========================================================
# REACTIVAR INTERNET TEMPORAL EN net0 (SOLO SI HACE FALTA)
# ==========================================================
ejecutar_internet_on() {
  obtener_interfaces_pci
  IF0="${IFACES[0]}"
  echo "[*] Activando DHCP temporal en net0 (${IF0})..."
  sed -i "s/interface-name:${IF0};\?//g" /etc/NetworkManager/conf.d/99-escenario-unmanaged.conf 2>/dev/null || true
  systemctl restart NetworkManager
  sleep 2
  nmcli con delete "temp-internet" >/dev/null 2>&1 || true
  nmcli con add type ethernet ifname "$IF0" con-name "temp-internet" ipv4.method auto ipv6.method ignore >/dev/null
  nmcli con up "temp-internet"
  echo "[OK] Internet activo. Cuando termines, ejecuta: sudo bash $0 $ID fase2"
}

# ==========================================================
# VERIFICACIÓN COMPLETA DEL EQUIPO
# ==========================================================
ejecutar_verificar() {
  echo "=========================================================="
  echo " AUDITORÍA -> $(hostname) (Esperado: ${HOSTNAME_FINAL})"
  echo "=========================================================="

  echo "--- 1. Interfaces e IPs ---"
  ip -br a | grep -v '^lo '

  echo "--- 2. Puerta de enlace (solo CGC-Subu51 debe tener 'default') ---"
  ip route

  echo "--- 3. Enrutamiento IP (debe ser 0) ---"
  sysctl -n net.ipv4.ip_forward

  if [[ "$ROL" == "S" ]]; then
    echo "--- 4. Servicios SSH (${SSH_PORT}) y HTTP (${HTTP_PORT}) ---"
    ss -tulpn | grep -E ":(${SSH_PORT}|${HTTP_PORT})\b" || echo "[FALLO] Algún puerto no escucha"
    echo "--- 5. Parámetros SSH clave ---"
    sshd -T | grep -E '^(port|allowtcpforwarding|gatewayports|passwordauthentication) '
    echo "--- 6. Prueba Web local ---"
    curl -s "http://127.0.0.1:${HTTP_PORT}" | grep -E "<h1>|Puerto" || echo "[FALLO] Apache no responde"
    if [[ -n "$HD_DIR" ]]; then
      echo "--- 7. Carpeta HD simulada ---"
      ls -ld "$HD_DIR"
    fi
  else
    echo "--- 4. Clientes SSH / SSHFS ---"
    ssh -V
    sshfs --version | head -n 1
  fi

  echo "--- 8. Ping a VECINOS directos (deben responder OK) ---"
  for ip in "${VECINOS[@]}"; do
    if ping -c 1 -W 1 "$ip" &>/dev/null; then
      echo "  [OK]    $ip accesible"
    else
      echo "  [FALLO] $ip NO responde (comprueba si esa VM ya está configurada y encendida)"
    fi
  done

  echo "--- 9. Ping a REDES REMOTAS (DEBEN FALLAR para confirmar aislamiento) ---"
  for ip in "${REMOTOS[@]}"; do
    if ping -c 1 -W 1 "$ip" &>/dev/null; then
      echo "  [ERROR AISLAMIENTO] $ip responde y NO debería"
    else
      echo "  [OK AISLADO]        $ip inalcanzable"
    fi
  done
}

case "$MODO" in
  fase1)       ejecutar_fase1 ;;
  fase2)       ejecutar_fase2 ;;
  todo)        ejecutar_fase1 && ejecutar_fase2 ;;
  verificar)   ejecutar_verificar ;;
  internet-on) ejecutar_internet_on ;;
  *) echo "Modo no válido. Usa: todo | fase1 | fase2 | verificar | internet-on"; exit 1 ;;
esac