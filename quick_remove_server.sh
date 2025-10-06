#!/usr/bin/env bash

# ============================================================
# Quick Remove Server - Script simplificado para eliminar servidores
# ============================================================

set -e

# ============================================================
# Variables de configuración (exportadas)
# ============================================================
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
echo "   🗑️  QUICK REMOVE SERVER"
echo "════════════════════════════════════════════════════════"
echo ""

# ============================================================
# Listar servidores actuales
# ============================================================
echo "🔍 Escaneando red $NETWORK_RANGE..."
echo ""

# Verificar que nmap esté disponible
if ! command -v nmap &>/dev/null; then
  echo "❌ ERROR: nmap no está instalado"
  echo "   Instálalo con: sudo pacman -S nmap"
  exit 1
fi

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
  exit 0
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

# ============================================================
# Solicitar nombre de la VM a eliminar
# ============================================================
if [[ -z "$1" ]]; then
  read -p "Nombre de la VM a eliminar: " VM_NAME
  if [[ -z "$VM_NAME" ]]; then
    echo "❌ ERROR: El nombre de la VM es obligatorio"
    exit 1
  fi
else
  VM_NAME="$1"
fi

echo ""
echo "⚠️  ADVERTENCIA: Esta operación eliminará la VM completamente"
echo "   y la removerá de la configuración de HAProxy."
echo ""
read -p "¿Estás seguro de eliminar '$VM_NAME'? (s/N): " confirm

if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
  echo "Operación cancelada"
  exit 0
fi

# ============================================================
# Ejecutar remove_server.sh
# ============================================================
echo ""
echo "🚀 Eliminando servidor '$VM_NAME'..."
echo ""

./remove_server.sh \
  --vm-name "$VM_NAME" \
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
