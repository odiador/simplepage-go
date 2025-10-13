#!/usr/bin/env bash

#############################################
# AUTO-SCALER DEFINITIVO - TODO EN UNO
#############################################
# Este script integra toda la funcionalidad de autoscaling
# sin dependencias de otros scripts externos
# Solo requiere quick_config.sh para variables de entorno
#############################################

# No usar set -e porque el autoscaler debe ser robusto ante errores
# set -e  # Salir si hay algún error

# ============================================================
# Importar configuración centralizada (valores por defecto)
# ============================================================
if [ -f "./quick_config.sh" ]; then
    source ./quick_config.sh
fi

# ============================================================
# Configuración de Auto-Scaling (pueden ser sobreescritos por argumentos)
# ============================================================
UMBRAL_ALTO=${UMBRAL_ALTO:-75}
UMBRAL_CRITICO=${UMBRAL_CRITICO:-85}
UMBRAL_BAJO=${UMBRAL_BAJO:-40}
UMBRAL_MUY_BAJO=${UMBRAL_MUY_BAJO:-25}
INTERVALO_MONITOREO=${INTERVALO_MONITOREO:-20}
MIN_SERVIDORES=${MIN_SERVIDORES:-2}
MAX_SERVIDORES=${MAX_SERVIDORES:-5}
TIEMPO_COOLDOWN=${TIEMPO_COOLDOWN:-60}

# ============================================================
# Configuración de Infraestructura (pueden ser sobreescritos por argumentos)
# ============================================================
BALANCER_HOST=${BALANCER_HOST:-"192.168.56.101"}
BALANCER_USER=${BALANCER_USER:-"debian"}
BALANCER_PASSWORD=${BALANCER_PASSWORD:-"debian"}
BALANCER_PORT=${BALANCER_PORT:-"80"}
VM_USER=${VM_USER:-"debian"}
VM_PASSWORD=${VM_PASSWORD:-"debian"}
NETWORK_RANGE=${NETWORK_RANGE:-"192.168.56.102-254"}
BACKEND_PORT=${BACKEND_PORT:-"8080"}
BASE_VM=${BASE_VM:-"plantilla"}
DISK_PATH=${DISK_PATH:-"/home/amador/VirtualBox VMs/plantilla-servicio/servicioimg.vdi"}

# ============================================================
# Configuración de Prueba Automática (Opcional)
# ============================================================
MODO_PRUEBA=false
FASE_ACTUAL=0
TIEMPO_INICIO=$(date +%s)

# ============================================================
# Archivos y Scripts
# ============================================================
LOG_FILE="./../autoscaler.log"
ESTADO_FILE="/tmp/autoscaler_state"
COOLDOWN_FILE="/tmp/autoscaler_cooldown"

#############################################
# Funciones de Logging
#############################################

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

#############################################
# Función para ejecutar comandos remotos con sudo
#############################################
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

#############################################
# Funciones de Control de Stress (Opcional para Pruebas)
#############################################

control_stress_automatico() {
    local tiempo_actual=$(date +%s)
    local tiempo_transcurrido=$((tiempo_actual - TIEMPO_INICIO))
    
    case $FASE_ACTUAL in
        0)
            if [ $tiempo_transcurrido -ge 60 ]; then
                log_message "🧪 FASE 1: Iniciando stress alto (80%)"
                iniciar_stress_en_balanceador 80 120
                FASE_ACTUAL=1
            fi
            ;;
        1)
            if [ $tiempo_transcurrido -ge 180 ]; then
                log_message "🧪 FASE 2: Subiendo a stress crítico (90%)"
                iniciar_stress_en_balanceador 90 120
                FASE_ACTUAL=2
            fi
            ;;
        2)
            if [ $tiempo_transcurrido -ge 300 ]; then
                log_message "🧪 FASE 3: Bajando stress (30%)"
                iniciar_stress_en_balanceador 30 120
                FASE_ACTUAL=3
            fi
            ;;
        3)
            if [ $tiempo_transcurrido -ge 420 ]; then
                log_message "🧪 FASE 4: Stress muy bajo (20%)"
                iniciar_stress_en_balanceador 20 120
                FASE_ACTUAL=4
            fi
            ;;
        4)
            if [ $tiempo_transcurrido -ge 540 ]; then
                log_message "🧪 FASE 5: Detener stress"
                detener_stress_en_balanceador
                FASE_ACTUAL=5
            fi
            ;;
        5)
            if [ $tiempo_transcurrido -ge 660 ]; then
                log_message "🧪 FASE 6: Finalizando prueba"
                FASE_ACTUAL=6
            fi
            ;;
        6)
            log_message "✅ Prueba automática completada"
            ;;
    esac
}

iniciar_stress_en_balanceador() {
    local carga=$1
    local duracion=$2
    
    detener_stress_en_balanceador
    
    local workers=$(sshpass -p "$BALANCER_PASSWORD" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "${BALANCER_USER}@${BALANCER_HOST}" \
        "nproc | awk '{print int(\$1 * $carga / 100) + 1}'" 2>/dev/null)
    
    workers=${workers:-2}
    
    sshpass -p "$BALANCER_PASSWORD" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "${BALANCER_USER}@${BALANCER_HOST}" \
        "nohup stress-ng --cpu $workers --cpu-load $carga --timeout ${duracion}s > /dev/null 2>&1 &"
    
    log_message "⚡ Stress iniciado en BALANCEADOR: $carga% por ${duracion}s - Workers: $workers"
}

detener_stress_en_balanceador() {
    sshpass -p "$BALANCER_PASSWORD" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "${BALANCER_USER}@${BALANCER_HOST}" \
        "pkill -f stress-ng >/dev/null 2>&1; sleep 2; pkill -9 -f stress-ng >/dev/null 2>&1" || true
    
    log_message "🛑 Stress detenido en balanceador"
}

check_stress_en_balanceador() {
    local running=$(sshpass -p "$BALANCER_PASSWORD" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "${BALANCER_USER}@${BALANCER_HOST}" \
        "pgrep stress-ng >/dev/null && echo 'SI' || echo 'NO'" 2>/dev/null)
    echo "${running:-NO}"
}

#############################################
# Funciones de Monitoreo de CPU del BALANCEADOR
#############################################

