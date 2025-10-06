#!/usr/bin/env bash

# ============================================================
# Script 2: Agregar Servidor al Cluster
# ============================================================
# Este script:
# - Clona una VM desde la plantilla base (con DHCP)
# - Detecta automáticamente la IP asignada por DHCP
# - Configura esa IP como estática en la VM
# - Agrega el servidor al HAProxy del balanceador
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
# Función para detectar IP de una VM en la red host-only
# ============================================================
detect_vm_ip() {
  local vm_name="$1"
  local network_range="$2"
  local timeout="$3"
  local vm_user="$4"
  local vm_pass="$5"
  
  # Todos los mensajes informativos van a stderr (>&2)
  echo "🔍 Detectando IP de la VM $vm_name en la red $network_range ..." >&2
  echo "   Esperando $timeout segundos para que la VM obtenga IP por DHCP..." >&2
  sleep "$timeout"
  echo "" >&2
  
  # Verificar que nmap esté disponible
  if ! command -v nmap &>/dev/null; then
    echo "❌ ERROR: nmap no está instalado. Instálalo con: sudo pacman -S nmap" >&2
    return 1
  fi
  
  # Intentar detectar con nmap (máximo 5 intentos)
  local max_attempts=5
  local attempt=1
  
  while [ $attempt -le $max_attempts ]; do
    echo "   📡 Intento $attempt/$max_attempts: Escaneando rango DHCP con nmap ($network_range.102-254)..." >&2
    
    # Escanear red y obtener todas las IPs activas
    local nmap_output=$(nmap -sn "$network_range.102-254" 2>/dev/null)
    
    # Extraer IPs del output usando grep con regex
    # Formato: "Nmap scan report for 192.168.56.114" o "Nmap scan report for 192.168.56.114 (192.168.56.114)"
    local all_ips=$(echo "$nmap_output" | \
      grep "Nmap scan report for" | \
      grep -oE "$network_range\.[0-9]+" | \
      sort -u)
    
    if [[ -n "$all_ips" ]]; then
      # Convertir a array para iterar correctamente
      local ips_array=()
      while IFS= read -r line; do
        [[ -n "$line" ]] && ips_array+=("$line")
      done <<< "$all_ips"
      
      local ip_count=${#ips_array[@]}
      echo "   📋 Se encontraron $ip_count host(s) activo(s), verificando hostnames..." >&2
      echo "   📝 IPs: ${ips_array[*]}" >&2
      
      # Verificar hostname de cada IP
      for ip in "${ips_array[@]}"; do
        echo "   🔍 Verificando $ip..." >&2
        
        # Intentar obtener hostname via SSH
        local hostname=$(sshpass -p "$vm_pass" ssh \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          -o ConnectTimeout=3 \
          -o BatchMode=no \
          "${vm_user}@${ip}" "hostname" 2>/dev/null | tr -d '\r\n\t ')
        
        if [[ "$hostname" == "servidor1" ]]; then
          echo "✅ IP detectada: $ip (hostname: $hostname)" >&2
          echo "$ip"  # Solo esto va a stdout
          return 0
        else
          echo "   ⏭️  Saltando $ip (hostname: ${hostname:-sin acceso SSH})" >&2
        fi
      done
      
      echo "   ⚠️  No se encontró ninguna VM con hostname 'servidor1' en este intento" >&2
    else
      echo "   ⚠️  No se encontraron hosts activos con nmap" >&2
    fi
    
    # Si no es el último intento, esperar antes de reintentar
    if [ $attempt -lt $max_attempts ]; then
      echo "   ⏳ Esperando 5 segundos antes de reintentar..." >&2
      sleep 5
    fi
    
    attempt=$((attempt + 1))
  done
  
  echo "❌ No se pudo detectar la IP después de $max_attempts intentos" >&2
  return 1
}

# ============================================================
# Mostrar ayuda
# ============================================================
show_help() {
  cat <<EOF
Uso: $0 [opciones]

Descripción:
  Clona una VM, detecta su IP automáticamente, la configura como estática
  y la registra en el balanceador HAProxy.

Opciones:
  --base-vm <nombre>        Nombre de la VM plantilla a clonar
  --vm-name <nombre>        Nombre para la nueva VM clonada
  --disk-path <ruta>        Ruta del disco VDI a montar (opcional)
  --vm-user <usuario>       Usuario SSH de la VM
  --vm-password <pass>      Contraseña sudo de la VM
  --network-range <ip>      Rango de red (ej: 192.168.56)
  --gateway <ip>            Gateway de la red (default: <network-range>.1)
  --backend-port <puerto>   Puerto del servicio backend (default: 8000)
  --balancer-host <ip>      IP del balanceador HAProxy
  --balancer-user <user>    Usuario SSH del balanceador
  --balancer-pass <pass>    Contraseña sudo del balanceador
  --static-ip <ip>          IP estática a asignar (opcional, si se omite se usa la detectada)
  --timeout <segundos>      Timeout para detectar IP (default: 30)
  --help                    Muestra esta ayuda

Ejemplo:
  ./add_server.sh \\
    --base-vm plantilla-servicio \\
    --vm-name servidor-10 \\
    --disk-path /home/discos/srvimg.vdi \\
    --vm-user debian \\
    --vm-password '1234' \\
    --network-range 192.168.56 \\
    --backend-port 8000 \\
    --balancer-host 192.168.56.2 \\
    --balancer-user debian \\
    --balancer-pass '1234'

Requisitos en Arch Linux (host):
  Obligatorios:
    - sshpass: sudo pacman -S sshpass
    - VirtualBox: Ya instalado
  
  Opcionales (para mejor detección de IP):
    - nmap: sudo pacman -S nmap
    - arp-scan: yay -S arp-scan (AUR)

EOF
  exit 0
}

# ============================================================
# Valores por defecto
# ============================================================
BACKEND_PORT=8000
TIMEOUT=10

# ============================================================
# Parseo de argumentos
# ============================================================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-vm) BASE_VM="$2"; shift 2;;
    --vm-name) VM_NAME="$2"; shift 2;;
    --disk-path) DISK_PATH="$2"; shift 2;;
    --vm-user) VM_USER="$2"; shift 2;;
    --vm-password) VM_PASS="$2"; shift 2;;
    --network-range) NETWORK_RANGE="$2"; shift 2;;
    --gateway) GATEWAY="$2"; shift 2;;
    --backend-port) BACKEND_PORT="$2"; shift 2;;
    --balancer-host) BALANCER_HOST="$2"; shift 2;;
    --balancer-user) BALANCER_USER="$2"; shift 2;;
    --balancer-pass) BALANCER_PASS="$2"; shift 2;;
    --static-ip) STATIC_IP="$2"; shift 2;;
    --timeout) TIMEOUT="$2"; shift 2;;
    --help) show_help;;
    *) echo "❌ Opción desconocida: $1"; show_help;;
  esac
