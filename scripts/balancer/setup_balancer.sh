#!/usr/bin/env bash

# ============================================================
# Script 1: Configuración del Balanceador de Carga (HAProxy)
# ============================================================
# Este script prepara la máquina del balanceador:
# - Instala HAProxy y dependencias
# - Crea una configuración base inicial (sin backends)
# - Deja el sistema listo para recibir servidores backend
# ============================================================

set -e  # Salir si hay algún error

# ============================================================
# Función para ejecutar comandos remotos con sudo
# ============================================================
sudo_remote() {
  local host="$1"
  local user="$2"
  local password="$3"
  local command="$4"

  # Debug: Verificar que la contraseña se está pasando
  echo "🔍 DEBUG: Password length: ${#password}" >&2
  echo "🔍 DEBUG: Password first char: ${password:0:1}" >&2
  
  sshpass -p "$password" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -o ConnectTimeout=30 \
    -o ServerAliveInterval=10 \
    -o ServerAliveCountMax=6 \
    -o Compression=yes \
    "${user}@${host}" \
    "echo \"$password\" | sudo -S bash -c \"$command\" 2>&1" | sed 's/\[sudo\] password for [^:]*:/&\n/'
}

# ============================================================
# Mostrar ayuda
# ============================================================
show_help() {
  cat <<EOF
Uso: $0 [opciones]

Descripción:
  Configura un balanceador de carga HAProxy con configuración base inicial.
  Puede escanear automáticamente la red para detectar servidores existentes.

Opciones:
  --balancer-host <ip>      IP del host donde instalar HAProxy
  --user <usuario>          Usuario SSH para el balanceador
  --password <contraseña>   Contraseña sudo del balanceador
  --port <puerto>           Puerto en el que HAProxy escuchará (default: 80)
  --network-range <rango>   Rango de red para escanear servidores (ej: 192.168.56.102-254)
  --vm-user <usuario>       Usuario SSH de las VMs (para escaneo automático)
  --vm-password <pass>      Contraseña SSH de las VMs (para escaneo automático)
  --backend-port <puerto>   Puerto del servicio backend (default: 8000)
  --help                    Muestra esta ayuda

Ejemplo básico (sin servidores):
  ./setup_balancer.sh \\
    --balancer-host 192.168.56.2 \\
    --user debian \\
    --password '1234' \\
    --port 80

Ejemplo con escaneo automático:
  ./setup_balancer.sh \\
    --balancer-host 192.168.56.2 \\
    --user debian \\
    --password '1234' \\
    --port 80 \\
    --network-range 192.168.56.102-254 \\
    --vm-user debian \\
    --vm-password '1234' \\
    --backend-port 8000

Requisitos en Arch Linux (host):
  - sshpass: sudo pacman -S sshpass
  - nmap: sudo pacman -S nmap (para escaneo automático)
  - ssh: Ya viene instalado normalmente

EOF
  exit 0
}

# ============================================================
# Valores por defecto
# ============================================================
BALANCER_PORT=80
BACKEND_PORT=8000

# ============================================================
# Parseo de argumentos
# ============================================================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --balancer-host) BALANCER_HOST="$2"; shift 2;;
    --user) BALANCER_USER="$2"; shift 2;;
    --password) BALANCER_PASS="$2"; shift 2;;
    --port) BALANCER_PORT="$2"; shift 2;;
    --network-range) NETWORK_RANGE="$2"; shift 2;;
    --vm-user) VM_USER="$2"; shift 2;;
    --vm-password) VM_PASS="$2"; shift 2;;
    --backend-port) BACKEND_PORT="$2"; shift 2;;
    --help) show_help;;
    *) echo "❌ Opción desconocida: $1"; show_help;;
  esac
done

# ============================================================
# Validar parámetros obligatorios
# ============================================================
if [[ -z "$BALANCER_HOST" || -z "$BALANCER_USER" || -z "$BALANCER_PASS" ]]; then
  echo "❌ ERROR: Faltan parámetros obligatorios."
  echo ""
  show_help
fi

