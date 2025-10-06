#!/usr/bin/env bash

# ============================================================
# Menú Interactivo para Cluster Management
# ============================================================

set -e

# ============================================================
# Variables por defecto (exportadas para los scripts)
# ============================================================
export BASE_VM="plantilla"
export DISK_PATH="/home/amador/VirtualBox VMs/plantilla-servicio/servicioimg.vdi"
export VM_USER="debian"
export VM_PASSWORD="debian"
export NETWORK_RANGE="192.168.56.102-254"
export BACKEND_PORT="8080"
export BALANCER_HOST="192.168.56.101"
export BALANCER_USER="debian"
export BALANCER_PASSWORD="debian"
export BALANCER_PORT="80"

# ============================================================
# Funciones auxiliares
# ============================================================

# Mostrar banner
show_banner() {
  clear
  echo ""
  echo "════════════════════════════════════════════════════════"
  echo "   🖥️  CLUSTER MANAGEMENT MENU"
  echo "════════════════════════════════════════════════════════"
  echo ""
}

# Mostrar configuración actual
show_config() {
  echo "📋 Configuración actual:"
  echo "   • VM Base:           $BASE_VM"
  echo "   • Disk Path:         $DISK_PATH"
  echo "   • VM User:           $VM_USER"
  echo "   • VM Password:       $VM_PASSWORD"
  echo "   • Network Range:     $NETWORK_RANGE"
  echo "   • Backend Port:      $BACKEND_PORT"
  echo "   • Balancer Host:     $BALANCER_HOST"
  echo "   • Balancer User:     $BALANCER_USER"
  echo "   • Balancer Password: $BALANCER_PASSWORD"
  echo "   • Balancer Port:     $BALANCER_PORT"
  echo ""
}

# Pausa para que el usuario vea el resultado
pause() {
  echo ""
  read -p "Presiona ENTER para continuar..."
}

# ============================================================
# Funciones del menú
# ============================================================

setup_balancer() {
  show_banner
  echo "🔧 CONFIGURAR BALANCEADOR"
  echo "════════════════════════════════════════════════════════"
  echo ""
  show_config
  
  echo "💡 Tip: Usa la opción 6 del menú para editar la configuración"
  echo ""
  
  # Preguntar si quiere escanear la red automáticamente
  read -p "¿Escanear red y agregar servidores automáticamente? (S/n): " scan_network
  
  echo ""
  read -p "¿Continuar con estos parámetros? (S/n): " confirm
  if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo "Operación cancelada"
    pause
    return
  fi
  
  echo ""
  echo "🚀 Ejecutando setup_balancer.sh..."
  echo "════════════════════════════════════════════════════════"
  echo ""
  
  # Construir comando base
  local cmd="./setup_balancer.sh \
    --balancer-host \"$BALANCER_HOST\" \
    --user \"$BALANCER_USER\" \
    --password \"$BALANCER_PASSWORD\" \
    --port \"$BALANCER_PORT\""
  
  # Agregar parámetros de escaneo si el usuario lo solicitó
  if [[ ! "$scan_network" =~ ^[Nn]$ ]]; then
    cmd="$cmd \
    --network-range \"$NETWORK_RANGE\" \
    --vm-user \"$VM_USER\" \
    --vm-password \"$VM_PASSWORD\" \
    --backend-port \"$BACKEND_PORT\""
  fi
  
  # Ejecutar comando
  eval $cmd
  
  pause
}

add_server() {
  show_banner
  echo "➕ AGREGAR SERVIDOR"
  echo "════════════════════════════════════════════════════════"
  echo ""
  show_config
  
  echo "💡 Tip: Usa la opción 6 del menú para editar la configuración"
  echo ""
  
  # Preguntar por el nombre de la VM (obligatorio)
  local vm_name=""
  while [[ -z "$vm_name" ]]; do
    read -p "Nombre de la nueva VM (obligatorio): " vm_name
    if [[ -z "$vm_name" ]]; then
      echo "❌ El nombre de la VM es obligatorio"
    fi
  done
  
  echo ""
  read -p "¿Continuar con estos parámetros? (S/n): " confirm
  if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo "Operación cancelada"
    pause
    return
  fi
  
  echo ""
  echo "🚀 Ejecutando add_server.sh..."
  echo "════════════════════════════════════════════════════════"
  echo ""
  
  ./add_server.sh \
    --base-vm "$BASE_VM" \
    --vm-name "$vm_name" \
    --disk-path "$DISK_PATH" \
    --vm-user "$VM_USER" \
    --vm-password "$VM_PASSWORD" \
    --network-range "$NETWORK_RANGE" \
    --backend-port "$BACKEND_PORT" \
    --balancer-host "$BALANCER_HOST" \
    --balancer-user "$BALANCER_USER" \
    --balancer-pass "$BALANCER_PASSWORD"
  
  pause
}