done

# ============================================================
# Validar parámetros obligatorios
# ============================================================
if [[ -z "$BASE_VM" || -z "$VM_NAME" || -z "$VM_USER" || -z "$VM_PASS" || 
      -z "$NETWORK_RANGE" || -z "$BALANCER_HOST" || -z "$BALANCER_USER" || -z "$BALANCER_PASS" ]]; then
  echo "❌ ERROR: Faltan parámetros obligatorios."
  echo ""
  show_help
fi

# Configurar gateway por defecto si no se especificó
if [[ -z "$GATEWAY" ]]; then
  GATEWAY="${NETWORK_RANGE}.1"
fi

# ============================================================
# Validar nombre de VM
# ============================================================
if [[ "$VM_NAME" == "servidor1" ]]; then
  echo "❌ ERROR: El nombre 'servidor1' está reservado para la plantilla base."
  echo "   Por favor usa otro nombre para la VM."
  exit 1
fi

# ============================================================
# Banner inicial
# ============================================================
echo ""
echo "════════════════════════════════════════════════════════"
echo "   🖥️  AGREGANDO NUEVO SERVIDOR AL CLUSTER"
echo "════════════════════════════════════════════════════════"
echo "VM Base:      $BASE_VM"
echo "Nueva VM:     $VM_NAME"
echo "Red:          $NETWORK_RANGE.0/24"
echo "Gateway:      $GATEWAY"
echo "Balanceador:  $BALANCER_HOST"
echo "════════════════════════════════════════════════════════"
echo ""

