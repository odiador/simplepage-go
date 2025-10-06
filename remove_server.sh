#!/usr/bin/env bash

# ============================================================
# Script 3: Eliminar Servidor del Cluster
# ============================================================
# Este script:
# - Elimina una VM del cluster de VirtualBox
# - Remueve la entrada correspondiente del HAProxy
# - Limpia la configuración del balanceador
# ============================================================

set -e  # Salir si hay algún error

# ============================================================
# Función para ejecutar comandos remotos con sudo
# ============================================================
sudo_remote() {
  local host="$1"
  local user="$2"
  local password="$3"
  local command="$4"

  sshpass -p "$password" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=30 \
    -o ServerAliveInterval=10 \
    -o ServerAliveCountMax=6 \
    -o Compression=yes \
    "${user}@${host}" \
    "echo '$password' | sudo -S bash -c \"$command\""
}

# ============================================================
# Mostrar ayuda
# ============================================================
show_help() {
  cat <<EOF
Uso: $0 [opciones]

Descripción:
  Elimina una VM del cluster y la remueve de la configuración de HAProxy.

Opciones:
  --vm-name <nombre>        Nombre de la VM a eliminar
  --vm-user <usuario>       Usuario SSH de la VM
  --vm-password <pass>      Contraseña SSH de la VM
  --network-range <ip>      Rango de red (ej: 192.168.56)
  --backend-port <puerto>   Puerto del servicio backend (default: 8080)
  --balancer-host <ip>      IP del balanceador HAProxy
  --balancer-user <user>    Usuario SSH del balanceador
  --balancer-pass <pass>    Contraseña sudo del balanceador
  --force                   No pedir confirmación antes de eliminar
  --keep-vm                 Mantener la VM pero eliminarla solo del HAProxy
  --help                    Muestra esta ayuda

Ejemplo 1 (eliminar VM y configuración):
  ./remove_server.sh \\
    --vm-name servidor-10 \\
    --vm-user debian \\
    --vm-password '1234' \\
    --network-range 192.168.56 \\
    --backend-port 8080 \\
    --balancer-host 192.168.56.2 \\
    --balancer-user debian \\
    --balancer-pass '1234'

Ejemplo 2 (solo remover del HAProxy, mantener VM):
  ./remove_server.sh \\
    --vm-name servidor-10 \\
    --vm-user debian \\
    --vm-password '1234' \\
    --network-range 192.168.56 \\
    --balancer-host 192.168.56.2 \\
    --balancer-user debian \\
    --balancer-pass '1234' \\
    --keep-vm

Requisitos en Arch Linux (host):
  - sshpass: sudo pacman -S sshpass
  - nmap: sudo pacman -S nmap
  - VirtualBox: Ya instalado

EOF
  exit 0
}

# ============================================================
# Valores por defecto
# ============================================================
FORCE=false
KEEP_VM=false
BACKEND_PORT=8080

# ============================================================
# Parseo de argumentos
# ============================================================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vm-name) VM_NAME="$2"; shift 2;;
    --vm-user) VM_USER="$2"; shift 2;;
    --vm-password) VM_PASS="$2"; shift 2;;
    --network-range) NETWORK_RANGE="$2"; shift 2;;
    --backend-port) BACKEND_PORT="$2"; shift 2;;
    --balancer-host) BALANCER_HOST="$2"; shift 2;;
    --balancer-user) BALANCER_USER="$2"; shift 2;;
    --balancer-pass) BALANCER_PASS="$2"; shift 2;;
    --force) FORCE=true; shift;;
    --keep-vm) KEEP_VM=true; shift;;
    --help) show_help;;
    *) echo "❌ Opción desconocida: $1"; show_help;;
  esac
done

# ============================================================
# Validar parámetros obligatorios
# ============================================================
if [[ -z "$VM_NAME" || -z "$VM_USER" || -z "$VM_PASS" || -z "$NETWORK_RANGE" || 
      -z "$BALANCER_HOST" || -z "$BALANCER_USER" || -z "$BALANCER_PASS" ]]; then
  echo "❌ ERROR: Faltan parámetros obligatorios."
  echo ""
  show_help
fi

# ============================================================
# Banner inicial
# ============================================================
echo ""
echo "════════════════════════════════════════════════════════"
echo "   🗑️  ELIMINANDO SERVIDOR DEL CLUSTER"
echo "════════════════════════════════════════════════════════"
echo "VM:           $VM_NAME"
echo "Balanceador:  $BALANCER_HOST"
if $KEEP_VM; then
  echo "Modo:         Solo remover de HAProxy (mantener VM)"
