#!/usr/bin/env bash

#############################################
# Validador de Configuración del Auto-Scaler
# Verifica que todo esté listo para ejecutar
#############################################

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuración
BALANCER_HOST="192.168.56.101"
BALANCER_USER="debian"
BALANCER_PASSWORD="debian"
NETWORK_RANGE="192.168.56.102-254"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Contadores
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

#############################################
# Funciones de Output
#############################################

print_header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}   🔍 VALIDADOR DE CONFIGURACIÓN - AUTO-SCALER${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_check() {
    echo -e "  ⏳ $1..."
}

print_success() {
    echo -e "  ${GREEN}✅ $1${NC}"
    ((CHECKS_PASSED++))
}

print_error() {
    echo -e "  ${RED}❌ $1${NC}"
    ((CHECKS_FAILED++))
}

print_warning() {
    echo -e "  ${YELLOW}⚠️  $1${NC}"
    ((CHECKS_WARNING++))
}

print_info() {
    echo -e "  ${BLUE}ℹ️  $1${NC}"
}

print_summary() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}   📊 RESUMEN DE VALIDACIÓN${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}Pasadas:${NC}     $CHECKS_PASSED"
    echo -e "  ${YELLOW}Advertencias:${NC} $CHECKS_WARNING"
    echo -e "  ${RED}Fallidas:${NC}    $CHECKS_FAILED"
    echo ""
    
    if [ $CHECKS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✅ SISTEMA LISTO PARA AUTO-SCALER${NC}"
        echo ""
        echo -e "Ejecutar con:"
        echo -e "  ${BLUE}./autoscaler.sh${NC}                  # Modo normal"
        echo -e "  ${BLUE}./autoscaler.sh --modo-prueba${NC}    # Modo prueba con stress"
        echo ""
        return 0
    else
        echo -e "${RED}❌ CORRIGE LOS ERRORES ANTES DE CONTINUAR${NC}"
        echo ""
        return 1
    fi
}

#############################################
# Validaciones
#############################################

check_dependencies() {
    echo ""
    echo -e "${BLUE}[1/8] Verificando Dependencias del Sistema${NC}"
    echo ""
    
    # sshpass
    print_check "Verificando sshpass"
    if command -v sshpass &>/dev/null; then
        print_success "sshpass instalado: $(which sshpass)"
    else
        print_error "sshpass no encontrado"
        print_info "Instalar con: sudo pacman -S sshpass"
    fi
    
    # nmap
    print_check "Verificando nmap"
    if command -v nmap &>/dev/null; then
        print_success "nmap instalado: $(which nmap)"
    else
        print_warning "nmap no encontrado (opcional pero recomendado)"
        print_info "Instalar con: sudo pacman -S nmap"
    fi
    
    # SSH
    print_check "Verificando ssh"
    if command -v ssh &>/dev/null; then
        print_success "ssh instalado: $(which ssh)"
    else
        print_error "ssh no encontrado"
    fi
    
    # VBoxManage
    print_check "Verificando VBoxManage"
    if command -v VBoxManage &>/dev/null; then
        print_success "VBoxManage instalado: $(which VBoxManage)"
    else
        print_error "VBoxManage no encontrado"
        print_info "Instalar VirtualBox"
    fi
}