# ============================================================
# Paso 1: Verificar que la VM base existe
# ============================================================
echo "🔍 [1/8] Verificando VM base '$BASE_VM'..."
if ! VBoxManage showvminfo "$BASE_VM" &>/dev/null; then
  echo "❌ ERROR: La VM base '$BASE_VM' no existe."
  echo ""
  echo "VMs disponibles:"
  VBoxManage list vms
  exit 1
fi
echo "✅ VM base encontrada"
echo ""

# ============================================================
# Paso 2: Verificar si la VM ya existe
# ============================================================
echo "🔍 [2/8] Verificando si '$VM_NAME' ya existe..."
if VBoxManage showvminfo "$VM_NAME" &>/dev/null; then
  echo "⚠️  La VM '$VM_NAME' ya existe."
  read -p "¿Deseas eliminarla y recrearla? (y/N): " recreate
  if [[ "$recreate" =~ ^[Yy]$ ]]; then
    echo "🗑️  Eliminando VM existente..."
    VBoxManage unregistervm "$VM_NAME" --delete
    echo "✅ VM eliminada"
  else
    echo "❌ Operación cancelada"
    exit 1
  fi
fi
echo ""

# ============================================================
# Paso 3: Clonar VM
# ============================================================
echo "🌀 [3/8] Clonando VM '$VM_NAME' desde '$BASE_VM'..."
attempt=1
max_attempts=3
while true; do
  echo "   Intento $attempt de $max_attempts..."
  if VBoxManage clonevm "$BASE_VM" --name "$VM_NAME" --register --mode machine 2>&1; then
    echo "✅ VM clonada exitosamente"
    break
  else
    if [ $attempt -ge $max_attempts ]; then
      echo "❌ ERROR: Falló la clonación después de $max_attempts intentos"
      exit 1
    fi
    echo "⚠️  Error en clonación, reintentando en 5 segundos..."
    sleep 5
    attempt=$((attempt + 1))
  fi
done
echo ""

# ============================================================
# Paso 4: Montar disco adicional si se especificó
# ============================================================
if [[ -n "$DISK_PATH" ]]; then
  echo "💾 [4/8] Montando disco en SATA port 1..."
  if VBoxManage storageattach "$VM_NAME" \
      --storagectl "SATA" \
      --port 1 \
      --device 0 \
      --type hdd \
      --medium "$DISK_PATH" 2>&1; then
    echo "✅ Disco montado correctamente"
  else
    echo "⚠️  Advertencia: No se pudo montar el disco (puede que ya esté montado)"
  fi
else
  echo "⏭️  [4/8] No se especificó disco adicional, omitiendo..."
fi
echo ""

# ============================================================
# Paso 5: Iniciar VM y esperar a que arranque
# ============================================================
echo "🚀 [5/8] Iniciando VM '$VM_NAME'..."
VBoxManage startvm "$VM_NAME" --type headless
echo "⏳ Esperando 20 segundos para que la VM inicie y obtenga IP por DHCP..."
sleep 20
echo ""

# ============================================================
# Paso 6: Detectar IP automáticamente
# ============================================================
echo "🔍 [6/8] Detectando IP de la VM..."
if [[ -n "$STATIC_IP" ]]; then
  echo "   Usando IP especificada manualmente: $STATIC_IP"
  DETECTED_IP="$STATIC_IP"
else
  DETECTED_IP=$(detect_vm_ip "$VM_NAME" "$NETWORK_RANGE" "$TIMEOUT" "$VM_USER" "$VM_PASS")
  if [[ -z "$DETECTED_IP" ]]; then
    echo ""
    echo "❌ No se pudo detectar la IP automáticamente."
    echo ""
    echo "Opciones:"
    echo "  1. Espera más tiempo y vuelve a ejecutar el script"
    echo "  2. Usa --static-ip para especificar la IP manualmente"
    echo "  3. Instala nmap o arp-scan para mejor detección:"
    echo "     sudo pacman -S nmap"
    echo "     yay -S arp-scan"
    echo ""
    read -p "¿Deseas ingresar la IP manualmente? (y/N): " manual_ip
    if [[ "$manual_ip" =~ ^[Yy]$ ]]; then
      read -p "Ingresa la IP de la VM: " DETECTED_IP
      if [[ -z "$DETECTED_IP" ]]; then
        echo "❌ IP no válida"
        exit 1
      fi
    else
      echo "❌ Operación cancelada"
      exit 1
    fi
  fi