else
  echo "Modo:         Eliminar VM completamente"
fi
echo "════════════════════════════════════════════════════════"
echo ""

# ============================================================
# Paso 1: Escanear red y encontrar la VM por hostname usando nmap
# ============================================================
echo "🔍 [1/5] Buscando VM '$VM_NAME' en la red usando nmap..."

# Verificar que nmap esté disponible
if ! command -v nmap &>/dev/null; then
  echo "❌ ERROR: nmap no está instalado. Instálalo con: sudo pacman -S nmap"
  exit 1
fi

# Escanear red
echo "   📡 Escaneando red $NETWORK_RANGE.0/24 ..."
nmap_output=$(nmap -sn "$NETWORK_RANGE.102-254" 2>/dev/null)

# Extraer todas las IPs activas
all_ips=$(echo "$nmap_output" | \
  grep "Nmap scan report for" | \
  grep -oE "$NETWORK_RANGE\.[0-9]+" | \
  sort -u)

VM_IP=""
VM_FOUND=false

if [[ -n "$all_ips" ]]; then
  # Convertir a array
  ips_array=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && ips_array+=("$line")
  done <<< "$all_ips"
  
  echo "   📋 Se encontraron ${#ips_array[@]} host(s) activo(s)"
  echo "   🔍 Buscando hostname '$VM_NAME'..."
  
  # Buscar la IP que corresponde al hostname
  for ip in "${ips_array[@]}"; do
    # Intentar obtener hostname via SSH
    hostname=$(sshpass -p "$VM_PASS" ssh \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=3 \
      -o BatchMode=no \
      "${VM_USER}@${ip}" "hostname" 2>/dev/null | tr -d '\r\n\t ')
    
    if [[ "$hostname" == "$VM_NAME" ]]; then
      VM_IP="$ip"
      VM_FOUND=true
      echo "   ✅ VM encontrada: $VM_NAME en $VM_IP"
      break
    fi
  done
  
  if ! $VM_FOUND; then
    echo "   ⚠️  No se encontró ninguna VM con hostname '$VM_NAME' en la red"
  fi
else
  echo "   ⚠️  No se encontraron hosts activos en la red"
fi

# Verificar si la VM existe en VirtualBox
if VBoxManage showvminfo "$VM_NAME" &>/dev/null; then
  echo "   ✅ VM '$VM_NAME' existe en VirtualBox"
  vm_state=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep "VMState=" | cut -d'"' -f2)
  echo "   Estado: $vm_state"
else
  if ! $KEEP_VM; then
    echo "   ⚠️  VM '$VM_NAME' no existe en VirtualBox"
  fi
fi
echo ""

# ============================================================
# Paso 2: Detener y eliminar VM (si no es --keep-vm)
# ============================================================
if ! $KEEP_VM; then
  echo "🛑 [2/5] Deteniendo y eliminando VM '$VM_NAME'..."
  
  # Verificar si la VM está corriendo
  if VBoxManage showvminfo "$VM_NAME" | grep -q "State:.*running"; then
    echo "   VM está corriendo, apagándola..."
    
    # Intentar apagado limpio primero
    VBoxManage controlvm "$VM_NAME" acpipowerbutton 2>/dev/null || true
    echo "   Esperando apagado limpio (10 segundos)..."
    sleep 10
    
    # Si todavía está corriendo, forzar apagado
    if VBoxManage showvminfo "$VM_NAME" | grep -q "State:.*running"; then
      echo "   Forzando apagado..."
      VBoxManage controlvm "$VM_NAME" poweroff
      sleep 3
    fi
    
    echo "✅ VM detenida"
  else
    echo "   VM ya está detenida"
  fi
  
  # Eliminar VM y todos sus archivos
  echo "   Eliminando VM y archivos asociados..."
  if VBoxManage unregistervm "$VM_NAME" --delete 2>&1; then
    echo "✅ VM eliminada completamente"
  else
    echo "❌ ERROR: No se pudo eliminar la VM"
    exit 1
  fi
else
  echo "⏭️  [2/5] Saltando eliminación de VM (--keep-vm activo)"
fi
echo ""

