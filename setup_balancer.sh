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

  sshpass -p "$password" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=30 \
    -o ServerAliveInterval=10 \
    -o ServerAliveCountMax=6 \
    -o Compression=yes \
    "${user}@${host}" \
    "echo '$password' | sudo -S bash -c \"$command\""
}

# ============================================================
# Mostrar ayuda
# ============================================================
show_help() {
  cat <<EOF
Uso: $0 [opciones]

Descripción:
  Configura un balanceador de carga HAProxy con configuración base inicial.
  No define backends todavía - eso se hará con add_server.sh.

Opciones:
  --balancer-host <ip>      IP del host donde instalar HAProxy
  --user <usuario>          Usuario SSH para el balanceador
  --password <contraseña>   Contraseña sudo del balanceador
  --port <puerto>           Puerto en el que HAProxy escuchará (default: 80)
  --help                    Muestra esta ayuda

Ejemplo:
  ./setup_balancer.sh \\
    --balancer-host 192.168.56.2 \\
    --user debian \\
    --password '1234' \\
    --port 80

Requisitos en Arch Linux (host):
  - sshpass: sudo pacman -S sshpass
  - ssh: Ya viene instalado normalmente

EOF
  exit 0
}

# ============================================================
# Valores por defecto
# ============================================================
BALANCER_PORT=80

# ============================================================
# Parseo de argumentos
# ============================================================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --balancer-host) BALANCER_HOST="$2"; shift 2;;
    --user) BALANCER_USER="$2"; shift 2;;
    --password) BALANCER_PASS="$2"; shift 2;;
    --port) BALANCER_PORT="$2"; shift 2;;
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
  echo ""
  read -p "¿Deseas continuar de todas formas? (y/N): " continue_anyway
  if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
    echo "❌ Instalación cancelada por el usuario"
    exit 1
  fi
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
  "apt-get update -qq && apt-get install -y haproxy" 2>&1)

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
# Crear configuración base de HAProxy
# ============================================================
echo "⚙️  [5/5] Creando configuración base de HAProxy..."

sudo_remote "$BALANCER_HOST" "$BALANCER_USER" "$BALANCER_PASS" "
cat > /etc/haproxy/haproxy.cfg <<'EOCFG'
#---------------------------------------------------------------------
# Configuración Global de HAProxy
#---------------------------------------------------------------------
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    maxconn 2048

    # Configuración SSL por defecto si se necesita
    # ssl-default-bind-ciphers ...
    # ssl-default-bind-options ...

#---------------------------------------------------------------------
# Configuración por defecto
#---------------------------------------------------------------------
defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

#---------------------------------------------------------------------
# Frontend - Punto de entrada HTTP
#---------------------------------------------------------------------
frontend http_front
    bind *:${BALANCER_PORT}
    default_backend http_back
    
    # Estadísticas disponibles en /haproxy?stats
    stats uri /haproxy?stats
    stats realm HAProxy\\ Statistics
    stats auth admin:admin

#---------------------------------------------------------------------
# Backend - Servidores de aplicación
#---------------------------------------------------------------------
backend http_back
    balance random
    option httpchk GET /
    # Los servidores se agregarán con add_server.sh
    # Ejemplo: server web-10 192.168.56.10:8000 check
EOCFG
"

if [ $? -ne 0 ]; then
  echo "❌ ERROR: No se pudo crear el archivo de configuración"
  exit 1
fi
echo "✅ Configuración base creada en /etc/haproxy/haproxy.cfg"
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
echo ""
echo "📌 Próximos pasos:"
echo "   1. Usa add_server.sh para agregar servidores backend"
echo "   2. Usa remove_server.sh para eliminar servidores"
echo ""
echo "🔧 Archivo de configuración: /etc/haproxy/haproxy.cfg"
echo "════════════════════════════════════════════════════════"
echo ""