get_balancer_cpu() {
    local cpu_usage=0
    
    # Método 1: Usar top en el BALANCEADOR
    cpu_usage=$(sshpass -p "$BALANCER_PASSWORD" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -o ConnectTimeout=10 \
        "${BALANCER_USER}@${BALANCER_HOST}" \
        "top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'%' -f1 | cut -d'.' -f1" 2>/dev/null)
    
    # Si falla top, usar método alternativo
    if [[ ! "$cpu_usage" =~ ^[0-9]+$ ]] || [ -z "$cpu_usage" ]; then
        # Método 2: Usar mpstat en el BALANCEADOR
        cpu_usage=$(sshpass -p "$BALANCER_PASSWORD" ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            -o ConnectTimeout=10 \
            "${BALANCER_USER}@${BALANCER_HOST}" \
            "mpstat 1 1 2>/dev/null | awk '/Average:/ {print 100 - \$NF}' | cut -d'.' -f1" 2>/dev/null)
    fi
    
    # Si aún falla, usar /proc/loadavg como aproximación
    if [[ ! "$cpu_usage" =~ ^[0-9]+$ ]] || [ -z "$cpu_usage" ]; then
        cpu_usage=$(sshpass -p "$BALANCER_PASSWORD" ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            -o ConnectTimeout=10 \
            "${BALANCER_USER}@${BALANCER_HOST}" \
            "awk '{print int(\$1 * 25)}' /proc/loadavg" 2>/dev/null)
    fi
    
    # Validación final
    if [[ "$cpu_usage" =~ ^[0-9]+$ ]] && [ "$cpu_usage" -ge 0 ] && [ "$cpu_usage" -le 100 ]; then
        echo "$cpu_usage"
    else
        log_message "❌ No se pudo obtener CPU del balanceador (valor: '$cpu_usage')"
        echo "0"
    fi
}

#############################################
# Funciones de Gestión de Servidores
#############################################