# ============================================================
# Paso 4: Verificar conectividad con el balanceador
# ============================================================
echo "🔍 [3/5] Verificando conectividad con balanceador..."
if ! ping -c 1 -W 3 "$BALANCER_HOST" &>/dev/null; then
  echo "❌ ERROR: El balanceador $BALANCER_HOST no responde"
  exit 1
fi
echo "✅ Balanceador accesible"
echo ""

# ============================================================
# Paso 5: Eliminar entrada del HAProxy usando hostname + IP + puerto
# ============================================================
echo "🔧 [4/5] Eliminando '$VM_NAME' del HAProxy..."

if [[ -z "$VM_IP" ]]; then
  echo "⚠️  No se detectó la IP de la VM"
  echo "   Intentando eliminar solo por hostname..."
  
  # Verificar que la entrada existe
  entry_count=$(sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
    "grep -c 'server $VM_NAME' /etc/haproxy/haproxy.cfg || true")
  
  if [[ "$entry_count" -eq 0 ]]; then
    echo "⚠️  El servidor '$VM_NAME' no está registrado en HAProxy"
    echo "   No hay nada que eliminar de la configuración"
  else
    echo "   Encontradas $entry_count entrada(s), eliminando..."
    
    # Hacer backup de la configuración
    echo "   Creando backup de configuración..."
    sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
      "cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup.\$(date +%Y%m%d_%H%M%S)"
    
    # Mostrar la línea antes de eliminar
    echo "   📋 Contenido actual:"
    sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
      "grep 'server $VM_NAME' /etc/haproxy/haproxy.cfg"
    
    # Eliminar todas las líneas que contengan el servidor (formato: "    server nombre ...")
    sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
      "sed -i '/^    server $VM_NAME /d' /etc/haproxy/haproxy.cfg"
    
    if [ $? -ne 0 ]; then
      echo "❌ ERROR: No se pudo actualizar la configuración de HAProxy"
      exit 1
    fi
    
    # Mostrar el archivo modificado
    echo "   📄 Archivo después de eliminar:"
    sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
      "cat /etc/haproxy/haproxy.cfg"
    echo ""
    
    echo "✅ Entrada eliminada de HAProxy"
  fi
else
  echo "   Buscando entrada con hostname '$VM_NAME' e IP '$VM_IP:$BACKEND_PORT'..."
  
  # Verificar que la entrada existe con IP específica
  entry_count=$(sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
    "grep -c 'server $VM_NAME $VM_IP:$BACKEND_PORT' /etc/haproxy/haproxy.cfg || true")
  
  if [[ "$entry_count" -eq 0 ]]; then
    echo "⚠️  El servidor '$VM_NAME $VM_IP:$BACKEND_PORT' no está registrado en HAProxy"
    echo "   Intentando buscar solo por hostname..."
    
    entry_count=$(sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
      "grep -c 'server $VM_NAME' /etc/haproxy/haproxy.cfg || true")
    
    if [[ "$entry_count" -eq 0 ]]; then
      echo "⚠️  No se encontró ninguna entrada para '$VM_NAME'"
    else
      echo "   Encontradas $entry_count entrada(s) por hostname, eliminando..."
      
      # Hacer backup de la configuración
      echo "   Creando backup de configuración..."
      sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
        "cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup.\$(date +%Y%m%d_%H%M%S)"
      
      # Mostrar la línea antes de eliminar
      echo "   📋 Contenido actual:"
      sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
        "grep 'server $VM_NAME' /etc/haproxy/haproxy.cfg"
      
      # Eliminar por hostname (formato: "    server nombre ...")
      sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
        "sed -i '/^    server $VM_NAME /d' /etc/haproxy/haproxy.cfg"
      
      if [ $? -ne 0 ]; then
        echo "❌ ERROR: No se pudo actualizar la configuración de HAProxy"
        exit 1
      fi
      
      # Mostrar el archivo modificado
      echo "   📄 Archivo después de eliminar:"
      sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
        "cat /etc/haproxy/haproxy.cfg"
      echo ""
      
      echo "✅ Entrada eliminada de HAProxy"
    fi
  else
    echo "   ✅ Encontrada entrada exacta: 'server $VM_NAME $VM_IP:$BACKEND_PORT'"
    
    # Hacer backup de la configuración
    echo "   Creando backup de configuración..."
    sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
      "cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup.\$(date +%Y%m%d_%H%M%S)"
    
    # Mostrar la línea antes de eliminar
    echo "   📋 Contenido actual:"
    sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
      "grep 'server $VM_NAME' /etc/haproxy/haproxy.cfg"
    
    # Eliminar la línea específica con IP (formato: "    server nombre ip:puerto check")
    sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
      "sed -i '/^    server $VM_NAME $VM_IP:$BACKEND_PORT check$/d' /etc/haproxy/haproxy.cfg"
    
    if [ $? -ne 0 ]; then
      echo "❌ ERROR: No se pudo actualizar la configuración de HAProxy"
      exit 1
    fi
    
    # Mostrar el archivo modificado
    echo "   📄 Archivo después de eliminar:"
    sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
      "cat /etc/haproxy/haproxy.cfg"
    echo ""
    
    echo "✅ Entrada eliminada de HAProxy"
  fi