# ============================================================
# Banner inicial
# ============================================================
echo ""
echo "════════════════════════════════════════════════════════"
echo "   🔧 CONFIGURACIÓN DE BALANCEADOR HAPROXY"
echo "════════════════════════════════════════════════════════"
echo "Host:     $BALANCER_HOST"
echo "Usuario:  $BALANCER_USER"
echo "Puerto:   $BALANCER_PORT"
echo "════════════════════════════════════════════════════════"
echo ""

# ============================================================
# Verificar conectividad
# ============================================================
echo "🔍 [1/5] Verificando conectividad con $BALANCER_HOST ..."
if ! ping -c 1 -W 3 "$BALANCER_HOST" &>/dev/null; then
  echo "❌ ERROR: El host $BALANCER_HOST no responde a ping"
  exit 1
fi
echo "✅ Host responde correctamente"
echo ""

# ============================================================
# Verificar acceso SSH
# ============================================================
echo "🔑 [2/5] Verificando acceso SSH..."
if ! sshpass -p "$BALANCER_PASS" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -o ConnectTimeout=10 \
    "${BALANCER_USER}@${BALANCER_HOST}" "echo 'SSH OK'" &>/dev/null; then
  echo "❌ ERROR: No se pudo conectar vía SSH"
  exit 1
fi
echo "✅ Acceso SSH verificado"
echo ""

# ============================================================
# Verificar conectividad a internet
# ============================================================
echo "🌐 [3/5] Verificando conectividad a internet del balanceador..."
if ! sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
    "ping -c 2 -W 5 8.8.8.8" &>/dev/null; then
  echo "⚠️  ADVERTENCIA: El balanceador no tiene conectividad a internet"
  echo "   Para instalar HAProxy necesitas configurar la red correctamente."
  echo "   Continuando de todas formas..."
else
  echo "✅ Conectividad a internet verificada"
fi
echo ""

# ============================================================
# Instalar HAProxy
# ============================================================
echo "📦 [4/5] Instalando HAProxy..."
echo ""

install_output=$(sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
  "apt-get update -qq && apt-get install -y haproxy sysstat stress-ng" 2>&1)

if [ $? -ne 0 ]; then
  echo "❌ ERROR: Falló la instalación de HAProxy"
  echo ""
  echo "Salida del comando:"
  echo "$install_output"
  exit 1
fi

# Mostrar las últimas 10 líneas del proceso de instalación
echo "📋 Últimas líneas de la instalación:"
echo "─────────────────────────────────────────────────────────"
echo "$install_output" | tail -n 10
echo "─────────────────────────────────────────────────────────"
echo "✅ HAProxy instalado correctamente"
echo ""

# ============================================================
# Crear configuración de HAProxy
# ============================================================
echo "⚙️  [5/5] Creando configuración de HAProxy..."

# Detectar servidores si se proporcionaron parámetros de red
declare -a valid_servers
servers_found=0