fi
echo "✅ IP detectada/configurada: $DETECTED_IP"
echo ""

# ============================================================
# Paso 7: Configurar IP estática en la VM
# ============================================================
echo "⚙️  [7/8] Configurando IP estática $DETECTED_IP en la VM..."

# Verificar conectividad SSH
echo "   Verificando SSH en $DETECTED_IP ..."
ssh_attempt=1
max_ssh_attempts=15
while [ $ssh_attempt -le $max_ssh_attempts ]; do
  # Intentar conexión SSH real para verificar disponibilidad y aceptar host key automáticamente
  if sshpass -p "$VM_PASS" ssh \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 \
      -o BatchMode=no \
      "${VM_USER}@${DETECTED_IP}" "echo 'SSH OK'" &>/dev/null; then
    echo "✅ SSH disponible en $DETECTED_IP"
    break
  fi
  echo "   Intento $ssh_attempt/$max_ssh_attempts - Esperando SSH..."
  sleep 2
  ssh_attempt=$((ssh_attempt + 1))
done

if [ $ssh_attempt -gt $max_ssh_attempts ]; then
  echo "❌ ERROR: SSH no está disponible en $DETECTED_IP"
  exit 1
fi

# Configurar red con IP estática
echo "   Configurando /etc/network/interfaces..."
sudo_remote "$DETECTED_IP" "$VM_USER" "$VM_PASS" "
cat > /etc/network/interfaces <<'NETEOF'
source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
allow-hotplug enp0s3
iface enp0s3 inet static
    address $DETECTED_IP
    netmask 255.255.255.0
    gateway $GATEWAY
    dns-nameservers 8.8.8.8 8.8.4.4

# This is an autoconfigured IPv6 interface
iface enp0s3 inet6 auto
NETEOF
echo \"✅ Configuración de red actualizada\"
"

# Configurar hostname
echo "   Configurando hostname..."
sudo_remote "$DETECTED_IP" "$VM_USER" "$VM_PASS" "
hostnamectl set-hostname $VM_NAME
if grep -q '^127\\.0\\.1\\.1' /etc/hosts; then
  sed -i 's|^127\\.0\\.1\\.1.*|127.0.1.1\t$VM_NAME|' /etc/hosts
else
  sed -i '/^127\\.0\\.0\\.1/a 127.0.1.1\t$VM_NAME' /etc/hosts
fi
echo \"✅ Hostname configurado: $VM_NAME\"
"

# Reiniciar VM para aplicar cambios
echo "🔄 Reiniciando VM para aplicar configuración..."
VBoxManage controlvm "$VM_NAME" acpipowerbutton
sleep 10

# Esperar apagado
while VBoxManage showvminfo "$VM_NAME" | grep -q "State:.*running"; do
  echo "   Esperando apagado..."
  sleep 3
done

echo "🚀 Iniciando VM con configuración estática..."
VBoxManage startvm "$VM_NAME" --type headless
sleep 15

# Verificar conectividad en la nueva IP
echo "🔍 Verificando conectividad en $DETECTED_IP ..."
ping_attempt=1
max_ping=10
while [ $ping_attempt -le $max_ping ]; do
  if ping -c 1 -W 2 "$DETECTED_IP" &>/dev/null; then
    echo "✅ VM responde en $DETECTED_IP"
    break
  fi
  echo "   Intento $ping_attempt/$max_ping..."
  sleep 2
  ping_attempt=$((ping_attempt + 1))
done

if [ $ping_attempt -gt $max_ping ]; then
  echo "⚠️  Advertencia: La VM no responde en $DETECTED_IP"
fi
echo ""

# ============================================================
# Paso 8: Agregar servidores al HAProxy
# ============================================================
echo "🔗 [8/8] Agregando servidores al HAProxy en $BALANCER_HOST ..."