check_scripts() {
    echo ""
    echo -e "${BLUE}[2/8] Verificando Scripts Requeridos${NC}"
    echo ""
    
    # autoscaler.sh
    print_check "Verificando autoscaler.sh"
    if [ -f "$SCRIPT_DIR/autoscaler.sh" ]; then
        if [ -x "$SCRIPT_DIR/autoscaler.sh" ]; then
            print_success "autoscaler.sh existe y es ejecutable"
        else
            print_warning "autoscaler.sh existe pero no es ejecutable"
            print_info "Ejecutar: chmod +x autoscaler.sh"
            chmod +x "$SCRIPT_DIR/autoscaler.sh" 2>/dev/null && print_success "Permisos corregidos"
        fi
    else
        print_error "autoscaler.sh no encontrado"
    fi
    
    # quick_add_server.sh
    print_check "Verificando quick_add_server.sh"
    if [ -f "$SCRIPT_DIR/quick_add_server.sh" ]; then
        if [ -x "$SCRIPT_DIR/quick_add_server.sh" ]; then
            print_success "quick_add_server.sh existe y es ejecutable"
        else
            print_warning "quick_add_server.sh existe pero no es ejecutable"
            chmod +x "$SCRIPT_DIR/quick_add_server.sh" 2>/dev/null && print_success "Permisos corregidos"
        fi
    else
        print_error "quick_add_server.sh no encontrado"
    fi
    
    # quick_remove_server.sh
    print_check "Verificando quick_remove_server.sh"
    if [ -f "$SCRIPT_DIR/quick_remove_server.sh" ]; then
        if [ -x "$SCRIPT_DIR/quick_remove_server.sh" ]; then
            print_success "quick_remove_server.sh existe y es ejecutable"
        else
            print_warning "quick_remove_server.sh existe pero no es ejecutable"
            chmod +x "$SCRIPT_DIR/quick_remove_server.sh" 2>/dev/null && print_success "Permisos corregidos"
        fi
    else
        print_error "quick_remove_server.sh no encontrado"
    fi
    
    # add_server.sh
    print_check "Verificando add_server.sh"
    if [ -f "$SCRIPT_DIR/add_server.sh" ]; then
        if [ -x "$SCRIPT_DIR/add_server.sh" ]; then
            print_success "add_server.sh existe y es ejecutable"
        else
            print_warning "add_server.sh existe pero no es ejecutable"
            chmod +x "$SCRIPT_DIR/add_server.sh" 2>/dev/null && print_success "Permisos corregidos"
        fi
    else
        print_error "add_server.sh no encontrado"
    fi
    
    # remove_server.sh
    print_check "Verificando remove_server.sh"
    if [ -f "$SCRIPT_DIR/remove_server.sh" ]; then
        if [ -x "$SCRIPT_DIR/remove_server.sh" ]; then
            print_success "remove_server.sh existe y es ejecutable"
        else
            print_warning "remove_server.sh existe pero no es ejecutable"
            chmod +x "$SCRIPT_DIR/remove_server.sh" 2>/dev/null && print_success "Permisos corregidos"
        fi
    else
        print_error "remove_server.sh no encontrado"
    fi
}

check_balancer_connectivity() {
    echo ""
    echo -e "${BLUE}[3/8] Verificando Conectividad con Balanceador${NC}"
    echo ""
    
    print_check "Verificando conexión SSH a $BALANCER_HOST"
    if timeout 5 sshpass -p "$BALANCER_PASSWORD" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -o ConnectTimeout=5 \
        "${BALANCER_USER}@${BALANCER_HOST}" \
        "hostname" &>/dev/null; then
        local hostname=$(sshpass -p "$BALANCER_PASSWORD" ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            "${BALANCER_USER}@${BALANCER_HOST}" \
            "hostname" 2>/dev/null)
        print_success "Conectado a balanceador: $hostname"
    else
        print_error "No se puede conectar al balanceador $BALANCER_HOST"
        print_info "Verificar que la VM esté encendida y accesible"
    fi
}

check_balancer_haproxy() {
    echo ""
    echo -e "${BLUE}[4/8] Verificando HAProxy en Balanceador${NC}"
    echo ""
    
    print_check "Verificando servicio HAProxy"
    local haproxy_status=$(sshpass -p "$BALANCER_PASSWORD" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "${BALANCER_USER}@${BALANCER_HOST}" \
        "systemctl is-active haproxy 2>/dev/null || echo 'inactive'" 2>/dev/null)
    
    if [ "$haproxy_status" = "active" ]; then
        print_success "HAProxy está activo"
    else
        print_error "HAProxy no está activo (estado: $haproxy_status)"
        print_info "Iniciar con: sudo systemctl start haproxy"
    fi
    
    print_check "Verificando configuración HAProxy"
    if sshpass -p "$BALANCER_PASSWORD" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "${BALANCER_USER}@${BALANCER_HOST}" \
        "test -f /etc/haproxy/haproxy.cfg" 2>/dev/null; then
        print_success "Archivo de configuración existe: /etc/haproxy/haproxy.cfg"
    else
        print_error "Configuración de HAProxy no encontrada"
    fi
}