if [[ -n "$NETWORK_RANGE" && -n "$VM_USER" && -n "$VM_PASS" ]]; then
  echo "   📡 Escaneando red $NETWORK_RANGE para detectar servidores..."
  
  # Verificar que nmap esté disponible
  if ! command -v nmap &>/dev/null; then
    echo "⚠️  ADVERTENCIA: nmap no está instalado. No se pueden escanear servidores."
    echo "   Instálalo con: sudo pacman -S nmap"
  else
    # Extraer el prefijo de red
    NETWORK_PREFIX=$(echo "$NETWORK_RANGE" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
    
    nmap_output=$(nmap -sn "$NETWORK_RANGE" 2>/dev/null)
    
    # Extraer todas las IPs activas
    all_server_ips=$(echo "$nmap_output" | \
      grep "Nmap scan report for" | \
      grep -oE "$NETWORK_PREFIX\.[0-9]+" | \
      sort -u)
    
    # Convertir a array
    server_ips_array=()
    while IFS= read -r line; do
      [[ -n "$line" ]] && server_ips_array+=("$line")
    done <<< "$all_server_ips"
    
    echo "   📋 Se encontraron ${#server_ips_array[@]} host(s) activos"
    
    # Verificar cada IP
    for ip in "${server_ips_array[@]}"; do
      # Verificar SSH y obtener hostname
      hostname=$(sshpass -p "$VM_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -o ConnectTimeout=3 \
        -o BatchMode=no \
        "${VM_USER}@${ip}" "hostname; echo" 2>/dev/null | tr -d '\r\n\t ')
      
      if [[ -n "$hostname" ]]; then
        echo "   ✅ Detectado: $hostname ($ip)"
        valid_servers+=("$hostname|$ip")
        servers_found=$((servers_found + 1))
      fi
    done
    
    echo "   📊 Total de servidores válidos: $servers_found"
  fi
fi
echo ""

# Construir configuración de HAProxy
echo "   ✍️  Generando configuración..."

new_config=$(cat <<HAPROXY_CONFIG
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

# Frontend - Puerto de entrada
frontend http_front
    bind *:${BALANCER_PORT}
    stats uri /haproxy?stats
    stats realm HAProxy\ Statistics
    stats auth admin:admin
    default_backend http_back

#------------------------------------------------------------------------------
# Backend - Servidores de aplicación
#------------------------------------------------------------------------------
backend http_back
    balance random
    option httpchk GET /
HAPROXY_CONFIG
)

# Agregar servidores detectados
if [ $servers_found -gt 0 ]; then
  for server_entry in "${valid_servers[@]}"; do
    IFS='|' read -r hostname ip <<< "$server_entry"
    new_config+=$'\n'"    server $hostname $ip:$BACKEND_PORT check"
  done
fi

# Escribir configuración
sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
  "cat > /etc/haproxy/haproxy.cfg <<'EOF'
$new_config
EOF"

if [ $? -ne 0 ]; then
  echo "❌ ERROR: No se pudo crear el archivo de configuración"
  exit 1
fi

if [ $servers_found -gt 0 ]; then
  echo "✅ Configuración creada con $servers_found servidor(es)"
  echo ""
  echo "   📋 Servidores configurados:"
  for server_entry in "${valid_servers[@]}"; do
    IFS='|' read -r hostname ip <<< "$server_entry"
    echo "      • $hostname ($ip:$BACKEND_PORT)"
  done
else
  echo "✅ Configuración base creada (sin servidores backend)"
  echo "   Usa add_server.sh para agregar servidores"
fi
echo ""

# ============================================================
# Habilitar y reiniciar HAProxy
# ============================================================
echo "🔄 Habilitando e iniciando HAProxy..."
sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
  "systemctl enable haproxy && systemctl restart haproxy"

if [ $? -ne 0 ]; then
  echo "❌ ERROR: No se pudo iniciar HAProxy"
  exit 1
fi
echo "✅ HAProxy habilitado y en ejecución"
echo ""

# ============================================================
# Verificar estado
# ============================================================
echo "🔍 Verificando estado del servicio..."
status_output=$(sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" \
  "systemctl status haproxy --no-pager -l" 2>&1)

if echo "$status_output" | grep -q "active (running)"; then
  echo "✅ HAProxy está activo y funcionando"
else
  echo "⚠️  HAProxy podría tener problemas:"
  echo "$status_output"
fi
echo ""

# ============================================================
# Resumen final
# ============================================================
echo "════════════════════════════════════════════════════════"
echo "   ✅ BALANCEADOR CONFIGURADO EXITOSAMENTE"
echo "════════════════════════════════════════════════════════"
echo ""
echo "📋 Información del balanceador:"
echo "   • URL: http://${BALANCER_HOST}:${BALANCER_PORT}"
echo "   • Estadísticas: http://${BALANCER_HOST}:${BALANCER_PORT}/haproxy?stats"
echo "   • Usuario stats: admin"
echo "   • Contraseña stats: admin"
if [ $servers_found -gt 0 ]; then
  echo "   • Servidores configurados: $servers_found"
fi
echo ""
echo "📌 Próximos pasos:"
if [ $servers_found -eq 0 ]; then
  echo "   1. Usa add_server.sh para agregar servidores backend"
  echo "   2. Usa remove_server.sh para eliminar servidores"
else
  echo "   1. Verifica el estado de los servidores en las estadísticas"
  echo "   2. Usa add_server.sh para agregar más servidores"
  echo "   3. Usa remove_server.sh para eliminar servidores"
fi
echo ""
echo "🔧 Archivo de configuración: /etc/haproxy/haproxy.cfg"
echo "════════════════════════════════════════════════════════"
echo ""