# Escanear red para encontrar todos los servidores disponibles
echo "   📡 Escaneando red para detectar servidores..."
nmap_output=$(nmap -sn "$NETWORK_RANGE.102-254" 2>/dev/null)

# Extraer todas las IPs activas
all_server_ips=$(echo "$nmap_output" | \
  grep "Nmap scan report for" | \
  grep -oE "$NETWORK_RANGE\.[0-9]+" | \
  sort -u)

if [[ -z "$all_server_ips" ]]; then
  echo "⚠️  No se encontraron servidores en la red"
  exit 0
fi

# Convertir a array
server_ips_array=()
while IFS= read -r line; do
  [[ -n "$line" ]] && server_ips_array+=("$line")
done <<< "$all_server_ips"

echo "   📋 Se encontraron ${#server_ips_array[@]} host(s) en el rango DHCP"
echo "   📝 IPs: ${server_ips_array[*]}"
echo ""

# Verificar cada IP y agregar al HAProxy
servers_added=0
servers_skipped=0

for ip in "${server_ips_array[@]}"; do
  echo "   🔍 Procesando $ip..."
  
  # Verificar SSH y obtener hostname
  hostname=$(sshpass -p "$VM_PASS" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=3 \
    -o BatchMode=no \
    "${VM_USER}@${ip}" "hostname" 2>/dev/null | tr -d '\r\n\t ')
  
  if [[ -z "$hostname" ]]; then
    echo "   ⏭️  Saltando $ip (sin acceso SSH)"
    servers_skipped=$((servers_skipped + 1))
    continue
  fi
  
  echo "   ✅ Hostname detectado: $hostname"
  
  # Verificar si ya existe en HAProxy
  existing=$(sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
    "grep -c 'server $hostname $ip:$BACKEND_PORT' /etc/haproxy/haproxy.cfg || true")
  
  if [[ "$existing" -gt 0 ]]; then
    echo "   ℹ️  Servidor '$hostname' ya existe en HAProxy (saltando)"
    servers_skipped=$((servers_skipped + 1))
    continue
  fi
  
  # Agregar al HAProxy
  echo "   ➕ Agregando $hostname ($ip:$BACKEND_PORT) al HAProxy..."
  sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
    "echo '    server $hostname $ip:$BACKEND_PORT check' >> /etc/haproxy/haproxy.cfg"
  
  if [ $? -eq 0 ]; then
    echo "   ✅ Servidor '$hostname' agregado correctamente"
    servers_added=$((servers_added + 1))
  else
    echo "   ❌ Error al agregar '$hostname'"
  fi
  echo ""
done

echo "════════════════════════════════════════════════════════"
echo "   📊 RESUMEN DE SERVIDORES"
echo "════════════════════════════════════════════════════════"
echo "   ✅ Agregados:  $servers_added"
echo "   ⏭️  Saltados:   $servers_skipped"
echo "════════════════════════════════════════════════════════"
echo ""

if [ $servers_added -gt 0 ]; then
  # Reiniciar HAProxy solo si se agregaron servidores
  echo "🔄 Recargando HAProxy..."
  sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
    "systemctl reload haproxy"
  
  if [ $? -ne 0 ]; then
    echo "❌ ERROR: Falló la recarga de HAProxy"
    exit 1
  fi
  echo "✅ HAProxy recargado correctamente"
else
  echo "ℹ️  No se agregaron servidores nuevos, no es necesario recargar HAProxy"
fi
echo ""

# ============================================================
# Resumen final
# ============================================================
echo "════════════════════════════════════════════════════════"
echo "   ✅ SERVIDOR AGREGADO EXITOSAMENTE"
echo "════════════════════════════════════════════════════════"
echo ""
echo "📋 Información del servidor:"
echo "   • Nombre VM:   $VM_NAME"
echo "   • IP:          $DETECTED_IP"
echo "   • Puerto:      $BACKEND_PORT"
echo "   • Balanceador: $BALANCER_HOST"
echo ""
echo "🔍 Verificar en HAProxy:"
echo "   http://$BALANCER_HOST/haproxy?stats"
echo ""
echo "🧪 Probar servicio directamente:"
echo "   curl http://$DETECTED_IP:$BACKEND_PORT"
echo ""
echo "════════════════════════════════════════════════════════"
echo ""
