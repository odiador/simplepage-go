#!/usr/bin/env bash

#############################################
# Auto-Scaler con Monitoreo de Estrés del Balanceador
# Monitorea CPU del BALANCEADOR y escala automáticamente
#############################################

# ============================================================
# Configuración de Auto-Scaling
# ============================================================
UMBRAL_ALTO=75
UMBRAL_CRITICO=85
UMBRAL_BAJO=40
UMBRAL_MUY_BAJO=25
INTERVALO_MONITOREO=20
MIN_SERVIDORES=2
MAX_SERVIDORES=5
TIEMPO_COOLDOWN=60

# ============================================================
# Configuración de Infraestructura
# ============================================================
BALANCER_HOST="192.168.56.101"
BALANCER_USER="debian"
BALANCER_PASSWORD="debian"
VM_USER="debian"
VM_PASSWORD="debian"
NETWORK_RANGE="192.168.56.102-254"
BACKEND_PORT="8080"

# ============================================================
# Configuración de Prueba Automática (Opcional)
# ============================================================
MODO_PRUEBA=false
FASE_ACTUAL=0
TIEMPO_INICIO=$(date +%s)

# ============================================================
# Archivos y Scripts
# ============================================================
LOG_FILE="./autoscaler.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_AGREGAR="$SCRIPT_DIR/quick_add_server.sh"
SCRIPT_ELIMINAR="$SCRIPT_DIR/quick_remove_server.sh"
ESTADO_FILE="/tmp/autoscaler_state"
COOLDOWN_FILE="/tmp/autoscaler_cooldown"

#############################################
# Funciones de Logging
#############################################

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

#############################################
# Funciones de Control de Stress (Opcional para Pruebas)
#############################################

