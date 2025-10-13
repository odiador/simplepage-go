#!/usr/bin/env bash

# ============================================================
# Quick Auto-Scaler - Inicio rápido del auto-scaler
# ============================================================
# Este script inicia el auto-scaler de forma rápida
# con opciones para modo normal o con stress
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
# Función de ayuda
# ============================================================
show_help() {
  cat <<EOF
Uso: $0 [opciones]

Descripción:
  Inicia el auto-scaler de forma rápida con configuración por defecto.

Opciones:
  --normal          Modo normal (sin stress artificial) [default]
  --stress          Modo prueba con stress artificial
  --help            Muestra esta ayuda

Ejemplos:
  $0                # Inicia en modo normal
  $0 --normal       # Inicia en modo normal
  $0 --stress       # Inicia en modo prueba con stress

EOF
  exit 0
}

# ============================================================
# Parseo de argumentos
# ============================================================
MODO="normal"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --normal)
      MODO="normal"
      shift
      ;;
    --stress)
      MODO="stress"
      shift
      ;;
    --help)
      show_help
      ;;
    *)
      echo "❌ Opción desconocida: $1"
      show_help
      ;;
  esac
done

# ============================================================
# Banner
# ============================================================
echo ""
echo "════════════════════════════════════════════════════════"
echo "   ⚡ QUICK AUTO-SCALER"
echo "════════════════════════════════════════════════════════"
if [ "$MODO" = "stress" ]; then
  echo "Modo:        PRUEBA CON STRESS"
  echo "Descripción: Genera carga artificial para probar escalado"
else
  echo "Modo:        NORMAL"
  echo "Descripción: Monitoreo continuo sin stress artificial"
fi
echo "════════════════════════════════════════════════════════"
echo ""

# ============================================================
# Verificar que existe el autoscaler
# ============================================================
if [ ! -f "./autoscaler.sh" ]; then
  echo "❌ ERROR: autoscaler.sh no encontrado"
  exit 1
fi

if [ ! -x "./autoscaler.sh" ]; then
  echo "⚠️  Haciendo ejecutable autoscaler.sh..."
  chmod +x ./autoscaler.sh
fi

# ============================================================
# Ejecutar autoscaler según el modo
# ============================================================
echo "🚀 Iniciando auto-scaler en modo $MODO..."
echo ""

if [ "$MODO" = "stress" ]; then
  # Modo prueba con stress automático
  exec ./autoscaler.sh --modo-prueba
else
  # Modo normal
  exec ./autoscaler.sh
fi