get_active_servers() {
    # Escanear la red para contar servidores activos
    if ! command -v nmap &>/dev/null; then
        log_message "⚠️  nmap no disponible, intentando con VBoxManage"
        # Contar VMs en ejecución (excluyendo plantilla y balanceador)
        local running_vms=$(VBoxManage list runningvms 2>/dev/null | \
            grep -v "$BASE_VM" | \
            grep -v "balancer" | \
            wc -l)
        echo "${running_vms:-0}"
        return
    fi
    
    local network_prefix=$(echo "$NETWORK_RANGE" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
    local balancer_ip="$BALANCER_HOST"
    
    # Escanear red y obtener todas las IPs activas
    local nmap_output=$(nmap -sn "$NETWORK_RANGE" 2>/dev/null)
    
    # Extraer IPs del output usando grep con regex
    local active_ips=$(echo "$nmap_output" | \
        grep "Nmap scan report for" | \
        grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
        grep -v "^$balancer_ip$" | \
        sort -u | \
        wc -l)
    
    echo "${active_ips:-0}"
}

refresh_server_list() {
    log_message "🔄 Refrescando lista de servidores activos..."
    
    local current_servers=$(get_active_servers)
    log_message "   📊 Servidores detectados en la red: $current_servers"
    
    # Listar IPs activas
    if command -v nmap &>/dev/null; then
        local network_prefix=$(echo "$NETWORK_RANGE" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
        
        local nmap_output=$(nmap -sn "$NETWORK_RANGE" 2>/dev/null)
        
        local all_ips=$(echo "$nmap_output" | \
            grep "Nmap scan report for" | \
            grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
            grep -v "^$BALANCER_HOST$" | \
            sort -u)
        
        if [ -n "$all_ips" ]; then
            log_message "   📋 IPs activas:"
            while IFS= read -r ip; do
                [[ -z "$ip" ]] && continue
                
                local hostname=$(sshpass -p "$VM_PASSWORD" ssh \
                    -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null \
                    -o LogLevel=ERROR \
                    -o ConnectTimeout=2 \
                    -o BatchMode=no \
                    "${VM_USER}@${ip}" "hostname; echo" 2>/dev/null | tr -d '\r\n\t ')
                
                if [[ -n "$hostname" ]]; then
                    log_message "      • $ip → $hostname ✅"
                else
                    log_message "      • $ip → (sin SSH)"
                fi
            done <<< "$all_ips"
            log_message ""
        else
            log_message "   ⚠️  No se detectaron servidores activos"
        fi
    else
        local running_vms=$(VBoxManage list runningvms 2>/dev/null | \
            grep -v "$BASE_VM" | \
            grep -v "balancer")
        
        if [ -n "$running_vms" ]; then
            log_message "   📋 VMs en ejecución:"
            while IFS= read -r vm; do
                log_message "      • $vm"
            done <<< "$running_vms"
        else
            log_message "   ⚠️  No hay VMs en ejecución"
        fi
    fi
    
    echo "$current_servers"
}

count_active_servers() {
    get_active_servers
}

get_backend_servers() {
    # Obtener lista de servidores desde nmap
    if ! command -v nmap &>/dev/null; then
        echo ""
        return
    fi
    
    local nmap_output=$(nmap -sn "$NETWORK_RANGE" 2>/dev/null)
    
    local servers=$(echo "$nmap_output" | \
        grep "Nmap scan report for" | \
        grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
        grep -v "^$BALANCER_HOST$" | \
        sort -u | \
        tr '\n' ' ')
    
    echo $servers
}

#############################################
# Función para detectar IP de una VM
#############################################

detect_vm_ip() {
  local vm_name="$1"
  local network_range="$2"
  local timeout="$3"
  local vm_user="$4"
  local vm_pass="$5"
  
  log_message "🔍 Detectando IP de la VM $vm_name en la red $network_range ..."
  log_message "   Esperando $timeout segundos para que la VM obtenga IP por DHCP..."
  sleep "$timeout"
  
  if ! command -v nmap &>/dev/null; then
    log_message "❌ ERROR: nmap no está instalado"
    return 1
  fi
  
  local max_attempts=5
  local attempt=1
  
  local network_prefix=$(echo "$network_range" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
  
  while [ $attempt -le $max_attempts ]; do
    log_message "   📡 Intento $attempt/$max_attempts: Escaneando rango DHCP con nmap ($network_range)..."
    
    local nmap_output=$(nmap -sn "$network_range" 2>/dev/null)
    
    local all_ips=$(echo "$nmap_output" | \
      grep "Nmap scan report for" | \
      grep -oE "$network_prefix\.[0-9]+" | \
      sort -u)
    
    if [[ -n "$all_ips" ]]; then
      local ips_array=()
      while IFS= read -r line; do
        [[ -n "$line" ]] && ips_array+=("$line")
      done <<< "$all_ips"
      
      local ip_count=${#ips_array[@]}
      log_message "   📋 Se encontraron $ip_count host(s) activo(s), verificando hostnames..."
      
      for ip in "${ips_array[@]}"; do
        log_message "   🔍 Verificando $ip..."
        
        local hostname=$(sshpass -p "$vm_pass" ssh \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          -o LogLevel=ERROR \
          -o ConnectTimeout=3 \
          -o BatchMode=no \
          "${vm_user}@${ip}" "hostname; echo" 2>/dev/null | tr -d '\r\n\t ')
        
        # Buscar VM que tenga el hostname de la plantilla base (servidor1)
        # Esta será la VM recién clonada que aún no ha sido renombrada
        if [[ "$hostname" == "servidor1" ]]; then
          log_message "✅ IP detectada: $ip (hostname: $hostname - VM recién clonada)"
          # Escribir IP a archivo temporal
          echo "$ip" > /tmp/detected_ip_$$
          return 0
        else
          log_message "   ⏭️  Saltando $ip (hostname: ${hostname:-sin acceso SSH})"
        fi
      done
      
      log_message "   ⚠️  No se encontró ninguna VM con hostname 'servidor1' (plantilla) en este intento"
    else
      log_message "   ⚠️  No se encontraron hosts activos con nmap"
    fi
    
    if [ $attempt -lt $max_attempts ]; then
      log_message "   ⏳ Esperando 5 segundos antes de reintentar..."
      sleep 5
    fi
    
    attempt=$((attempt + 1))
  done
  
  log_message "❌ No se pudo detectar la IP después de $max_attempts intentos"
  return 1
}

#############################################
# Función Integrada: AGREGAR SERVIDOR
#############################################

add_server_internal() {
    local vm_name="$1"
    
    log_message "🚀 [ADD_SERVER] Iniciando creación de servidor: $vm_name"
    
    # Validar nombre de VM
    if [[ "$vm_name" == "servidor1" ]]; then
        log_message "❌ ERROR: El nombre 'servidor1' está reservado para la plantilla base"
        return 1
    fi
    
    # Verificar que la VM base existe
    log_message "🔍 Verificando VM base '$BASE_VM'..."
    if ! VBoxManage showvminfo "$BASE_VM" &>/dev/null; then
        log_message "❌ ERROR: La VM base '$BASE_VM' no existe"
        return 1
    fi
    log_message "✅ VM base encontrada"
    
    # Verificar si la VM ya existe
    if VBoxManage showvminfo "$vm_name" &>/dev/null; then
        log_message "⚠️  La VM '$vm_name' ya existe, eliminándola..."
        
        if VBoxManage showvminfo "$vm_name" | grep -q "State:.*running"; then
            log_message "   VM está corriendo, apagándola..."
            VBoxManage controlvm "$vm_name" acpipowerbutton 2>/dev/null || true
            sleep 10
            
            if VBoxManage showvminfo "$vm_name" | grep -q "State:.*running"; then
                VBoxManage controlvm "$vm_name" poweroff
                sleep 3
            fi
        fi
        
        VBoxManage unregistervm "$vm_name" --delete
        log_message "✅ VM eliminada"
    fi
    
    # Clonar VM
    log_message "🌀 Clonando VM '$vm_name' desde '$BASE_VM'..."
    local attempt=1
    local max_attempts=3
    while true; do
        if VBoxManage clonevm "$BASE_VM" --name "$vm_name" --register --mode machine 2>&1; then
            log_message "✅ VM clonada exitosamente"
            break
        else
            if [ $attempt -ge $max_attempts ]; then
                log_message "❌ ERROR: Falló la clonación después de $max_attempts intentos"
                return 1
            fi
            log_message "⚠️  Error en clonación, reintentando..."
            sleep 5
            attempt=$((attempt + 1))
        fi
    done
    
    # Montar disco adicional si existe
    if [[ -n "$DISK_PATH" ]] && [[ -f "$DISK_PATH" ]]; then
        log_message "💾 Montando disco en SATA port 1..."
        VBoxManage storageattach "$vm_name" \
            --storagectl "SATA" \
            --port 1 \
            --device 0 \
            --type hdd \
            --medium "$DISK_PATH" 2>&1 || log_message "⚠️  Advertencia: No se pudo montar el disco"
    fi
    
    # Iniciar VM
    log_message "🚀 Iniciando VM '$vm_name'..."
    VBoxManage startvm "$vm_name" --type headless
    log_message "⏳ Esperando 30 segundos para que la VM inicie completamente..."
    sleep 30
    
    # Detectar IP
    log_message "🔍 Detectando IP de la VM..."
    # Limpiar archivo temporal previo
    rm -f /tmp/detected_ip_$$ 2>/dev/null
    
    # Ejecutar detección (la IP se guarda en archivo temporal)
    if detect_vm_ip "$vm_name" "$NETWORK_RANGE" 15 "$VM_USER" "$VM_PASSWORD"; then
        # Leer IP del archivo temporal
        local detected_ip=$(cat /tmp/detected_ip_$$ 2>/dev/null | tr -d '\r\n ')
        rm -f /tmp/detected_ip_$$ 2>/dev/null
        
        # Validar que sea una IP válida
        if [[ "$detected_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            log_message "✅ IP detectada: $detected_ip"
        else
            log_message "❌ No se pudo detectar la IP automáticamente (resultado inválido: '$detected_ip')"
            return 1
        fi
    else
        rm -f /tmp/detected_ip_$$ 2>/dev/null
        log_message "❌ No se pudo detectar la IP automáticamente"
        return 1
    fi
    
    # Configurar IP estática
    log_message "⚙️  Configurando IP estática $detected_ip en la VM..."
    
    # Esperar un poco más antes de intentar SSH
    log_message "   Esperando 10 segundos adicionales para que SSH esté completamente listo..."
    sleep 10
    
    local ssh_attempt=1
    local max_ssh_attempts=20
    while [ $ssh_attempt -le $max_ssh_attempts ]; do
        if sshpass -p "$VM_PASSWORD" ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            -o ConnectTimeout=5 \
            -o BatchMode=no \
            "${VM_USER}@${detected_ip}" "echo 'SSH OK'; echo" &>/dev/null; then
            log_message "✅ SSH disponible en $detected_ip"
            break
        fi
        log_message "   Intento $ssh_attempt/$max_ssh_attempts - Esperando SSH..."
        sleep 3
        ssh_attempt=$((ssh_attempt + 1))
    done
    
    if [ $ssh_attempt -gt $max_ssh_attempts ]; then
        log_message "❌ ERROR: SSH no está disponible en $detected_ip después de $max_ssh_attempts intentos"
        log_message "   Posibles causas:"
        log_message "   • VM muy lenta al iniciar (hardware limitado)"
        log_message "   • SSH no configurado en la plantilla base"
        log_message "   • Firewall bloqueando puerto 22"
        log_message "   • Problemas de red host-only"
        
        # Verificar si la VM aún responde a ping
        if ping -c 1 -W 2 "$detected_ip" &>/dev/null; then
            log_message "   ℹ️  La VM responde a ping pero no a SSH"
            log_message "   💡 Sugerencia: Verifica que SSH esté instalado y habilitado en la plantilla"
        else
            log_message "   ℹ️  La VM no responde a ping - posible problema de red"
        fi
        
        # No fallar completamente, marcar para limpieza posterior
        log_message "⚠️  Continuando sin configurar esta VM (será limpiada después)"
        
        # Intentar eliminar la VM problemática
        log_message "🧹 Limpiando VM problemática..."
        if VBoxManage showvminfo "$vm_name" &>/dev/null; then
            VBoxManage controlvm "$vm_name" poweroff 2>/dev/null || true
            sleep 3
            VBoxManage unregistervm "$vm_name" --delete 2>/dev/null || true
            log_message "✅ VM problemática eliminada"
        fi
        
        return 1
    fi
    
    local network_prefix=$(echo "$NETWORK_RANGE" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
    local gateway="${network_prefix}.1"
    
    # Configurar red con IP estática
    log_message "   Configurando /etc/network/interfaces..."
    sudo_remote "$detected_ip" "$VM_USER" "$VM_PASSWORD" "
cat > /etc/network/interfaces <<'NETEOF'
source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
allow-hotplug enp0s3
iface enp0s3 inet static
    address $detected_ip
    netmask 255.255.255.0
    gateway $gateway
    dns-nameservers 8.8.8.8 8.8.4.4

# This is an autoconfigured IPv6 interface
iface enp0s3 inet6 auto
NETEOF
"

    # Configurar hostname
    log_message "   Configurando hostname..."
    sudo_remote "$detected_ip" "$VM_USER" "$VM_PASSWORD" "
hostnamectl set-hostname $vm_name
if grep -q '^127\\.0\\.1\\.1' /etc/hosts; then
  sed -i 's|^127\\.0\\.1\\.1.*|127.0.1.1\t$vm_name|' /etc/hosts
else
  sed -i '/^127\\.0\\.0\\.1/a 127.0.1.1\t$vm_name' /etc/hosts
fi
"
    
    # Reiniciar VM
    log_message "🔄 Reiniciando VM para aplicar configuración..."
    VBoxManage controlvm "$vm_name" acpipowerbutton
    sleep 10
    
    while VBoxManage showvminfo "$vm_name" | grep -q "State:.*running"; do
        sleep 3
    done
    
    VBoxManage startvm "$vm_name" --type headless
    sleep 15
    
    # Verificar conectividad
    local ping_attempt=1
    local max_ping=10
    while [ $ping_attempt -le $max_ping ]; do
        if ping -c 1 -W 2 "$detected_ip" &>/dev/null; then
            log_message "✅ VM responde en $detected_ip"
            break
        fi
        sleep 2
        ping_attempt=$((ping_attempt + 1))
    done
    
    # Actualizar HAProxy
    log_message "🔗 Actualizando configuración de HAProxy..."
    regenerate_haproxy_config
    
    log_message "✅ Servidor $vm_name agregado exitosamente ($detected_ip)"
    return 0
}

#############################################
# Función Integrada: ELIMINAR SERVIDOR
#############################################

remove_server_internal() {
    local target_vm_name="$1"
    
    log_message "🗑️  [REMOVE_SERVER] Iniciando eliminación de servidor: $target_vm_name"
    
    # Buscar TODAS las VMs que coincidan por hostname o nombre en VirtualBox
    local vms_to_delete=()
    local vm_ips=()
    
    # Método 1: Buscar en VirtualBox por nombre exacto
    if VBoxManage showvminfo "$target_vm_name" &>/dev/null; then
        vms_to_delete+=("$target_vm_name")
        log_message "✅ VM encontrada en VirtualBox: $target_vm_name"
    fi
    
    # Método 2: Buscar en la red por IP y hostname
    if command -v nmap &>/dev/null; then
        local network_prefix=$(echo "$NETWORK_RANGE" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
        local nmap_output=$(nmap -sn "$NETWORK_RANGE" 2>/dev/null)
        local all_ips=$(echo "$nmap_output" | \
            grep "Nmap scan report for" | \
            grep -oE "$network_prefix\.[0-9]+" | \
            sort -u)
        
        if [[ -n "$all_ips" ]]; then
            while IFS= read -r ip; do
                [[ -z "$ip" ]] && continue
                
                local hostname=$(sshpass -p "$VM_PASSWORD" ssh \
                    -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null \
                    -o LogLevel=ERROR \
                    -o ConnectTimeout=3 \
                    -o BatchMode=no \
                    "${VM_USER}@${ip}" "hostname; echo" 2>/dev/null | tr -d '\r\n\t ')
                
                if [[ "$hostname" == "$target_vm_name" ]]; then
                    vm_ips+=("$ip")
                    log_message "✅ VM encontrada en la red: $target_vm_name en $ip"
                    
                    # Buscar el nombre real de la VM en VirtualBox por MAC address
                    local mac=$(sshpass -p "$VM_PASSWORD" ssh \
                        -o StrictHostKeyChecking=no \
                        -o UserKnownHostsFile=/dev/null \
                        -o LogLevel=ERROR \
                        -o ConnectTimeout=3 \
                        "${VM_USER}@${ip}" "cat /sys/class/net/enp0s3/address 2>/dev/null" | tr -d '\r\n\t ')
                    
                    if [[ -n "$mac" ]]; then
                        # Buscar VM por MAC en VirtualBox
                        local vbox_vm=$(VBoxManage list vms | while read -r line; do
                            local vm_name_quoted=$(echo "$line" | cut -d' ' -f1)
                            local vm_name_clean="${vm_name_quoted//\"/}"
                            
                            local vm_mac=$(VBoxManage showvminfo "$vm_name_clean" --machinereadable 2>/dev/null | \
                                grep "macaddress1=" | cut -d'"' -f2 | \
                                sed 's/../&:/g;s/:$//' | tr '[:upper:]' '[:lower:]')
                            
                            if [[ "$vm_mac" == "$mac" ]]; then
                                echo "$vm_name_clean"
                                break
                            fi
                        done)
                        
                        if [[ -n "$vbox_vm" ]] && [[ "$vbox_vm" != "$target_vm_name" ]]; then
                            vms_to_delete+=("$vbox_vm")
                            log_message "✅ VM real identificada en VirtualBox: $vbox_vm (hostname: $target_vm_name, IP: $ip)"
                        fi
                    fi
                fi
            done <<< "$all_ips"
        fi
    fi
    
    # Eliminar todas las VMs encontradas
    local deleted_count=0
    for vm_name in "${vms_to_delete[@]}"; do
        if VBoxManage showvminfo "$vm_name" &>/dev/null; then
            log_message "🛑 Deteniendo y eliminando VM '$vm_name'..."
            
            if VBoxManage showvminfo "$vm_name" | grep -q "State:.*running"; then
                log_message "   VM está corriendo, apagándola..."
                VBoxManage controlvm "$vm_name" acpipowerbutton 2>/dev/null || true
                sleep 5
                
                if VBoxManage showvminfo "$vm_name" | grep -q "State:.*running"; then
                    VBoxManage controlvm "$vm_name" poweroff
                    sleep 3
                fi
            fi
            
            if VBoxManage unregistervm "$vm_name" --delete 2>&1; then
                log_message "✅ VM '$vm_name' eliminada completamente"
                deleted_count=$((deleted_count + 1))
            else
                log_message "❌ ERROR: No se pudo eliminar la VM '$vm_name'"
            fi
        fi
    done
    
    if [ $deleted_count -eq 0 ]; then
        log_message "⚠️  No se encontraron VMs para eliminar con nombre/hostname: $target_vm_name"
    else
        log_message "✅ Total de VMs eliminadas: $deleted_count"
    fi
    
    # Actualizar HAProxy
    log_message "🔧 Actualizando configuración de HAProxy..."
    regenerate_haproxy_config
    
    log_message "✅ Proceso de eliminación completado"
    return 0
}

#############################################
# Función: REGENERAR CONFIGURACIÓN DE HAPROXY
#############################################

regenerate_haproxy_config() {
    log_message "📡 Escaneando red para detectar servidores activos..."
    
    if ! command -v nmap &>/dev/null; then
        log_message "❌ ERROR: nmap no está disponible"
        return 1
    fi
    
    local network_prefix=$(echo "$NETWORK_RANGE" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
    local nmap_output=$(nmap -sn "$NETWORK_RANGE" 2>/dev/null)
    
    local all_server_ips=$(echo "$nmap_output" | \
        grep "Nmap scan report for" | \
        grep -oE "$network_prefix\.[0-9]+" | \
        sort -u)
    
    local server_ips_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && server_ips_array+=("$line")
    done <<< "$all_server_ips"
    
    log_message "   📋 Se encontraron ${#server_ips_array[@]} host(s) en el rango"
    
    # Recopilar información de servidores válidos
    declare -a valid_servers
    local servers_found=0
    
    for ip in "${server_ips_array[@]}"; do
        local hostname=$(sshpass -p "$VM_PASSWORD" ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            -o ConnectTimeout=3 \
            -o BatchMode=no \
            "${VM_USER}@${ip}" "hostname; echo" 2>/dev/null | tr -d '\r\n\t ')
        
        if [[ -n "$hostname" ]]; then
            log_message "   ✅ Detectado: $hostname ($ip)"
            valid_servers+=("$hostname|$ip")
            servers_found=$((servers_found + 1))
        fi
    done
    
    log_message "   📊 Total de servidores válidos: $servers_found"
    
    # Crear backup
    sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASSWORD" \
        "cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup.\$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    
    # Construir configuración
    local new_config=$(cat <<'HAPROXY_CONFIG'
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

frontend http_front
    bind *:80
    stats uri /haproxy?stats
    stats realm HAProxy\ Statistics
    stats auth admin:admin
    default_backend http_back

backend http_back
    balance random
    option httpchk GET /
HAPROXY_CONFIG
)
    
    # Agregar servidores
    for server_entry in "${valid_servers[@]}"; do
        IFS='|' read -r hostname ip <<< "$server_entry"
        new_config+=$'\n'"    server $hostname $ip:$BACKEND_PORT check"
    done
    
    # Escribir configuración
    sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASSWORD" \
        "cat > /etc/haproxy/haproxy.cfg <<'EOF'
$new_config
EOF"
    
    if [ $? -ne 0 ]; then
        log_message "❌ ERROR: No se pudo escribir la configuración"
        return 1
    fi
    
    log_message "   ✅ Configuración regenerada con $servers_found servidor(es)"
    
    # Recargar o reiniciar HAProxy
    log_message "   🔄 Aplicando configuración en HAProxy..."
    
    # Primero verificar si HAProxy está activo
    local haproxy_status=$(sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASSWORD" \
        "systemctl is-active haproxy" 2>/dev/null | tr -d '\r\n ')
    
    if [[ "$haproxy_status" == "active" ]]; then
        # Si está activo, recargar
        sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASSWORD" \
            "systemctl reload haproxy"
        log_message "   ✅ HAProxy recargado correctamente"
    else
        # Si no está activo, iniciar
        log_message "   ⚠️  HAProxy no estaba activo, iniciando..."
        sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASSWORD" \
            "systemctl start haproxy"
        
        if [ $? -eq 0 ]; then
            log_message "   ✅ HAProxy iniciado correctamente"
        else
            log_message "   ❌ ERROR: No se pudo iniciar HAProxy"
            return 1
        fi
    fi
    
    return 0
}

#############################################
# Función: SETUP INICIAL DEL BALANCEADOR
#############################################

setup_balancer_internal() {
    log_message "🔧 [SETUP_BALANCER] Configurando balanceador HAProxy..."
    
    # Verificar conectividad
    log_message "🔍 Verificando conectividad con $BALANCER_HOST ..."
    if ! ping -c 1 -W 3 "$BALANCER_HOST" &>/dev/null; then
        log_message "❌ ERROR: El host $BALANCER_HOST no responde"
        return 1
    fi
    log_message "✅ Host responde correctamente"
    
    # Verificar acceso SSH
    log_message "🔑 Verificando acceso SSH..."
    if ! sshpass -p "$BALANCER_PASSWORD" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -o ConnectTimeout=10 \
        "${BALANCER_USER}@${BALANCER_HOST}" "echo 'SSH OK'" &>/dev/null; then
        log_message "❌ ERROR: No se pudo conectar vía SSH"
        return 1
    fi
    log_message "✅ Acceso SSH verificado"
    
    # Instalar HAProxy
    log_message "📦 Instalando HAProxy, sysstat y stress-ng..."
    local install_output=$(sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASSWORD" \
        "apt-get update -qq && apt-get install -y haproxy sysstat stress-ng" 2>&1)
    
    if [ $? -ne 0 ]; then
        log_message "❌ ERROR: Falló la instalación de HAProxy"
        return 1
    fi
    log_message "✅ HAProxy instalado correctamente"
    
    # Crear configuración inicial
    log_message "⚙️  Creando configuración inicial de HAProxy..."
    regenerate_haproxy_config
    
    # Habilitar y reiniciar HAProxy
    log_message "🔄 Habilitando e iniciando HAProxy..."
    sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASSWORD" \
        "systemctl enable haproxy && systemctl restart haproxy"
    
    if [ $? -ne 0 ]; then
        log_message "❌ ERROR: No se pudo iniciar HAProxy"
        return 1
    fi
    log_message "✅ HAProxy habilitado y en ejecución"
    
    log_message "✅ Balanceador configurado exitosamente"
    log_message "   URL: http://${BALANCER_HOST}:${BALANCER_PORT}"
    log_message "   Estadísticas: http://${BALANCER_HOST}:${BALANCER_PORT}/haproxy?stats"
    
    return 0
}

#############################################
# Funciones de Control de Escalado
#############################################

ensure_minimum_servers() {
    log_message "🔍 Verificando mínimo de servidores requeridos..."
    
    local current_servers=$(refresh_server_list 2>&1 | tail -1)
    local servers_needed=$((MIN_SERVIDORES - current_servers))
    
    if [ $servers_needed -le 0 ]; then
        log_message "✅ Ya hay suficientes servidores ($current_servers >= $MIN_SERVIDORES)"
        return 0
    fi
    
    log_message "⚠️  Servidores insuficientes: $current_servers de $MIN_SERVIDORES mínimos"
    log_message "🚀 Iniciando $servers_needed servidor(es) para alcanzar el mínimo..."
    
    for ((i=1; i<=servers_needed; i++)); do
        log_message ""
        log_message "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_message "   Agregando servidor $i de $servers_needed"
        log_message "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        local vm_name="servidor-$(date +%s)-$i"
        
        if add_server_internal "$vm_name"; then
            log_message "✅ Servidor $i agregado exitosamente"
            sleep 5
        else
            log_message "❌ Error al agregar servidor $i"
            continue
        fi
    done
    
    sleep 5
    local final_count=$(get_active_servers)
    log_message "📊 Conteo final: $final_count servidores activos"
    
    if [ $final_count -ge $MIN_SERVIDORES ]; then
        log_message "✅ Mínimo de servidores alcanzado"
        return 0
    else
        log_message "⚠️  No se pudo alcanzar el mínimo de servidores"
        return 1
    fi
}

check_cooldown() {
    if [ -f "$COOLDOWN_FILE" ]; then
        local last_action=$(cat "$COOLDOWN_FILE" 2>/dev/null)
        local now=$(date +%s)
        local diff=$((now - last_action))
        
        if [ $diff -lt $TIEMPO_COOLDOWN ]; then
            local remaining=$((TIEMPO_COOLDOWN - diff))
            log_message "⏳ Cooldown activo: ${remaining}s restantes"
            return 1
        fi
    fi
    return 0
}

register_action() {
    date +%s > "$COOLDOWN_FILE"
}

add_server() {
    local is_urgent=${1:-false}
    local current_servers=$(count_active_servers)
    
    if [ $current_servers -ge $MAX_SERVIDORES ]; then
        log_message "❌ Límite máximo alcanzado ($MAX_SERVIDORES servidores)"
        return 1
    fi
    
    log_message "🚀 EJECUTANDO: add_server_internal (servidores: $current_servers → $((current_servers + 1)))"
    
    local vm_name="servidor-$(date +%s)"
    
    log_message ""
    log_message "┌────────────────────────────────────────────────────────┐"
    log_message "│  📦 CREACIÓN DE SERVIDOR - OUTPUT EN TIEMPO REAL      │"
    log_message "└────────────────────────────────────────────────────────┘"
    
    # Redirigir logs de la función con colores
    (
        add_server_internal "$vm_name" 2>&1
    ) | while IFS= read -r line; do
        # Mostrar con color cyan/azul para output de creación
        echo -e "\033[0;36m[CREATE]\033[0m $line" | tee -a "$LOG_FILE"
    done
    
    local exit_code=${PIPESTATUS[0]}
    
    if [ $exit_code -eq 0 ]; then
        log_message ""
        log_message "✅ Servidor agregado exitosamente - VM: $vm_name"
        register_action
        return 0
    else
        log_message ""
        log_message "❌ Error al agregar servidor"
        return 1
    fi
}

remove_server() {
    local is_urgent=${1:-false}
    local current_servers=$(count_active_servers)
    
    if [ $current_servers -le $MIN_SERVIDORES ]; then
        log_message "❌ Mínimo alcanzado ($MIN_SERVIDORES servidores)"
        return 1
    fi
    
    # Buscar VMs en VirtualBox (excluyendo la plantilla base y balanceador)
    local vms_list=$(VBoxManage list runningvms 2>/dev/null | \
        grep -v "\"$BASE_VM\"" | \
        grep -v "balancer" | \
        grep -v "plantilla")
    
    if [[ -z "$vms_list" ]]; then
        log_message "⚠️  No se encontraron VMs en ejecución en VirtualBox"
        
        # Intentar método alternativo: escanear red
        local network_prefix=$(echo "$NETWORK_RANGE" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
        local nmap_output=$(nmap -sn "$NETWORK_RANGE" 2>/dev/null)
        local all_ips=$(echo "$nmap_output" | \
            grep "Nmap scan report for" | \
            grep -oE "$network_prefix\.[0-9]+" | \
            sort -u)
        
        if [[ -z "$all_ips" ]]; then
            log_message "❌ No se encontraron servidores activos en la red"
            return 1
        fi
        
        # Convertir a array
        local ips_array=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && ips_array+=("$line")
        done <<< "$all_ips"
        
        # Obtener hostname del último servidor
        local vm_to_remove=""
        local last_ip="${ips_array[-1]}"
        
        if [[ -n "$last_ip" ]]; then
            vm_to_remove=$(sshpass -p "$VM_PASSWORD" ssh \
                -o StrictHostKeyChecking=no \
                -o UserKnownHostsFile=/dev/null \
                -o LogLevel=ERROR \
                -o ConnectTimeout=3 \
                -o BatchMode=no \
                "${VM_USER}@${last_ip}" "hostname; echo" 2>/dev/null | tr -d '\r\n\t ')
        fi
        
        if [[ -z "$vm_to_remove" ]]; then
            log_message "❌ No se pudo determinar el servidor a eliminar"
            return 1
        fi
        
        last_ip_found="$last_ip"
    else
        # Obtener la última VM de la lista (la más reciente)
        local last_vm=$(echo "$vms_list" | tail -1 | cut -d'"' -f2)
        vm_to_remove="$last_vm"
        
        # Intentar obtener la IP de la VM
        local last_ip_found=$(nmap -sn "$NETWORK_RANGE" 2>/dev/null | \
            grep "Nmap scan report for" | \
            grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
            tail -1)
        
        log_message "✅ VM seleccionada de VirtualBox: $vm_to_remove"
    fi
    
    if [[ -z "$vm_to_remove" ]]; then
        log_message "❌ No se pudo determinar el servidor a eliminar"
        return 1
    fi
    
    log_message "🗑️  EJECUTANDO: remove_server_internal (servidores: $current_servers → $((current_servers - 1)))"
    if [[ -n "$last_ip_found" ]]; then
        log_message "🎯 VM seleccionada para eliminar: $vm_to_remove ($last_ip_found)"
    else
        log_message "🎯 VM seleccionada para eliminar: $vm_to_remove"
    fi
    
    log_message ""
    log_message "┌─────────────────────────────────────────────┐"
    log_message "│   PROCESO DE ELIMINACIÓN DE SERVIDOR       │"
    log_message "└─────────────────────────────────────────────┘"
    
    # Redirigir logs de la función con colores
    (
        remove_server_internal "$vm_to_remove" 2>&1
    ) | while IFS= read -r line; do
        # Mostrar en rojo con prefijo [REMOVE]
        echo -e "\033[0;31m[REMOVE]\033[0m $line" | tee -a "$LOG_FILE"
    done
    
    local exit_code=${PIPESTATUS[0]}
    
    if [ $exit_code -eq 0 ]; then
        log_message ""
        log_message "✅ Servidor eliminado exitosamente - VM: $vm_to_remove"
        register_action
        return 0
    else
        log_message ""
        log_message "❌ Error al eliminar servidor"
        return 1
    fi
}

evaluate_scaling() {
    local cpu_usage=$1
    local active_servers=$2
    local decision="MANTENER"
    
    if ! [[ "$cpu_usage" =~ ^[0-9]+$ ]] || ! [[ "$active_servers" =~ ^[0-9]+$ ]]; then
        echo "MANTENER"
        return
    fi
    
    if [ $cpu_usage -gt $UMBRAL_CRITICO ] && [ $active_servers -lt $MAX_SERVIDORES ]; then
        decision="AGREGAR_URGENTE"
    elif [ $cpu_usage -gt $UMBRAL_ALTO ] && [ $active_servers -lt $MAX_SERVIDORES ]; then
        decision="AGREGAR"
    elif [ $cpu_usage -lt $UMBRAL_MUY_BAJO ] && [ $active_servers -gt $MIN_SERVIDORES ]; then
        decision="ELIMINAR_URGENTE"
    elif [ $cpu_usage -lt $UMBRAL_BAJO ] && [ $active_servers -gt $MIN_SERVIDORES ]; then
        decision="ELIMINAR"
    fi
    
    echo "$decision"
}

show_system_status() {
    local cpu_usage=$1
    local active_servers=$2
    local decision=$3
    local stress_status=$4
    
    if ! [[ "$cpu_usage" =~ ^[0-9]+$ ]]; then
        cpu_usage="ERROR"
    fi
    if ! [[ "$active_servers" =~ ^[0-9]+$ ]]; then
        active_servers="ERROR"
    fi
    
    log_message "📊 SISTEMA | CPU Balanceador: ${cpu_usage}% | Servidores: ${active_servers} | Stress: ${stress_status} | Decisión: ${decision}"
    
    local servers=($(get_backend_servers))
    if [ ${#servers[@]} -gt 0 ]; then
        log_message "   🖥️  Servidores activos: ${servers[*]}"
    fi
}

#############################################
# Funciones de Validación
#############################################

validate_dependencies() {
    local missing_deps=()
    
    if ! command -v sshpass &>/dev/null; then
        missing_deps+=("sshpass")
    fi
    
    if ! command -v nmap &>/dev/null; then
        log_message "⚠️  nmap no está instalado (opcional, pero recomendado)"
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_message "❌ ERROR: Dependencias faltantes: ${missing_deps[*]}"
        log_message "   Instalar con: sudo pacman -S ${missing_deps[*]}"
        return 1
    fi
    
    return 0
}

validate_balancer_connection() {
    if ! sshpass -p "$BALANCER_PASSWORD" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -o ConnectTimeout=5 \
        "${BALANCER_USER}@${BALANCER_HOST}" \
        "echo '✅ Balanceador conectado'" 2>/dev/null; then
        log_message "❌ ERROR: No se puede conectar al balanceador $BALANCER_HOST"
        return 1
    fi
    
    return 0
}

#############################################
# Funciones de Configuración
#############################################

show_help() {
    cat <<EOF
Uso: $0 [opciones]

Descripción:
  Auto-scaler definitivo que monitorea la CPU del balanceador y escala automáticamente.
  Integra toda la funcionalidad en un solo script (solo necesita quick_config.sh).

Opciones:
  --help                    Mostrar esta ayuda
  --modo-prueba             Activar modo de prueba automática con stress
  --umbral-alto <valor>     CPU alta para agregar (default: $UMBRAL_ALTO)
  --umbral-critico <valor>  CPU crítica para agregar urgente (default: $UMBRAL_CRITICO)
  --umbral-bajo <valor>     CPU baja para eliminar (default: $UMBRAL_BAJO)
  --umbral-muy-bajo <valor> CPU muy baja para eliminar urgente (default: $UMBRAL_MUY_BAJO)
  --intervalo <segundos>    Intervalo de monitoreo (default: $INTERVALO_MONITOREO)
  --min-servidores <num>    Mínimo de servidores (default: $MIN_SERVIDORES)
  --max-servidores <num>    Máximo de servidores (default: $MAX_SERVIDORES)
  --cooldown <segundos>     Tiempo de cooldown entre acciones (default: $TIEMPO_COOLDOWN)

Ejemplos:
  $0
  $0 --modo-prueba
  $0 --umbral-alto 80 --max-servidores 10
  $0 --intervalo 30 --cooldown 120

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                show_help
                exit 0
                ;;
            --modo-prueba)
                MODO_PRUEBA=true
                shift
                ;;
            --umbral-alto)
                UMBRAL_ALTO="$2"
                shift 2
                ;;
            --umbral-critico)
                UMBRAL_CRITICO="$2"
                shift 2
                ;;
            --umbral-bajo)
                UMBRAL_BAJO="$2"
                shift 2
                ;;
            --umbral-muy-bajo)
                UMBRAL_MUY_BAJO="$2"
                shift 2
                ;;
            --intervalo)
                INTERVALO_MONITOREO="$2"
                shift 2
                ;;
            --min-servidores)
                MIN_SERVIDORES="$2"
                shift 2
                ;;
            --max-servidores)
                MAX_SERVIDORES="$2"
                shift 2
                ;;
            --cooldown)
                TIEMPO_COOLDOWN="$2"
                shift 2
                ;;
            *)
                log_message "❌ Opción desconocida: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

#############################################
# Loop Principal
#############################################

main() {
    log_message "=========================================="
    log_message "🤖 AUTO-SCALER DEFINITIVO - TODO EN UNO"
    log_message "🎯 Monitoreando: CPU del BALANCEADOR ($BALANCER_HOST)"
    log_message "⚡ Umbrales: Alto=${UMBRAL_ALTO}% Crítico=${UMBRAL_CRITICO}% Bajo=${UMBRAL_BAJO}% MuyBajo=${UMBRAL_MUY_BAJO}%"
    log_message "🔢 Servidores: Mín=${MIN_SERVIDORES} Máx=${MAX_SERVIDORES}"
    log_message "⏰ Intervalo: ${INTERVALO_MONITOREO}s | Cooldown: ${TIEMPO_COOLDOWN}s"
    log_message "📂 Log: $LOG_FILE"
    log_message "=========================================="
    log_message ""
    log_message "📋 POLÍTICA DE ESCALADO:"
    log_message "   ┌─ 🚀 AGREGAR SERVIDOR:"
    log_message "   │  • CPU > ${UMBRAL_ALTO}% (alta) → Agregar 1 servidor"
    log_message "   │  • CPU > ${UMBRAL_CRITICO}% (crítica) → Agregar URGENTE"
    log_message "   │"
    log_message "   └─ 🗑️  ELIMINAR SERVIDOR:"
    log_message "      • CPU < ${UMBRAL_BAJO}% (baja) → Eliminar 1 servidor"
    log_message "      • CPU < ${UMBRAL_MUY_BAJO}% (muy baja) → Eliminar URGENTE"
    log_message ""
    log_message "   ⏱️  Cooldown: ${TIEMPO_COOLDOWN}s entre acciones"
    log_message "   🔄 Refresco: cada $((5 * INTERVALO_MONITOREO))s"
    log_message "=========================================="
    
    # Validaciones
    if ! validate_dependencies; then
        exit 1
    fi
    
    if ! validate_balancer_connection; then
        exit 1
    fi
    
    # Setup automático del balanceador
    log_message ""
    log_message "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_message "   SETUP AUTOMÁTICO DEL BALANCEADOR"
    log_message "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_message ""
    
    # Redirigir logs de la función con colores
    (
        setup_balancer_internal 2>&1
    ) | while IFS= read -r line; do
        # Mostrar en magenta con prefijo [BALANCER]
        echo -e "\033[0;35m[BALANCER]\033[0m $line" | tee -a "$LOG_FILE"
    done
    
    local exit_code=${PIPESTATUS[0]}
    
    if [ $exit_code -eq 0 ]; then
        log_message "✅ Setup del balanceador completado"
    else
        log_message "⚠️  El setup del balanceador falló, pero continuando..."
    fi
    
    log_message ""
    log_message "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_message "   TEST INICIAL DEL SISTEMA"
    log_message "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_message ""
    
    # Test inicial de CPU
    log_message "🔍 Test inicial de CPU del balanceador..."
    initial_cpu=$(get_balancer_cpu)
    log_message "   📊 CPU inicial del balanceador: ${initial_cpu}%"
    
    log_message ""
    log_message "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_message "   INICIALIZACIÓN DE SERVIDORES"
    log_message "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_message ""
    
    initial_servers=$(refresh_server_list 2>&1 | tail -1)
    log_message ""
    
    if [ "$initial_servers" -lt "$MIN_SERVIDORES" ]; then
        log_message "⚠️  Servidores insuficientes detectados"
        if ! ensure_minimum_servers; then
            log_message "❌ No se pudo garantizar el mínimo de servidores"
            log_message "⚠️  El auto-scaler continuará, pero puede haber problemas"
        fi
    else
        log_message "✅ Cantidad de servidores adecuada: $initial_servers >= $MIN_SERVIDORES"
    fi
    
    log_message ""
    log_message "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_message ""
    
    if [ "$MODO_PRUEBA" = true ]; then
        log_message "🧪 MODO PRUEBA ACTIVADO - Se generará carga artificial"
        if ! sshpass -p "$BALANCER_PASSWORD" ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            "${BALANCER_USER}@${BALANCER_HOST}" \
            "which stress-ng" >/dev/null 2>&1; then
            log_message "❌ ERROR: stress-ng no está instalado en el balanceador"
            exit 1
        fi
    fi
    
    log_message ""
    log_message "🚀 Iniciando monitoreo continuo..."
    log_message ""
    
    # Contador para refrescar lista cada N ciclos
    local refresh_counter=0
    local refresh_interval=5
    
    while true; do
        # Control de prueba automática
        if [ "$MODO_PRUEBA" = true ]; then
            control_stress_automatico || true
        fi
        
        # Refrescar lista periódicamente
        refresh_counter=$((refresh_counter + 1))
        if [ $refresh_counter -ge $refresh_interval ]; then
            log_message ""
            log_message "🔄 Refresco periódico de servidores (cada $((refresh_interval * INTERVALO_MONITOREO))s)"
            refresh_server_list > /dev/null 2>&1 || true
            refresh_counter=0
            log_message ""
        fi
        
        # Obtener métricas (con manejo de errores)
        cpu_balancer=$(get_balancer_cpu) || cpu_balancer=0
        servidores_activos=$(count_active_servers) || servidores_activos=0
        stress_status=$(check_stress_en_balanceador) || stress_status="NO"
        
        # Evaluar decisión
        decision=$(evaluate_scaling "$cpu_balancer" "$servidores_activos") || decision="MANTENER"
        
        # Mostrar estado
        show_system_status "$cpu_balancer" "$servidores_activos" "$decision" "$stress_status" || true
        
        # Ejecutar acción
        if [ "$decision" != "MANTENER" ]; then
            case $decision in
                "AGREGAR_URGENTE") 
                    log_message "🚨 AGREGADO URGENTE - CPU balanceador crítica: ${cpu_balancer}%"
                    log_message "⚡ BYPASS de cooldown activado para acción URGENTE"
                    add_server true || log_message "❌ Falló agregar servidor urgente"
                    ;;
                "AGREGAR") 
                    if check_cooldown; then
                        log_message "📈 AGREGANDO - CPU balanceador alta: ${cpu_balancer}%"
                        add_server false || log_message "❌ Falló agregar servidor"
                    fi
                    ;;
                "ELIMINAR_URGENTE") 
                    log_message "📉 ELIMINANDO URGENTE - CPU balanceador muy baja: ${cpu_balancer}%"
                    log_message "⚡ BYPASS de cooldown activado para acción URGENTE"
                    remove_server true || log_message "❌ Falló eliminar servidor urgente"
                    ;;
                "ELIMINAR") 
                    if check_cooldown; then
                        log_message "🔽 ELIMINANDO - CPU balanceador baja: ${cpu_balancer}%"
                        remove_server false || log_message "❌ Falló eliminar servidor"
                    fi
                    ;;
            esac
        fi
        
        sleep $INTERVALO_MONITOREO || sleep 20
    done
}

#############################################
# Manejo de señales
#############################################

cleanup() {
    log_message ""
    log_message "🛑 Auto-Scaler detenido manualmente"
    
    if [ "$MODO_PRUEBA" = true ]; then
        log_message "🧹 Limpiando stress del balanceador..."
        detener_stress_en_balanceador
    fi
    
    log_message "👋 Finalizando..."
    exit 0
}

trap cleanup SIGTERM SIGINT

#############################################
# Punto de entrada
#############################################

parse_arguments "$@"
main