control_stress_automatico() {
    local tiempo_actual=$(date +%s)
    local tiempo_transcurrido=$((tiempo_actual - TIEMPO_INICIO))
    
    case $FASE_ACTUAL in
        0)
            if [ $tiempo_transcurrido -ge 0 ]; then
                log_message "🎯 FASE 0: Sistema estable - 30s"
                iniciar_stress_en_balanceador 30 30
                FASE_ACTUAL=1
            fi
            ;;
        1)
            if [ $tiempo_transcurrido -ge 30 ]; then
                log_message "🎯 FASE 1: Carga normal 50% - 60s"
                iniciar_stress_en_balanceador 50 60
                FASE_ACTUAL=2
            fi
            ;;
        2)
            if [ $tiempo_transcurrido -ge 90 ]; then
                log_message "🎯 FASE 2: Carga alta 80% - 90s - ESPERAR ESCALADO"
                iniciar_stress_en_balanceador 80 90
                FASE_ACTUAL=3
            fi
            ;;
        3)
            if [ $tiempo_transcurrido -ge 180 ]; then
                log_message "🎯 FASE 3: Carga crítica 95% - 60s - ESPERAR ESCALADO URGENTE"
                iniciar_stress_en_balanceador 95 60
                FASE_ACTUAL=4
            fi
            ;;
        4)
            if [ $tiempo_transcurrido -ge 240 ]; then
                log_message "🎯 FASE 4: Carga baja 20% - 90s - ESPERAR DESESCALADO"
                iniciar_stress_en_balanceador 20 90
                FASE_ACTUAL=5
            fi
            ;;
        5)
            if [ $tiempo_transcurrido -ge 330 ]; then
                log_message "🎯 FASE 5: Finalizando prueba - Limpiar sistema"
                detener_stress_en_balanceador
                FASE_ACTUAL=6
            fi
            ;;
        6)
            log_message "✅ PRUEBA AUTOMÁTICA COMPLETADA - Modo monitoreo normal"
            MODO_PRUEBA=false
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
            grep -v "plantilla" | \
            grep -v "balanceador" | \
            wc -l)
        echo "${running_vms:-0}"
        return
    fi
    
    local network_prefix=$(echo "$NETWORK_RANGE" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
    local balancer_ip="$BALANCER_HOST"
    
    # Escanear red y obtener todas las IPs activas
    local nmap_output=$(nmap -sn "$NETWORK_RANGE" 2>/dev/null)
    
    # Extraer IPs del output usando grep con regex
    # Formato: "Nmap scan report for 192.168.56.114" o "Nmap scan report for 192.168.56.114 (192.168.56.114)"
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
        # Extraer el prefijo de red
        local network_prefix=$(echo "$NETWORK_RANGE" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
        
        # Escanear red y obtener todas las IPs activas
        local nmap_output=$(nmap -sn "$NETWORK_RANGE" 2>/dev/null)
        
        # Extraer IPs del output usando grep con regex
        # Formato: "Nmap scan report for 192.168.56.114" o "Nmap scan report for 192.168.56.114 (192.168.56.114)"
        local all_ips=$(echo "$nmap_output" | \
            grep "Nmap scan report for" | \
            grep -oE "$network_prefix\.[0-9]+" | \
            grep -v "^$BALANCER_HOST$" | \
            sort -u)
        
        if [ -n "$all_ips" ]; then
            # Convertir a array
            local ips_array=()
            while IFS= read -r line; do
                [[ -n "$line" ]] && ips_array+=("$line")
            done <<< "$all_ips"
            
            log_message "   🖥️  Servidores activos (${#ips_array[@]} encontrados):"
            log_message ""
            log_message "   $(printf '%-18s %-20s %-10s' 'IP' 'HOSTNAME' 'SSH')"
            log_message "   $(printf '%-18s %-20s %-10s' '──────────────────' '────────────────────' '──────────')"
            
            for ip in "${ips_array[@]}"; do
                # Intentar obtener hostname via SSH
                local hostname=$(sshpass -p "$BALANCER_PASSWORD" ssh \
                    -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null \
                    -o LogLevel=ERROR \
                    -o ConnectTimeout=2 \
                    -o BatchMode=no \
                    "${BALANCER_USER}@${ip}" "hostname; echo" 2>/dev/null | tr -d '\r\n\t ')
                
                if [[ -n "$hostname" ]]; then
                    local ssh_status="✅ OK"
                else
                    hostname="(sin acceso SSH)"
                    ssh_status="❌"
                fi
                
                log_message "   $(printf '%-18s %-20s %-10s' "$ip" "$hostname" "$ssh_status")"
            done
            log_message ""
        else
            log_message "   ⚠️  No se detectaron servidores activos"
        fi
    else
        # Listar VMs en ejecución
        local running_vms=$(VBoxManage list runningvms 2>/dev/null | \
            grep -v "plantilla" | \
            grep -v "balanceador")
        
        if [ -n "$running_vms" ]; then
            log_message "   🖥️  VMs en ejecución:"
            echo "$running_vms" | while IFS= read -r vm; do
                log_message "      • $vm"
            done
        else
            log_message "   ⚠️  No se detectaron VMs en ejecución"
        fi
    fi
    
    echo "$current_servers"
}

ensure_minimum_servers() {
    log_message "🔍 Verificando mínimo de servidores requeridos..."
    
    # Redirigir stdout para capturar solo el número, no la salida de log_message
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
        
        if [ ! -x "$SCRIPT_AGREGAR" ]; then
            log_message "❌ Script no ejecutable: $SCRIPT_AGREGAR"
            return 1
        fi
        
        log_message "🔧 Ejecutando: quick_add_server.sh $vm_name"
        
        if "$SCRIPT_AGREGAR" "$vm_name" >> "$LOG_FILE" 2>&1; then
            log_message "✅ Servidor $i agregado exitosamente: $vm_name"
            
            # Esperar un momento para que el servidor se estabilice
            if [ $i -lt $servers_needed ]; then
                log_message "⏳ Esperando 10 segundos antes de agregar el siguiente..."
                sleep 10
            fi
        else
            log_message "❌ Error al agregar servidor $i (código: $?)"
            log_message "⚠️  Continuando con el siguiente servidor..."
            continue
        fi
    done
    
    log_message ""
    log_message "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Verificar que se alcanzó el mínimo
    sleep 5
    local final_count=$(get_active_servers)
    log_message "📊 Conteo final: $final_count servidores activos"
    
    if [ $final_count -ge $MIN_SERVIDORES ]; then
        log_message "✅ Mínimo de servidores alcanzado"
        return 0
    else
        log_message "⚠️  No se pudo alcanzar el mínimo de servidores"
        log_message "   Actual: $final_count | Requerido: $MIN_SERVIDORES"
        return 1
    fi
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
    
    # Escanear red y obtener todas las IPs activas
    local nmap_output=$(nmap -sn "$NETWORK_RANGE" 2>/dev/null)
    
    # Extraer IPs del output usando grep con regex
    # Formato: "Nmap scan report for 192.168.56.114" o "Nmap scan report for 192.168.56.114 (192.168.56.114)"
    local servers=$(echo "$nmap_output" | \
        grep "Nmap scan report for" | \
        grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
        grep -v "^$BALANCER_HOST$" | \
        sort -u | \
        tr '\n' ' ')
    
    echo $servers
}

#############################################
# Funciones de Control de Escalado
#############################################

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
    
    log_message "🚀 EJECUTANDO: quick_add_server.sh (servidores: $current_servers → $((current_servers + 1)))"
    
    if [ ! -x "$SCRIPT_AGREGAR" ]; then
        log_message "❌ Script no ejecutable: $SCRIPT_AGREGAR"
        return 1
    fi
    
    # Generar nombre único para la nueva VM
    local vm_name="servidor-$(date +%s)"
    
    # Ejecutar script y capturar resultado
    log_message ""
    log_message "┌────────────────────────────────────────────────────────┐"
    log_message "│  📦 CREACIÓN DE SERVIDOR - OUTPUT EN TIEMPO REAL      │"
    log_message "└────────────────────────────────────────────────────────┘"
    
    if "$SCRIPT_AGREGAR" "$vm_name" 2>&1 | while IFS= read -r line; do
        # Mostrar con color cyan/azul para output de creación
        echo -e "\033[0;36m[CREATE]\033[0m $line" | tee -a "$LOG_FILE"
    done; then
        log_message ""
        log_message "✅ quick_add_server.sh ejecutado exitosamente - VM: $vm_name"
        register_action
        return 0
    else
        log_message ""
        log_message "❌ Error en quick_add_server.sh (código: $?)"
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
    
    # Escanear red usando nmap para obtener servidores activos
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
    
    # Obtener hostname del último servidor (el más reciente)
    local vm_to_remove=""
    local last_ip="${ips_array[-1]}"  # Último elemento del array
    
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
        log_message "❌ No se pudo determinar el hostname del servidor a eliminar"
        return 1
    fi
    
    log_message "🗑️  EJECUTANDO: quick_remove_server.sh (servidores: $current_servers → $((current_servers - 1)))"
    log_message "🎯 VM seleccionada para eliminar: $vm_to_remove ($last_ip)"
    
    if [ ! -x "$SCRIPT_ELIMINAR" ]; then
        log_message "❌ Script no ejecutable: $SCRIPT_ELIMINAR"
        return 1
    fi
    
    # Mostrar output en tiempo real con color rojo
    log_message ""
    log_message "┌─────────────────────────────────────────────┐"
    log_message "│   PROCESO DE ELIMINACIÓN DE SERVIDOR       │"
    log_message "└─────────────────────────────────────────────┘"
    log_message ""
    
    # Ejecutar el script pasando el hostname directamente como argumento
    # Esto evita los prompts interactivos
    if "$SCRIPT_ELIMINAR" "$vm_to_remove" 2>&1 | while IFS= read -r line; do
        # Mostrar en rojo con prefijo [REMOVE]
        echo -e "\033[0;31m[REMOVE]\033[0m $line" | tee -a "$LOG_FILE"
    done; then
        log_message ""
        log_message "✅ quick_remove_server.sh ejecutado exitosamente - VM eliminada: $vm_to_remove"
        register_action
        return 0
    else
        log_message ""
        log_message "❌ Error en quick_remove_server.sh (código: $?)"
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

validate_scripts() {
    if [ ! -f "$SCRIPT_AGREGAR" ]; then
        log_message "❌ ERROR: quick_add_server.sh no encontrado en: $SCRIPT_AGREGAR"
        return 1
    fi
    
    if [ ! -x "$SCRIPT_AGREGAR" ]; then
        log_message "⚠️  Haciendo ejecutable: $SCRIPT_AGREGAR"
        chmod +x "$SCRIPT_AGREGAR"
    fi
    
    if [ ! -f "$SCRIPT_ELIMINAR" ]; then
        log_message "❌ ERROR: quick_remove_server.sh no encontrado en: $SCRIPT_ELIMINAR"
        return 1
    fi
    
    if [ ! -x "$SCRIPT_ELIMINAR" ]; then
        log_message "⚠️  Haciendo ejecutable: $SCRIPT_ELIMINAR"
        chmod +x "$SCRIPT_ELIMINAR"
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
  Auto-scaler que monitorea la CPU del balanceador y escala automáticamente
  agregando o eliminando servidores según la carga.

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
    log_message "🤖 AUTO-SCALER CON MONITOREO DE BALANCEADOR"
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
    
    if ! validate_scripts; then
        exit 1
    fi
    
    if ! validate_balancer_connection; then
        exit 1
    fi
    
    # Test inicial de CPU del balanceador
    log_message "🔍 Test inicial de CPU del balanceador..."
    initial_cpu=$(get_balancer_cpu)
    log_message "   📊 CPU inicial del balanceador: ${initial_cpu}%"
    
    log_message ""
    log_message "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_message "   INICIALIZACIÓN DE SERVIDORES"
    log_message "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_message ""
    
    # Refrescar lista de servidores y asegurar el mínimo
    # Redirigir stdout para capturar solo el número, no la salida de log_message
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
        # Verificar que stress-ng esté instalado
        if ! sshpass -p "$BALANCER_PASSWORD" ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            "${BALANCER_USER}@${BALANCER_HOST}" \
            "which stress-ng" >/dev/null 2>&1; then
            log_message "❌ ERROR: stress-ng no está instalado en el balanceador"
            log_message "💡 Instalar con: sudo apt-get update && sudo apt-get install -y stress-ng"
            exit 1
        fi
    fi
    
    log_message ""
    log_message "🚀 Iniciando monitoreo continuo..."
    log_message ""
    
    # Contador para refrescar lista cada N ciclos
    local refresh_counter=0
    local refresh_interval=5  # Refrescar cada 5 ciclos (100s por defecto)
    
    while true; do
        # Control de prueba automática (si está activado)
        if [ "$MODO_PRUEBA" = true ]; then
            control_stress_automatico
        fi
        
        # Refrescar lista de servidores periódicamente
        ((refresh_counter++))
        if [ $refresh_counter -ge $refresh_interval ]; then
            log_message ""
            log_message "🔄 Refresco periódico de servidores (cada $((refresh_interval * INTERVALO_MONITOREO))s)"
            refresh_server_list > /dev/null
            refresh_counter=0
            log_message ""
        fi
        
        # Obtener métricas
        cpu_balancer=$(get_balancer_cpu)
        servidores_activos=$(count_active_servers)
        stress_status=$(check_stress_en_balanceador)
        
        # Evaluar decisión de escalado
        decision=$(evaluate_scaling "$cpu_balancer" "$servidores_activos")
        
        # Mostrar estado actual
        show_system_status "$cpu_balancer" "$servidores_activos" "$decision" "$stress_status"
        
        # Ejecutar acción si es necesaria
        if [ "$decision" != "MANTENER" ]; then
            case $decision in
                "AGREGAR_URGENTE") 
                    log_message "🚨 AGREGADO URGENTE - CPU balanceador crítica: ${cpu_balancer}%"
                    log_message "⚡ BYPASS de cooldown activado para acción URGENTE"
                    add_server true
                    ;;
                "AGREGAR") 
                    if check_cooldown; then
                        log_message "📈 AGREGANDO - CPU balanceador alta: ${cpu_balancer}%"
                        add_server false
                    fi
                    ;;
                "ELIMINAR_URGENTE") 
                    log_message "📉 ELIMINANDO URGENTE - CPU balanceador muy baja: ${cpu_balancer}%"
                    log_message "⚡ BYPASS de cooldown activado para acción URGENTE"
                    remove_server true
                    ;;
                "ELIMINAR") 
                    if check_cooldown; then
                        log_message "🔽 ELIMINANDO - CPU balanceador baja: ${cpu_balancer}%"
                        remove_server false
                    fi
                    ;;
            esac
        fi
        
        # Esperar antes del siguiente ciclo
        sleep $INTERVALO_MONITOREO
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
