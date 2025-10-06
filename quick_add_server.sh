#!/usr/bin/env bash

# ============================================================
# Quick Add Server - Script simplificado para agregar servidores
# ============================================================

set -e

# ============================================================
# Variables de configuración (exportadas)
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

# ============================================================
# Banner
# ============================================================
echo ""
echo "════════════════════════════════════════════════════════"
echo "   ➕ QUICK ADD SERVER"
echo "════════════════════════════════════════════════════════"
echo ""

# ============================================================
# Solicitar nombre de la VM
# ============================================================
if [[ -z "$1" ]]; then
  read -p "Nombre de la nueva VM: " VM_NAME
  if [[ -z "$VM_NAME" ]]; then
    echo "❌ ERROR: El nombre de la VM es obligatorio"
    exit 1
  fi
else
  VM_NAME="$1"
fi

echo ""
echo "📋 Configuración:"
echo "   • VM Base:       $BASE_VM"
echo "   • Nueva VM:      $VM_NAME"
echo "   • Disk Path:     $DISK_PATH"
echo "   • Red:           $NETWORK_RANGE"
echo "   • Backend Port:  $BACKEND_PORT"
echo "   • Balanceador:   $BALANCER_HOST"
echo ""

# ============================================================
# Ejecutar add_server.sh
# ============================================================
echo "🚀 Agregando servidor '$VM_NAME'..."
echo ""

./add_server.sh \
  --base-vm "$BASE_VM" \
  --vm-name "$VM_NAME" \
  --disk-path "$DISK_PATH" \
  --vm-user "$VM_USER" \
  --vm-password "$VM_PASSWORD" \
  --network-range "$NETWORK_RANGE" \
  --backend-port "$BACKEND_PORT" \
  --balancer-host "$BALANCER_HOST" \
  --balancer-user "$BALANCER_USER" \
  --balancer-pass "$BALANCER_PASSWORD"

echo ""
echo "✅ Completado"
echo ""
