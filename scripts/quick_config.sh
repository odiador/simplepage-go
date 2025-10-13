#!/usr/bin/env bash

# ============================================================
# Quick Config - Variables de configuración para scripts quick
# ============================================================
# Este archivo contiene todas las variables de configuración
# utilizadas por los scripts "quick" del proyecto.
#
# Para usar en un script: source ./quick_config.sh
# ============================================================

# ============================================================
# Configuración del Balanceador HAProxy
# ============================================================
export BALANCER_HOST="192.168.56.101"
export BALANCER_USER="debian"
export BALANCER_PASSWORD="debian"
export BALANCER_PORT="80"

# ============================================================
# Configuración de Servidores Virtuales
# ============================================================
export VM_USER="debian"
export VM_PASSWORD="debian"
export NETWORK_RANGE="192.168.56.102-254"
export BACKEND_PORT="8080"

# ============================================================
# Configuración específica de VirtualBox
# ============================================================
export BASE_VM="plantilla"
export DISK_PATH="/home/amador/VirtualBox VMs/plantilla-servicio/servicioimg.vdi"

# ============================================================
# Configuración del Auto-Scaler
# ============================================================
export UMBRAL_ALTO=75
export UMBRAL_CRITICO=85
export UMBRAL_BAJO=40
export UMBRAL_MUY_BAJO=25
export INTERVALO_MONITOREO=20
export MIN_SERVIDORES=2
export MAX_SERVIDORES=5
export TIEMPO_COOLDOWN=60

# ============================================================
# Rutas de Scripts
# ============================================================
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_AGREGAR="$SCRIPT_DIR/quick_add_server.sh"
export SCRIPT_ELIMINAR="$SCRIPT_DIR/quick_remove_server.sh"
export LOG_FILE="$SCRIPT_DIR/autoscaler.log"
export ESTADO_FILE="/tmp/autoscaler_state"
export COOLDOWN_FILE="/tmp/autoscaler_cooldown"

# ============================================================
# Función de validación de configuración
# ============================================================
validate_quick_config() {
    local errors=()

    # Verificar que las variables críticas estén definidas
    if [[ -z "$BALANCER_HOST" ]]; then
        errors+=("BALANCER_HOST no definido")
    fi

    if [[ -z "$BALANCER_USER" ]]; then
        errors+=("BALANCER_USER no definido")
    fi

    if [[ -z "$VM_USER" ]]; then
        errors+=("VM_USER no definido")
    fi

    if [[ -z "$NETWORK_RANGE" ]]; then
        errors+=("NETWORK_RANGE no definido")
    fi

    # Verificar rangos de umbrales
    if [[ $UMBRAL_ALTO -ge $UMBRAL_CRITICO ]]; then
        errors+=("UMBRAL_ALTO ($UMBRAL_ALTO) debe ser menor que UMBRAL_CRITICO ($UMBRAL_CRITICO)")
    fi

    if [[ $UMBRAL_BAJO -le $UMBRAL_MUY_BAJO ]]; then
        errors+=("UMBRAL_BAJO ($UMBRAL_BAJO) debe ser mayor que UMBRAL_MUY_BAJO ($UMBRAL_MUY_BAJO)")
    fi

    if [[ $MIN_SERVIDORES -ge $MAX_SERVIDORES ]]; then
        errors+=("MIN_SERVIDORES ($MIN_SERVIDORES) debe ser menor que MAX_SERVIDORES ($MAX_SERVIDORES)")
    fi

    # Mostrar errores si los hay
    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "❌ ERRORES DE CONFIGURACIÓN:"
        for error in "${errors[@]}"; do
            echo "   • $error"
        done
        echo ""
        return 1
    fi

    return 0
}

# ============================================================
# Función para mostrar configuración actual
# ============================================================
show_quick_config() {
    echo ""
    echo "📋 CONFIGURACIÓN QUICK ACTUAL:"
    echo "════════════════════════════════════════════════════════"
    echo "🔧 BALANCEADOR:"
    echo "   • Host:     $BALANCER_HOST:$BALANCER_PORT"
    echo "   • Usuario:  $BALANCER_USER"
    echo "   • Backend:  $BACKEND_PORT"
    echo ""
    echo "🖥️  SERVIDORES:"
    echo "   • Usuario:  $VM_USER"
    echo "   • Red:      $NETWORK_RANGE"
    echo ""
    echo "⚡ AUTO-SCALER:"
    echo "   • Umbrales: Alto=${UMBRAL_ALTO}% Crítico=${UMBRAL_CRITICO}%"
    echo "   •         Bajo=${UMBRAL_BAJO}% MuyBajo=${UMBRAL_MUY_BAJO}%"
    echo "   • Servidores: Mín=${MIN_SERVIDORES} Máx=${MAX_SERVIDORES}"
    echo "   • Intervalo: ${INTERVALO_MONITOREO}s | Cooldown: ${TIEMPO_COOLDOWN}s"
    echo "════════════════════════════════════════════════════════"
    echo ""
}

# ============================================================
# Auto-validación al cargar
# ============================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Si se ejecuta directamente, mostrar configuración
    echo "🔧 Quick Config - Archivo de configuración centralizada"
    show_quick_config

    if validate_quick_config; then
        echo "✅ Configuración válida"
    else
        echo "❌ Configuración con errores"
        exit 1
    fi
fi