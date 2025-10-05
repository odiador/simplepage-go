#!/usr/bin/env bash

# ============================================================
# Función para ejecutar comandos con sudo remoto usando expect
# ============================================================
sudo_remote() {
  local host="$1"
  local user="$2"
  local password="$3"
  local command="$4"

  expect <<EOF
set timeout -1
log_user 0
spawn ssh -o StrictHostKeyChecking=no ${user}@${host} "sudo -S bash -c '${command}'"
expect {
  "password" { send "${password}\r" }
  eof
}
EOF
}

# ============================================================
# Mostrar ayuda
# ============================================================
show_help() {
  echo "Uso: $0 [opciones]"
  echo
  echo "Opciones:"
  echo "  --from-ip <ip>            IP inicial para las VMs clonadas"
  echo "  --to-ip <ip>              IP final para las VMs clonadas"
  echo "  --base-name <nombre>      Prefijo para las VMs clonadas"
  echo "  --disk-path <ruta>        Ruta del disco a montar en SATA 1"
  echo "  --balancer-host <host>    Host donde se instalará HAProxy"
  echo "  --user <usuario>          Usuario SSH para las VMs"
  echo "  --user-balancer <usuario> Usuario SSH para el balanceador"
  echo "  --pass-vm <password>      Contraseña sudo para las VMs"
  echo "  --pass-balancer <pass>    Contraseña sudo para el balanceador"
  echo "  --base-vm <nombre>        Nombre de la VM base a clonar"
  echo
  echo "Ejemplo:"
  echo "  ./deploy_cluster.sh --from-ip 192.168.56.10 --to-ip 192.168.56.12 \\"
  echo "    --base-name web --base-vm template --disk-path /home/discos/srvimg.vdi \\"
  echo "    --balancer-host 192.168.56.5 --user juan --user-balancer juan \\"
  echo "    --pass-vm '1234' --pass-balancer '1234'"
  exit 1
}

# ============================================================
# Parseo de argumentos
# ============================================================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-ip) from_ip="$2"; shift 2;;
    --to-ip) to_ip="$2"; shift 2;;
    --base-name) base_name="$2"; shift 2;;
    --disk-path) disk_path="$2"; shift 2;;
    --balancer-host) balancer_host="$2"; shift 2;;
    --user) user_vm="$2"; shift 2;;
    --user-balancer) user_balancer="$2"; shift 2;;
    --pass-vm) pass_vm="$2"; shift 2;;
    --pass-balancer) pass_balancer="$2"; shift 2;;
    --base-vm) base_vm="$2"; shift 2;;
    *) echo "Opción desconocida: $1"; show_help ;;
  esac
done

if [[ -z "$from_ip" || -z "$to_ip" || -z "$base_name" || -z "$disk_path" || -z "$balancer_host" ||
      -z "$user_vm" || -z "$user_balancer" || -z "$pass_vm" || -z "$pass_balancer" || -z "$base_vm" ]]; then
  echo "❌ Faltan parámetros."
  show_help
fi

# ============================================================
# Funciones auxiliares IP
# ============================================================
ip_to_int() { local IFS=. ; read -r i1 i2 i3 i4 <<< "$1"; echo $(( (i1<<24) + (i2<<16) + (i3<<8) + i4 )); }
int_to_ip() { local ip=$1; echo "$(( (ip>>24)&255 )).$(( (ip>>16)&255 )).$(( (ip>>8)&255 )).$(( ip&255 ))"; }

from_int=$(ip_to_int "$from_ip")
to_int=$(ip_to_int "$to_ip")

# ============================================================
# Crear y configurar las VMs
# ============================================================
for ((ip_int=from_int; ip_int<=to_int; ip_int++)); do
  ip=$(int_to_ip "$ip_int")
  vm_name="${base_name}-${ip##*.}"

  echo "🌀 Verificando existencia de VM $vm_name ..."
  if VBoxManage showvminfo "$vm_name" &>/dev/null; then
    echo "⚠️  VM $vm_name ya existe, omitiendo clonación."
  else
    echo "🌀 Clonando VM $vm_name ..."
    VBoxManage clonevm "$base_vm" --name "$vm_name" --register --mode all
  fi

  echo "🔧 Configurando disco SATA 1 ..."
  VBoxManage storageattach "$vm_name" --storagectl "SATA Controller" --port 1 --device 0 --type hdd --medium "$disk_path"

  echo "🌐 Configurando IP $ip ..."
  sudo_remote "$ip" "$user_vm" "$pass_vm" "sed -i 's/address .*/address $ip/' /etc/network/interfaces && systemctl restart networking"

  echo "💻 Actualizando hostname y /etc/hosts ..."
  sudo_remote "$ip" "$user_vm" "$pass_vm" "
    hostnamectl set-hostname $vm_name
    if grep -q '^127\\.0\\.1\\.1' /etc/hosts; then
      sed -i 's/^127\\.0\\.1\\.1.*/127.0.1.1\t'"$vm_name"'/' /etc/hosts
    else
      echo -e '127.0.1.1\t'"$vm_name" >> /etc/hosts
    fi
  "

  echo "🔁 Reiniciando VM $vm_name ..."
  VBoxManage controlvm "$vm_name" reset

  echo "✅ VM $vm_name lista en IP $ip"
done

# ============================================================
# Configurar balanceador HAProxy
# ============================================================
echo "⚙️ Configurando HAProxy en $balancer_host ..."
sudo_remote "$balancer_host" "$user_balancer" "$pass_balancer" "
  apt-get update -y && apt-get install -y haproxy
"

cfg="/etc/haproxy/haproxy.cfg"
sudo_remote "$balancer_host" "$user_balancer" "$pass_balancer" "
cat > $cfg <<'EOCFG'
global
    daemon
    maxconn 256
defaults
    mode http
    timeout connect 5s
    timeout client 60s
    timeout server 60s

frontend http_front
    bind *:80
    default_backend http_back

backend http_back
    balance roundrobin
EOCFG
"

for ((ip_int=from_int; ip_int<=to_int; ip_int++)); do
  ip=$(int_to_ip "$ip_int")
  vm_name="${base_name}-${ip##*.}"
  sudo_remote "$balancer_host" "$user_balancer" "$pass_balancer" \
    "echo '    server ${vm_name} ${ip}:8000 check' | tee -a /etc/haproxy/haproxy.cfg"
done

sudo_remote "$balancer_host" "$user_balancer" "$pass_balancer" "systemctl restart haproxy"
echo "✅ HAProxy listo en $balancer_host"
