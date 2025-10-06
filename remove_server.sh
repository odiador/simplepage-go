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
    -o LogLevel=ERROR \
    -o ConnectTimeout=30 \
    -o ServerAliveInterval=10 \
    -o ServerAliveCountMax=6 \
    -o Compression=yes \
    "${user}@${host}" \
    "echo '$password' | sudo -S bash -c \"$command\"; echo"
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
  --network-range <rango>   Rango de red completo (ej: 192.168.56.102-254)
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
    --network-range 192.168.56.102-254 \\
    --backend-port 8080 \\
    --balancer-host 192.168.56.2 \\
    --balancer-user debian \\
    --balancer-pass '1234'

Ejemplo 2 (solo remover del HAProxy, mantener VM):
  ./remove_server.sh \\
    --vm-name servidor-10 \\
    --vm-user debian \\
    --vm-password '1234' \\
    --network-range 192.168.56.102-254 \\
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
echo "   📡 Escaneando red $NETWORK_RANGE ..."
nmap_output=$(nmap -sn "$NETWORK_RANGE" 2>/dev/null)

# Extraer el prefijo de red (ej: de "192.168.56.102-254" obtener "192.168.56")
NETWORK_PREFIX=$(echo "$NETWORK_RANGE" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')

# Extraer todas las IPs activas
all_ips=$(echo "$nmap_output" | \
  grep "Nmap scan report for" | \
  grep -oE "$NETWORK_PREFIX\.[0-9]+" | \
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
      -o LogLevel=ERROR \
      -o ConnectTimeout=3 \
      -o BatchMode=no \
      "${VM_USER}@${ip}" "hostname; echo" 2>/dev/null | tr -d '\r\n\t ')
    
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
# Paso 5: Regenerar configuración de HAProxy sin el servidor eliminado
# ============================================================
echo "🔧 [4/5] Regenerando configuración de HAProxy (excluyendo '$VM_NAME')..."

# Verificar que nmap esté disponible
if ! command -v nmap &>/dev/null; then
  echo "❌ ERROR: nmap no está instalado. Instálalo con: sudo pacman -S nmap"
  exit 1
fi

# Escanear red para encontrar todos los servidores disponibles
echo "   📡 Escaneando red para detectar servidores activos..."

# Extraer el prefijo de red (ej: de "192.168.56.102-254" obtener "192.168.56")
NETWORK_PREFIX=$(echo "$NETWORK_RANGE" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')

nmap_output=$(nmap -sn "$NETWORK_RANGE" 2>/dev/null)

# Extraer todas las IPs activas
all_server_ips=$(echo "$nmap_output" | \
  grep "Nmap scan report for" | \
  grep -oE "$NETWORK_PREFIX\.[0-9]+" | \
  sort -u)

# Convertir a array
server_ips_array=()
while IFS= read -r line; do
  [[ -n "$line" ]] && server_ips_array+=("$line")
done <<< "$all_server_ips"

echo "   📋 Se encontraron ${#server_ips_array[@]} host(s) en el rango"
echo ""

# Recopilar información de todos los servidores válidos (excepto el que se está eliminando)
declare -a valid_servers
servers_found=0

for ip in "${server_ips_array[@]}"; do
  # Verificar SSH y obtener hostname
  hostname=$(sshpass -p "$VM_PASS" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -o ConnectTimeout=3 \
    -o BatchMode=no \
    "${VM_USER}@${ip}" "hostname; echo" 2>/dev/null | tr -d '\r\n\t ')
  
  if [[ -z "$hostname" ]]; then
    continue
  fi
  
  # Excluir el servidor que se está eliminando
  if [[ "$hostname" == "$VM_NAME" ]]; then
    echo "   🗑️  Excluyendo $hostname ($ip) de la nueva configuración"
    continue
  fi
  
  echo "   ✅ Manteniendo: $hostname ($ip)"
  
  # Agregar a la lista de servidores válidos
  valid_servers+=("$hostname|$ip")
  servers_found=$((servers_found + 1))
done

echo ""
echo "   📊 Total de servidores en la nueva configuración: $servers_found"
echo ""

# Crear backup de la configuración actual
echo "   💾 Creando backup de configuración..."
sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
  "cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup.\$(date +%Y%m%d_%H%M%S)"

# Regenerar la configuración completa de HAProxy
echo "   ✍️  Regenerando configuración de HAProxy..."

# Construir la nueva configuración
new_config=$(cat <<'HAPROXY_CONFIG'
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

# Frontend - Puerto de entrada
frontend http_front
    bind *:80
    stats uri /haproxy?stats
    stats realm HAProxy\ Statistics
    stats auth admin:admin
    default_backend http_back

#------------------------------------------------------------------------------
# Backend - Servidores de aplicación
#------------------------------------------------------------------------------
backend http_back
    balance random
    option httpchk GET /
HAPROXY_CONFIG
)

# Agregar todos los servidores encontrados (excepto el eliminado)
for server_entry in "${valid_servers[@]}"; do
  IFS='|' read -r hostname ip <<< "$server_entry"
  new_config+=$'\n'"    server $hostname $ip:$BACKEND_PORT check"
done

# Escribir la nueva configuración
sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
  "cat > /etc/haproxy/haproxy.cfg <<'EOF'
$new_config
EOF"

if [ $? -ne 0 ]; then
  echo "❌ ERROR: No se pudo escribir la configuración"
  exit 1
fi

echo "   ✅ Configuración regenerada con $servers_found servidor(es)"
echo ""

# Validar la configuración
echo "   🔍 Validando configuración de HAProxy..."
validation=$(sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
  "haproxy -c -f /etc/haproxy/haproxy.cfg 2>&1")

if echo "$validation" | grep -qi "fatal.*error"; then
  echo "❌ ERROR: Configuración inválida"
  echo "$validation"
  echo ""
  echo "   Restaurando backup..."
  latest_backup=$(sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
    "ls -t /etc/haproxy/haproxy.cfg.backup.* 2>/dev/null | head -1")
  if [[ -n "$latest_backup" ]]; then
    sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
      "cp $latest_backup /etc/haproxy/haproxy.cfg"
    echo "   ✅ Backup restaurado"
  fi
  exit 1
fi

echo "   ✅ Configuración válida"
echo ""

# Mostrar servidores configurados
if [ $servers_found -gt 0 ]; then
  echo "   📋 Servidores configurados:"
  for server_entry in "${valid_servers[@]}"; do
    IFS='|' read -r hostname ip <<< "$server_entry"
    echo "      • $hostname ($ip:$BACKEND_PORT)"
  done
else
  echo "   ⚠️  No quedan servidores en la configuración"
fi
echo ""

# Recargar HAProxy
echo "   🔄 Recargando HAProxy..."
sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
  "systemctl reload haproxy"

if [ $? -ne 0 ]; then
  echo "❌ ERROR: Falló la recarga de HAProxy"
  exit 1
fi
echo "   ✅ HAProxy recargado correctamente"
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
echo "   • VM eliminada:        $VM_NAME"
if [[ -n "$VM_IP" ]]; then
  echo "   • IP anterior:         $VM_IP"
fi
if ! $KEEP_VM; then
  echo "   • VM eliminada de VirtualBox: ✅"
else
  echo "   • VM mantenida en VirtualBox: ✅"
fi
echo "   • Configuración regenerada: ✅"
echo "   • Servidores restantes:     $servers_found"
echo ""
echo "🔍 Verificar estado del balanceador:"
echo "   http://$BALANCER_HOST/haproxy?stats"
echo ""
echo "📁 Backups de configuración disponibles en:"
echo "   $BALANCER_HOST:/etc/haproxy/haproxy.cfg.backup.*"
echo ""
echo "💡 Nota: La configuración se regeneró automáticamente"
echo "   escaneando toda la red. No es necesaria validación manual."
echo ""
echo "════════════════════════════════════════════════════════"
echo ""