remove_server() {
  show_banner
  echo "🗑️  ELIMINAR SERVIDOR"
  echo "════════════════════════════════════════════════════════"
  echo ""
  show_config
  
  # Verificar que nmap esté disponible
  if ! command -v nmap &>/dev/null; then
    echo "❌ ERROR: nmap no está instalado"
    echo "   Instálalo con: sudo pacman -S nmap"
    pause
    return
  fi
  
  echo "🔍 Escaneando red $NETWORK_RANGE para listar servidores actuales..."
  echo ""
  
  # Extraer el prefijo de red
  NETWORK_PREFIX=$(echo "$NETWORK_RANGE" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
  
  # Escanear red
  nmap_output=$(nmap -sn "$NETWORK_RANGE" 2>/dev/null)
  
  # Extraer todas las IPs activas
  all_ips=$(echo "$nmap_output" | \
    grep "Nmap scan report for" | \
    grep -oE "$NETWORK_PREFIX\.[0-9]+" | \
    sort -u)
  
  if [[ -z "$all_ips" ]]; then
    echo "⚠️  No se encontraron servidores activos en la red"
    pause
    return
  fi
  
  # Convertir a array
  ips_array=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && ips_array+=("$line")
  done <<< "$all_ips"
  
  echo "📊 Servidores encontrados (${#ips_array[@]} host(s)):"
  echo ""
  
  # Tabla de servidores
  printf "%-18s %-20s %-10s\n" "IP" "HOSTNAME" "ESTADO"
  printf "%-18s %-20s %-10s\n" "──────────────────" "────────────────────" "──────────"
  
  declare -a valid_hostnames
  
  for ip in "${ips_array[@]}"; do
    # Intentar obtener hostname via SSH
    hostname=$(sshpass -p "$VM_PASSWORD" ssh \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR \
      -o ConnectTimeout=2 \
      -o BatchMode=no \
      "${VM_USER}@${ip}" "hostname; echo" 2>/dev/null | tr -d '\r\n\t ')
    
    if [[ -n "$hostname" ]]; then
      ssh_status="✅ OK"
      valid_hostnames+=("$hostname")
    else
      hostname="(sin acceso SSH)"
      ssh_status="❌"
    fi
    
    printf "%-18s %-20s %-10s\n" "$ip" "$hostname" "$ssh_status"
  done
  
  echo ""
  echo "💡 Tip: Usa la opción 7 del menú para editar la configuración"
  echo ""
  
  # Preguntar por el nombre de la VM (obligatorio)
  local vm_name=""
  while [[ -z "$vm_name" ]]; do
    read -p "Nombre de la VM a eliminar (obligatorio): " vm_name
    if [[ -z "$vm_name" ]]; then
      echo "❌ El nombre de la VM es obligatorio"
    fi
  done
  
  echo ""
  read -p "¿Mantener la VM pero removerla del HAProxy? (s/N): " keep_vm
  
  echo ""
  read -p "¿Continuar con estos parámetros? (S/n): " confirm
  if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo "Operación cancelada"
    pause
    return
  fi
  
  echo ""
  echo "🚀 Ejecutando remove_server.sh..."
  echo "════════════════════════════════════════════════════════"
  echo ""
  
  local keep_vm_flag=""
  if [[ "$keep_vm" =~ ^[Ss]$ ]]; then
    keep_vm_flag="--keep-vm"
  fi
  
  ./remove_server.sh \
    --vm-name "$vm_name" \
    --vm-user "$VM_USER" \
    --vm-password "$VM_PASSWORD" \
    --network-range "$NETWORK_RANGE" \
    --backend-port "$BACKEND_PORT" \
    --balancer-host "$BALANCER_HOST" \
    --balancer-user "$BALANCER_USER" \
    --balancer-pass "$BALANCER_PASSWORD" \
    $keep_vm_flag
  
  pause
}

list_servers() {
  show_banner
  echo "📋 LISTAR SERVIDORES EN LA RED"
  echo "════════════════════════════════════════════════════════"
  echo ""
  show_config
  
  # Verificar que nmap esté disponible
  if ! command -v nmap &>/dev/null; then
    echo "❌ ERROR: nmap no está instalado"
    echo "   Instálalo con: sudo pacman -S nmap"
    pause
    return
  fi
  
  echo "🔍 Escaneando red $NETWORK_RANGE..."
  echo ""
  
  # Extraer el prefijo de red
  NETWORK_PREFIX=$(echo "$NETWORK_RANGE" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
  
  # Escanear red
  nmap_output=$(nmap -sn "$NETWORK_RANGE" 2>/dev/null)
  
  # Extraer todas las IPs activas
  all_ips=$(echo "$nmap_output" | \
    grep "Nmap scan report for" | \
    grep -oE "$NETWORK_PREFIX\.[0-9]+" | \
    sort -u)
  
  if [[ -z "$all_ips" ]]; then
    echo "⚠️  No se encontraron servidores activos en la red"
    pause
    return
  fi
  
  # Convertir a array
  ips_array=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && ips_array+=("$line")
  done <<< "$all_ips"
  
  echo "📊 Se encontraron ${#ips_array[@]} host(s) activo(s):"
  echo ""
  
  # Tabla de servidores
  printf "%-18s %-20s %-10s\n" "IP" "HOSTNAME" "SSH"
  printf "%-18s %-20s %-10s\n" "──────────────────" "────────────────────" "──────────"
  
  for ip in "${ips_array[@]}"; do
    # Intentar obtener hostname via SSH
    hostname=$(sshpass -p "$VM_PASSWORD" ssh \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR \
      -o ConnectTimeout=2 \
      -o BatchMode=no \
      "${VM_USER}@${ip}" "hostname; echo" 2>/dev/null | tr -d '\r\n\t ')
    
    if [[ -n "$hostname" ]]; then
      ssh_status="✅ OK"
    else
      hostname="(sin acceso SSH)"
      ssh_status="❌"
    fi
    
    printf "%-18s %-20s %-10s\n" "$ip" "$hostname" "$ssh_status"
  done
  
  echo ""
  echo "💡 Tip: Usa la opción 5 para ver el estado de HAProxy"
  echo ""
  
  pause
}

show_haproxy_status() {
  show_banner
  echo "📊 ESTADO DE HAPROXY"
  echo "════════════════════════════════════════════════════════"
  echo ""
  show_config
  
  echo "🔍 Consultando estado de HAProxy en $BALANCER_HOST..."
  echo ""
  
  sshpass -p "$BALANCER_PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    "${BALANCER_USER}@${BALANCER_HOST}" \
    "echo '$BALANCER_PASSWORD' | sudo -S systemctl status haproxy --no-pager -l; echo" 2>&1 | sed 's/\[sudo\] password for [^:]*://'
  
  echo ""
  echo "📋 Servidores configurados:"
  sshpass -p "$BALANCER_PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    "${BALANCER_USER}@${BALANCER_HOST}" \
    "echo '$BALANCER_PASSWORD' | sudo -S grep '^    server' /etc/haproxy/haproxy.cfg; echo" 2>&1 | sed 's/\[sudo\] password for [^:]*://' || echo '   (ninguno)'
  
  echo ""
  echo "🌐 Panel web de estadísticas:"
  echo "   http://$BALANCER_HOST/haproxy?stats"
  echo "   Usuario: admin / Contraseña: admin"
  echo ""
  
  pause
}

edit_config() {
  show_banner
  echo "⚙️  EDITAR CONFIGURACIÓN"
  echo "════════════════════════════════════════════════════════"
  echo ""
  
  read -p "VM Base [$BASE_VM]: " input
  [[ -n "$input" ]] && export BASE_VM="$input"
  
  read -p "Disk Path [$DISK_PATH]: " input
  [[ -n "$input" ]] && export DISK_PATH="$input"
  
  read -p "VM User [$VM_USER]: " input
  [[ -n "$input" ]] && export VM_USER="$input"
  
  read -sp "VM Password [$VM_PASSWORD]: " input
  echo ""
  [[ -n "$input" ]] && export VM_PASSWORD="$input"
  
  read -p "Network Range [$NETWORK_RANGE]: " input
  [[ -n "$input" ]] && export NETWORK_RANGE="$input"
  
  read -p "Backend Port [$BACKEND_PORT]: " input
  [[ -n "$input" ]] && export BACKEND_PORT="$input"
  
  read -p "Balancer Host [$BALANCER_HOST]: " input
  [[ -n "$input" ]] && export BALANCER_HOST="$input"
  
  read -p "Balancer User [$BALANCER_USER]: " input
  [[ -n "$input" ]] && export BALANCER_USER="$input"
  
  read -sp "Balancer Password [$BALANCER_PASSWORD]: " input
  echo ""
  [[ -n "$input" ]] && export BALANCER_PASSWORD="$input"
  
  read -p "Balancer Port [$BALANCER_PORT]: " input
  [[ -n "$input" ]] && export BALANCER_PORT="$input"
  
  echo ""
  echo "✅ Configuración actualizada"
  pause
}

sync_haproxy() {
  show_banner
  echo "🔄 SINCRONIZAR HAPROXY"
  echo "════════════════════════════════════════════════════════"
  echo ""
  show_config
  
  echo "Esta opción escaneará la red y regenerará la configuración"
  echo "de HAProxy con todos los servidores detectados actualmente."
  echo ""
  echo "💡 Útil cuando:"
  echo "   • Agregaste/eliminaste VMs manualmente"
  echo "   • Hay inconsistencias en la configuración"
  echo "   • Quieres limpiar y reconstruir la configuración"
  echo ""
  
  read -p "¿Continuar? (S/n): " confirm
  if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo "Operación cancelada"
    pause
    return
  fi
  
  echo ""
  echo "🚀 Regenerando configuración de HAProxy..."
  echo "════════════════════════════════════════════════════════"
  echo ""
  
  # Verificar que nmap esté disponible
  if ! command -v nmap &>/dev/null; then
    echo "❌ ERROR: nmap no está instalado"
    echo "   Instálalo con: sudo pacman -S nmap"
    pause
    return
  fi
  
  # Usar setup_balancer.sh con escaneo automático para regenerar
  ./setup_balancer.sh \
    --balancer-host "$BALANCER_HOST" \
    --user "$BALANCER_USER" \
    --password "$BALANCER_PASSWORD" \
    --port "$BALANCER_PORT" \
    --network-range "$NETWORK_RANGE" \
    --vm-user "$VM_USER" \
    --vm-password "$VM_PASSWORD" \
    --backend-port "$BACKEND_PORT"
  
  pause
}

# ============================================================
# Menú principal
# ============================================================
main_menu() {
  while true; do
    show_banner
    show_config
    
    echo "════════════════════════════════════════════════════════"
    echo "OPCIONES:"
    echo "════════════════════════════════════════════════════════"
    echo "  1) 🔧 Configurar Balanceador (setup_balancer.sh)"
    echo "  2) ➕ Agregar Servidor (add_server.sh)"
    echo "  3) 🗑️  Eliminar Servidor (remove_server.sh)"
    echo "  4) 📋 Listar Servidores en la Red"
    echo "  5) 📊 Estado de HAProxy"
    echo "  6) 🔄 Sincronizar HAProxy con la Red"
    echo "  7) ⚙️  Editar Configuración"
    echo "  0) ❌ Salir"
    echo "════════════════════════════════════════════════════════"
    echo ""
    
    read -p "Selecciona una opción [0-7]: " option
    
    case "$option" in
      1) setup_balancer ;;
      2) add_server ;;
      3) remove_server ;;
      4) list_servers ;;
      5) show_haproxy_status ;;
      6) sync_haproxy ;;
      7) edit_config ;;
      0) 
        echo ""
        echo "👋 ¡Hasta luego!"
        echo ""
        exit 0
        ;;
      *)
        echo ""
        echo "❌ Opción inválida. Por favor selecciona 0-7."
        sleep 2
        ;;
    esac
  done
}

# ============================================================
# Verificar que los scripts existen
# ============================================================
if [[ ! -f "./add_server.sh" ]]; then
  echo "❌ ERROR: No se encuentra add_server.sh en el directorio actual"
  exit 1
fi

if [[ ! -f "./remove_server.sh" ]]; then
  echo "❌ ERROR: No se encuentra remove_server.sh en el directorio actual"
  exit 1
fi

if [[ ! -f "./setup_balancer.sh" ]]; then
  echo "❌ ERROR: No se encuentra setup_balancer.sh en el directorio actual"
  exit 1
fi

# Verificar que sshpass esté instalado
if ! command -v sshpass &>/dev/null; then
  echo "⚠️  ADVERTENCIA: sshpass no está instalado"
  echo "   Algunas funciones pueden no funcionar correctamente"
  echo "   Instálalo con: sudo pacman -S sshpass"
  echo ""
  read -p "Presiona ENTER para continuar de todos modos..."
fi

# ============================================================
# Iniciar menú principal
# ============================================================
main_menu