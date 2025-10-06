#!/usr/bin/env bash

# ============================================================
# Quick Setup Balancer - Script simplificado para configurar HAProxy
# ============================================================

set -e

# ============================================================
# Variables de configuración (exportadas)
# ============================================================
export BALANCER_HOST="192.168.56.101"
export BALANCER_USER="debian"
export BALANCER_PASSWORD="debian"
export BALANCER_PORT="80"

# Variables opcionales para escaneo automático
export NETWORK_RANGE="192.168.56.102-254"
export VM_USER="debian"
export VM_PASSWORD="debian"
export BACKEND_PORT="8080"

# ============================================================
# Banner
# ============================================================
echo ""
echo "════════════════════════════════════════════════════════"
echo "   🔧 QUICK SETUP BALANCER"
echo "════════════════════════════════════════════════════════"
echo ""

echo "📋 Configuración:"
echo "   • Balanceador:   $BALANCER_HOST:$BALANCER_PORT"
echo "   • Usuario:       $BALANCER_USER"
echo ""

# ============================================================
# Preguntar si desea escanear la red
# ============================================================
read -p "¿Escanear red y agregar servidores automáticamente? (S/n): " scan_network

# ============================================================
# Ejecutar setup_balancer.sh
# ============================================================
echo ""
echo "🚀 Configurando HAProxy en $BALANCER_HOST..."
echo ""

if [[ "$scan_network" =~ ^[Nn]$ ]]; then
  # Configuración básica sin servidores
  ./setup_balancer.sh \
    --balancer-host "$BALANCER_HOST" \
    --user "$BALANCER_USER" \
    --password "$BALANCER_PASSWORD" \
    --port "$BALANCER_PORT"
else
  # Configuración con escaneo automático de servidores
  echo "📡 Con escaneo automático de red: $NETWORK_RANGE"
  echo ""
  
  ./setup_balancer.sh \
    --balancer-host "$BALANCER_HOST" \
    --user "$BALANCER_USER" \
    --password "$BALANCER_PASSWORD" \
    --port "$BALANCER_PORT" \
    --network-range "$NETWORK_RANGE" \
    --vm-user "$VM_USER" \
    --vm-password "$VM_PASSWORD" \
    --backend-port "$BACKEND_PORT"
fi

echo ""
echo "✅ Completado"
echo ""
echo "🌐 Panel de estadísticas:"
echo "   http://$BALANCER_HOST/haproxy?stats"
echo "   Usuario: admin / Contraseña: admin"
echo ""
