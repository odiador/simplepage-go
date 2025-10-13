#!/usr/bin/env bash

# ============================================================
# Quick Setup Balancer - Script simplificado para configurar HAProxy
# ============================================================
# Configuración automática sin validaciones interactivas
# ============================================================

set -e

# ============================================================
# Importar configuración centralizada
# ============================================================
if [ -f "../quick_config.sh" ]; then
    source ../quick_config.sh
else
    echo "❌ ERROR: ../quick_config.sh no encontrado"
    exit 1
fi

# ============================================================
# Banner
# ============================================================
echo ""
echo "════════════════════════════════════════════════════════"
echo "   🔧 QUICK SETUP BALANCER (AUTOMÁTICO)"
echo "════════════════════════════════════════════════════════"
echo ""

echo "📋 Configuración:"
echo "   • Balanceador:   $BALANCER_HOST:$BALANCER_PORT"
echo "   • Usuario:       $BALANCER_USER"
echo "   • Red:           $NETWORK_RANGE"
echo ""

# ============================================================
# Ejecutar setup_balancer.sh con escaneo automático
# ============================================================
echo "🚀 Configurando HAProxy en $BALANCER_HOST..."
echo "📡 Con escaneo automático de red: $NETWORK_RANGE"
echo ""

# Obtener el directorio donde está este script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/setup_balancer.sh" \
  --balancer-host "$BALANCER_HOST" \
  --user "$BALANCER_USER" \
  --password "$BALANCER_PASSWORD" \
  --port "$BALANCER_PORT" \
  --network-range "$NETWORK_RANGE" \
  --vm-user "$VM_USER" \
  --vm-password "$VM_PASSWORD" \
  --backend-port "$BACKEND_PORT"

echo ""
echo "✅ Completado"
echo ""
echo "🌐 Panel de estadísticas:"
echo "   http://$BALANCER_HOST/haproxy?stats"
echo "   Usuario: admin / Contraseña: admin"
echo ""