check_balancer_cpu_monitoring() {
    echo ""
    echo -e "${BLUE}[5/8] Verificando Monitoreo de CPU${NC}"
    echo ""
    
    print_check "Probando comando top"
    local cpu_top=$(sshpass -p "$BALANCER_PASSWORD" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "${BALANCER_USER}@${BALANCER_HOST}" \
        "top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'%' -f1" 2>/dev/null)
    
    if [[ "$cpu_top" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        print_success "Comando top funciona (CPU: ${cpu_top}%)"
    else
        print_warning "Comando top no retorna datos válidos"
    fi
    
    print_check "Probando comando mpstat"
    if sshpass -p "$BALANCER_PASSWORD" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "${BALANCER_USER}@${BALANCER_HOST}" \
        "which mpstat" &>/dev/null; then
        print_success "mpstat disponible (alternativa)"
    else
        print_warning "mpstat no disponible (no crítico)"
    fi
}

check_stress_ng() {
    echo ""
    echo -e "${BLUE}[6/8] Verificando stress-ng (para modo prueba)${NC}"
    echo ""
    
    print_check "Verificando stress-ng en balanceador"
    if sshpass -p "$BALANCER_PASSWORD" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "${BALANCER_USER}@${BALANCER_HOST}" \
        "which stress-ng" &>/dev/null; then
        print_success "stress-ng instalado (modo prueba disponible)"
    else
        print_warning "stress-ng no instalado (solo necesario para modo prueba)"
        print_info "Instalar con: sudo apt-get install -y stress-ng"
    fi
}

check_network_and_servers() {
    echo ""
    echo -e "${BLUE}[7/8] Verificando Red y Servidores Backend${NC}"
    echo ""
    
    if ! command -v nmap &>/dev/null; then
        print_warning "nmap no disponible, saltando escaneo de red"
        return
    fi
    
    print_check "Escaneando red $NETWORK_RANGE"
    
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
    
    if [[ -z "$all_ips" ]]; then
        print_warning "No se encontraron servidores backend activos"
        print_info "El auto-scaler los creará automáticamente si es necesario"
        return
    fi
    
    # Convertir a array
    local ips_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && ips_array+=("$line")
    done <<< "$all_ips"
    
    print_success "Servidores activos encontrados: ${#ips_array[@]}"
    echo ""
    echo -e "  ${BLUE}$(printf '%-18s %-20s %-10s' 'IP' 'HOSTNAME' 'SSH')${NC}"
    echo -e "  ${BLUE}$(printf '%-18s %-20s %-10s' '──────────────────' '────────────────────' '──────────')${NC}"
    
    for ip in "${ips_array[@]}"; do
        # Intentar obtener hostname via SSH
        local hostname=$(sshpass -p "$BALANCER_PASSWORD" ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            -o ConnectTimeout=2 \
            -o BatchMode=no \
            "debian@${ip}" "hostname; echo" 2>/dev/null | tr -d '\r\n\t ')
        
        if [[ -n "$hostname" ]]; then
            local ssh_status="${GREEN}✅ OK${NC}"
        else
            hostname="(sin acceso SSH)"
            ssh_status="${RED}❌${NC}"
        fi
        
        echo -e "  $(printf '%-18s %-20s' "$ip" "$hostname") $ssh_status"
    done
    echo ""
}

check_virtualbox() {
    echo ""
    echo -e "${BLUE}[8/8] Verificando VirtualBox${NC}"
    echo ""
    
    print_check "Verificando VBoxManage"
    if ! command -v VBoxManage &>/dev/null; then
        print_error "VBoxManage no encontrado"
        return
    fi
    
    print_check "Listando VMs"
    local vm_count=$(VBoxManage list vms 2>/dev/null | wc -l)
    if [ "$vm_count" -gt 0 ]; then
        print_success "VMs disponibles: $vm_count"
    else
        print_warning "No se encontraron VMs"
    fi
    
    print_check "Verificando VM plantilla"
    if VBoxManage showvminfo "plantilla" &>/dev/null; then
        print_success "VM plantilla existe"
    else
        print_warning "VM 'plantilla' no encontrada"
        print_info "Esta VM se usa como base para clonar nuevos servidores"
    fi
    
    print_check "Verificando VMs en ejecución"
    local running_vms=$(VBoxManage list runningvms 2>/dev/null | wc -l)
    if [ "$running_vms" -gt 0 ]; then
        print_success "VMs en ejecución: $running_vms"
    else
        print_warning "No hay VMs en ejecución"
    fi
}

#############################################
# Main
#############################################

main() {
    print_header
    
    check_dependencies
    check_scripts
    check_balancer_connectivity
    check_balancer_haproxy
    check_balancer_cpu_monitoring
    check_stress_ng
    check_network_and_servers
    check_virtualbox
    
    print_summary
}

main
