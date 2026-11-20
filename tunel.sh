#!/usr/bin/env bash

USER_SSH="carlosgc"

mostrar_puertos() {
  echo "=========================================================="
  echo " PUERTOS 9990-9999 ABIERTOS EN $(hostname)"
  echo "=========================================================="
  sudo ss -tulpn | grep -E ':999[0-9]\b' || echo "  (Ningún puerto 9990-9999 en LISTEN)"
  echo ""
  echo "=== PROCESOS SSH CLIENTE ACTIVOS ==="
  pgrep -af "^ssh " || echo "  (Sin túneles SSH activos)"
  echo "=========================================================="
}

limpiar_todo() {
  pkill -f "^ssh -N" 2>/dev/null || true
  fusermount3 -u /mnt/remoto 2>/dev/null || true
  echo "[OK] Túneles SSH cerrados y /mnt/remoto desmontado en $(hostname)."
}

# Atajos rápidos desde terminal: bash t.sh ver | bash t.sh limpiar
case "${1:-}" in
  ver)     mostrar_puertos; exit 0 ;;
  limpiar) limpiar_todo; exit 0 ;;
esac

validar_puerto_tunel() {
  local p="$1"
  if [[ ! "$p" =~ ^999[0-9]$ ]]; then
    echo "[AVISO] El examen solo permite puertos entre 9990 y 9999 (has puesto: $p)."
  fi
}

mostrar_referencia() {
  echo "----------------------------------------------------------"
  echo " SERVIDORES: 51(A,C) 52(A,C,D,E) 53(B,G) 54(C,D) 55(F,G)"
  echo " PUERTOS:    SSH=?022  |  HTTP=?080  |  TÚNELES=9990-9999"
  echo "----------------------------------------------------------"
}