fi

# Continuar con validación solo si se eliminó algo
entry_count=$(sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
  "grep -c 'server $VM_NAME' /etc/haproxy/haproxy.cfg || true")

if [[ "$entry_count" -gt 0 ]]; then
  echo "⚠️  Advertencia: Aún quedan $entry_count entrada(s) con '$VM_NAME' en HAProxy"
else
  # Validar configuración de HAProxy
  echo "   Validando configuración..."
  validation=$(sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
    "haproxy -c -f /etc/haproxy/haproxy.cfg 2>&1")
  
  echo "   📋 Resultado de validación:"
  echo "$validation"
  echo ""
  
  if echo "$validation" | grep -qi "fatal.*error"; then
    echo "❌ ERROR: Configuración inválida - se encontraron errores fatales"
    echo ""
    echo "Restaurando backup..."
    # Obtener el archivo de backup más reciente
    latest_backup=$(sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
      "ls -t /etc/haproxy/haproxy.cfg.backup.* 2>/dev/null | head -1")
    if [[ -n "$latest_backup" ]]; then
      sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
        "cp $latest_backup /etc/haproxy/haproxy.cfg"
      echo "✅ Backup restaurado"
    else
      echo "⚠️  No se encontró backup reciente"
    fi
    exit 1
  else
    echo "✅ Configuración válida"
  fi
  
  # Recargar HAProxy
  echo "🔄 Recargando HAProxy..."
  sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
    "systemctl reload haproxy"
  
  if [ $? -ne 0 ]; then
    echo "❌ ERROR: No se pudo recargar HAProxy"
    exit 1
  fi
  echo "✅ HAProxy recargado correctamente"
fi
echo ""

# ============================================================
# Paso 6: Verificar estado final y mostrar servidores restantes
# ============================================================
echo "🔍 [5/5] Verificando estado de HAProxy..."
status_output=$(sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
  "systemctl status haproxy --no-pager -l | head -15" 2>&1)

if echo "$status_output" | grep -q "active (running)"; then
  echo "✅ HAProxy está funcionando correctamente"
else
  echo "⚠️  HAProxy podría tener problemas:"
  echo "$status_output"
fi
echo ""

# ============================================================
# Mostrar configuración actual
# ============================================================
echo "📋 Servidores actuales en HAProxy:"
sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
  "grep '^    server' /etc/haproxy/haproxy.cfg || echo '   (ninguno)'"
echo ""

# ============================================================
# Resumen final
# ============================================================
echo "════════════════════════════════════════════════════════"
echo "   ✅ SERVIDOR ELIMINADO EXITOSAMENTE"
echo "════════════════════════════════════════════════════════"
echo ""
echo "📋 Resumen:"
echo "   • VM:          $VM_NAME"
if [[ -n "$VM_IP" ]]; then
  echo "   • IP:          $VM_IP"
fi
echo "   • Puerto:      $BACKEND_PORT (especificado)"
if ! $KEEP_VM; then
  echo "   • VM eliminada de VirtualBox"
fi
echo "   • Entrada removida de HAProxy"
echo "   • Configuración actualizada y validada"
echo ""
echo "⚠️  NOTA: Si tu servidor usaba un puerto diferente a $BACKEND_PORT,"
echo "   verifica manualmente el archivo de configuración:"
echo "   ssh ${BALANCER_USER}@${BALANCER_HOST} 'cat /etc/haproxy/haproxy.cfg'"
echo ""
echo "🔍 Verificar estado del balanceador:"
echo "   http://$BALANCER_HOST/haproxy?stats"
echo ""
echo "📁 Backups de configuración disponibles en:"
echo "   $BALANCER_HOST:/etc/haproxy/haproxy.cfg.backup.*"
echo ""
echo "════════════════════════════════════════════════════════"
echo ""