while true; do
  echo ""
  echo "================ ASISTENTE TÚNELES SSH ($(hostname)) ================"
  echo " 1) Túnel DIRECTO  (-L) -> Traer servicio remoto a este equipo"
  echo " 2) Túnel INVERSO  (-R) -> Publicar servicio en un servidor puente"
  echo " 3) Proxy SOCKS5   (-D) -> Salida a Internet / navegación dinámica"
  echo " 4) Montar SSHFS        -> Montar carpeta remota en /mnt/remoto"
  echo " 5) Copiar por SCP      -> Copiar carpeta por SSH (directo o túnel)"
  echo " 6) Auditoría (VER)     -> Mostrar puertos 9990-9999 y procesos SSH"
  echo " 7) Limpiar todo        -> Matar túneles y desmontar /mnt/remoto"
  echo " 0) Salir"
  echo "====================================================================="
  read -rp "Elige opción: " OPC

  case "$OPC" in
    1)
      mostrar_referencia
      read -rp "Puerto local del túnel (9990-9999): " P_LOC
      validar_puerto_tunel "$P_LOC"
      read -rp "Escuchar en [127.0.0.1] (pon 0.0.0.0 si entran otros equipos): " BIND
      BIND="${BIND:-127.0.0.1}"
      read -rp "IP destino final (ej. 56.56.56.55 o 127.0.0.1): " IP_DEST
      read -rp "Puerto destino final (ej. 55080, 53022, 9992): " P_DEST
      read -rp "IP del servidor puente SSH (ej. 54.54.54.52): " IP_SRV
      read -rp "Puerto SSH del servidor puente (ej. 52022 o 9994): " P_SRV

      CMD="ssh -N -p ${P_SRV} -L ${BIND}:${P_LOC}:${IP_DEST}:${P_DEST} ${USER_SSH}@${IP_SRV}"
      echo ""
      echo ">>> COMANDO A EJECUTAR (Ctrl+C para cerrar el túnel):"
      echo "    $CMD"
      echo ""
      $CMD || true
      ;;

    2)
      mostrar_referencia
      read -rp "Puerto remoto en el servidor puente (9990-9999): " P_REM
      validar_puerto_tunel "$P_REM"
      read -rp "Escuchar en el puente [0.0.0.0] (127.0.0.1 para solo local): " BIND
      BIND="${BIND:-0.0.0.0}"
      read -rp "IP destino accesible desde AQUÍ (ej. 51.51.51.53 o 127.0.0.1): " IP_DEST
      read -rp "Puerto destino (ej. 53022, 53080, 9995): " P_DEST
      read -rp "IP del servidor puente SSH (ej. 54.54.54.52): " IP_SRV
      read -rp "Puerto SSH del servidor puente (ej. 52022): " P_SRV

      CMD="ssh -N -p ${P_SRV} -R ${BIND}:${P_REM}:${IP_DEST}:${P_DEST} ${USER_SSH}@${IP_SRV}"
      echo ""
      echo ">>> COMANDO A EJECUTAR (Ctrl+C para cerrar el túnel):"
      echo "    $CMD"
      echo ""
      $CMD || true
      ;;

    3)
      mostrar_referencia
      read -rp "Puerto SOCKS5 local (9990-9999) [9995]: " P_SOCKS
      P_SOCKS="${P_SOCKS:-9995}"
      validar_puerto_tunel "$P_SOCKS"
      read -rp "Escuchar en [127.0.0.1] (pon 0.0.0.0 para compartir en tu red): " BIND
      BIND="${BIND:-127.0.0.1}"
      read -rp "IP servidor con Internet [50.50.50.51]: " IP_SRV
      IP_SRV="${IP_SRV:-50.50.50.51}"
      read -rp "Puerto SSH del servidor [51022]: " P_SRV
      P_SRV="${P_SRV:-51022}"

      CMD="ssh -N -p ${P_SRV} -D ${BIND}:${P_SOCKS} ${USER_SSH}@${IP_SRV}"
      echo ""
      echo ">>> COMANDO A EJECUTAR (Ctrl+C para cerrar el proxy):"
      echo "    $CMD"
      echo ">>> Prueba rápida en otra pestaña:"
      echo "    curl --socks5-hostname ${BIND}:${P_SOCKS} -I https://educacionadistancia.juntadeandalucia.es"
      echo ""
      $CMD || true
      ;;

    4)
      read -rp "IP destino SSH (ej. 54.54.54.52 o 127.0.0.1): " IP_SRV
      read -rp "Puerto SSH o del túnel (ej. 9990 o 53022): " P_SRV
      read -rp "Ruta remota [/mnt/hd_externo_2GB]: " RUTA_REM
      RUTA_REM="${RUTA_REM:-/mnt/hd_externo_2GB}"
      mkdir -p /mnt/remoto

      CMD="sshfs -p ${P_SRV} ${USER_SSH}@${IP_SRV}:${RUTA_REM} /mnt/remoto"
      echo ""
      echo ">>> COMANDO A EJECUTAR:"
      echo "    $CMD"
      echo ""
      $CMD && ls -la /mnt/remoto
      ;;

    5)
      read -rp "Carpeta local a copiar (ej. DirCarlosGC): " DIR_LOC
      read -rp "IP destino (ej. 127.0.0.1): " IP_SRV
      read -rp "Puerto SSH o del túnel (ej. 9990): " P_SRV
      read -rp "Ruta destino [/home/carlosgc/]: " RUTA_DEST
      RUTA_DEST="${RUTA_DEST:-/home/carlosgc/}"

      mkdir -p "$DIR_LOC"
      echo "Archivo de prueba $(date)" > "${DIR_LOC}/prueba.txt"
      CMD="scp -r -P ${P_SRV} ${DIR_LOC} ${USER_SSH}@${IP_SRV}:${RUTA_DEST}"
      echo ""
      echo ">>> COMANDO A EJECUTAR:"
      echo "    $CMD"
      echo ""
      $CMD
      ;;

    6)
      mostrar_puertos
      ;;

    7)
      limpiar_todo
      ;;

    0)
      exit 0
      ;;

    *)
      echo "Opción no válida."
      ;;
  esac
done