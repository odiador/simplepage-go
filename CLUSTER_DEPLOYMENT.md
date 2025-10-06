# 🚀 Gestión de Cluster con HAProxy

Este proyecto incluye 3 scripts modulares para gestionar un cluster de máquinas virtuales con balanceo de carga HAProxy:

1. **`setup_balancer.sh`** - Configuración inicial del balanceador
2. **`add_server.sh`** - Agregar nuevas máquinas al cluster
3. **`remove_server.sh`** - Eliminar máquinas del cluster

---

## 📋 Requisitos Previos

### En Arch Linux (Host)

#### Obligatorios:
```bash
# VirtualBox (ya debería estar instalado)
sudo pacman -S virtualbox virtualbox-host-modules-arch

# sshpass para automatización SSH
sudo pacman -S sshpass
```

#### Opcionales (recomendados para detección automática de IP):
```bash
# nmap para escaneo de red
sudo pacman -S nmap

# arp-scan para detección ARP (AUR)
yay -S arp-scan
```

### En las VMs (Debian/Ubuntu)

- Sistema operativo Debian Trixie o Ubuntu reciente
- SSH habilitado y configurado
- Usuario con permisos sudo
- **Para la plantilla base**: Configurar inicialmente con DHCP en la interfaz de red

---

## 🏗️ Arquitectura del Sistema

```
┌─────────────────────────────────────────────────────────┐
│                   Host (Arch Linux)                      │
│                                                          │
│  ┌────────────────────────────────────────────────┐    │
│  │         Red Host-Only (192.168.56.0/24)        │    │
│  │                                                 │    │
│  │  ┌──────────────────────────────────────────┐  │    │
│  │  │   Balanceador HAProxy (192.168.56.2)    │  │    │
│  │  │   - Puerto 80: Balanceo HTTP            │  │    │
│  │  │   - Stats: /haproxy?stats               │  │    │
│  │  └──────────────────────────────────────────┘  │    │
│  │                      │                          │    │
│  │           ┌──────────┴──────────┐              │    │
│  │           │                     │              │    │
│  │  ┌────────▼────────┐   ┌───────▼────────┐    │    │
│  │  │  Servidor 1     │   │  Servidor 2     │    │    │
│  │  │  192.168.56.10  │   │  192.168.56.11  │    │    │
│  │  │  Puerto: 8000   │   │  Puerto: 8000   │    │    │
│  │  └─────────────────┘   └─────────────────┘    │    │
│  └────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

---

## 🔧 Script 1: `setup_balancer.sh`

### Propósito
Configura una VM como balanceador de carga HAProxy con configuración base inicial.

### Uso

```bash
./setup_balancer.sh \
  --balancer-host 192.168.56.2 \
  --user debian \
  --password '1234' \
  --port 80
```

### Parámetros

| Parámetro | Descripción | Obligatorio |
|-----------|-------------|-------------|
| `--balancer-host` | IP del balanceador | ✅ Sí |
| `--user` | Usuario SSH | ✅ Sí |
| `--password` | Contraseña sudo | ✅ Sí |
| `--port` | Puerto HTTP (default: 80) | ❌ No |

### ¿Qué hace?

1. ✅ Verifica conectividad con la VM
2. 🔑 Valida acceso SSH
3. 🌐 Verifica conectividad a internet
4. 📦 Instala HAProxy
5. ⚙️ Crea configuración base (sin backends)
6. 🔄 Habilita e inicia el servicio

### Resultado

- HAProxy instalado y funcionando
- Interfaz de estadísticas disponible en: `http://192.168.56.2/haproxy?stats`
  - Usuario: `admin`
  - Contraseña: `admin`
- Sistema listo para recibir servidores backend

---

## 🖥️ Script 2: `add_server.sh`

### Propósito
Clona una VM, detecta su IP automáticamente, la configura como estática y la registra en HAProxy.

### Uso

```bash
./add_server.sh \
  --base-vm plantilla-servicio \
  --vm-name servidor-10 \
  --disk-path /home/discos/srvimg.vdi \
  --vm-user debian \
  --vm-password '1234' \
  --network-range 192.168.56 \
  --backend-port 8000 \
  --balancer-host 192.168.56.2 \
  --balancer-user debian \
  --balancer-pass '1234'
```

### Parámetros

| Parámetro | Descripción | Obligatorio |
|-----------|-------------|-------------|
| `--base-vm` | VM plantilla a clonar | ✅ Sí |
| `--vm-name` | Nombre de la nueva VM | ✅ Sí |
| `--disk-path` | Ruta del disco VDI a montar | ❌ No |
| `--vm-user` | Usuario SSH de la VM | ✅ Sí |
| `--vm-password` | Contraseña sudo de la VM | ✅ Sí |
| `--network-range` | Rango de red (ej: 192.168.56) | ✅ Sí |
| `--gateway` | Gateway (default: `<network-range>.1`) | ❌ No |
| `--backend-port` | Puerto del servicio (default: 8000) | ❌ No |
| `--balancer-host` | IP del balanceador | ✅ Sí |
| `--balancer-user` | Usuario SSH del balanceador | ✅ Sí |
| `--balancer-pass` | Contraseña del balanceador | ✅ Sí |
| `--static-ip` | IP estática manual (opcional) | ❌ No |
| `--timeout` | Timeout detección IP (default: 30s) | ❌ No |

### ¿Qué hace?

1. 🔍 Verifica que la VM base existe
2. 🌀 Clona la VM (con reintentos si falla)
3. 💾 Monta disco adicional si se especifica
4. 🚀 Inicia la VM
5. 🔍 **Detecta automáticamente la IP asignada por DHCP** usando:
   - VBoxManage Guest Properties (más confiable)
   - nmap (si está instalado)
   - arp-scan (si está instalado)
   - Tabla ARP del sistema
6. ⚙️ Configura la IP detectada como estática en `/etc/network/interfaces`
7. 💻 Configura hostname y `/etc/hosts`
8. 🔄 Reinicia la VM para aplicar cambios
9. 🔗 Agrega el servidor al backend de HAProxy
10. ♻️ Recarga HAProxy

### Métodos de Detección de IP

El script intenta 4 métodos en orden:

#### 1. VBoxManage Guest Properties (más confiable)
Requiere VirtualBox Guest Additions instalado en la VM.

#### 2. nmap (recomendado)
```bash
sudo pacman -S nmap
```

#### 3. arp-scan (AUR, muy preciso)
```bash
yay -S arp-scan
```

#### 4. Tabla ARP del sistema
Usa `ip neigh` - menos confiable pero no requiere instalación adicional.

### Resultado

- Nueva VM creada y configurada con IP estática
- Servidor agregado al pool de HAProxy
- Backend listo para recibir tráfico

---

## 🗑️ Script 3: `remove_server.sh`

### Propósito
Elimina una VM del cluster y limpia su configuración en HAProxy usando detección automática de IP con nmap.

### Uso

```bash
# Eliminar VM completamente
./remove_server.sh \
  --vm-name servidor-10 \
  --vm-user debian \
  --vm-password '1234' \
  --network-range 192.168.56 \
  --backend-port 8080 \
  --balancer-host 192.168.56.2 \
  --balancer-user debian \
  --balancer-pass '1234'

# Solo remover de HAProxy (mantener VM)
./remove_server.sh \
  --vm-name servidor-10 \
  --vm-user debian \
  --vm-password '1234' \
  --network-range 192.168.56 \
  --backend-port 8080 \
  --balancer-host 192.168.56.2 \
  --balancer-user debian \
  --balancer-pass '1234' \
  --keep-vm

# Solo remover del HAProxy sin eliminar la VM
./remove_server.sh \
  --vm-name servidor-10 \
  --vm-user debian \
  --vm-password '1234' \
  --network-range 192.168.56 \
  --backend-port 8080 \
  --balancer-host 192.168.56.2 \
  --balancer-user debian \
  --balancer-pass '1234' \
  --keep-vm
```

### Parámetros

| Parámetro | Descripción | Obligatorio |
|-----------|-------------|-------------|
| `--vm-name` | Nombre de la VM a eliminar | ✅ Sí |
| `--vm-user` | Usuario SSH de la VM | ✅ Sí |
| `--vm-password` | Contraseña SSH de la VM | ✅ Sí |
| `--network-range` | Rango de red (ej: 192.168.56) | ✅ Sí |
| `--backend-port` | Puerto del servicio (default: 8080) | ❌ No |
| `--balancer-host` | IP del balanceador | ✅ Sí |
| `--balancer-user` | Usuario SSH del balanceador | ✅ Sí |
| `--balancer-pass` | Contraseña del balanceador | ✅ Sí |
| `--force` | No pedir confirmación | ❌ No |
| `--keep-vm` | Solo remover de HAProxy | ❌ No |

### ¿Qué hace?

1. 🔍 **Escanea la red con nmap** para encontrar la VM por hostname
2. 🔍 **Detecta automáticamente la IP** de la VM antes de eliminarla
3. 🛑 Detiene la VM si está corriendo
4. 🗑️ Elimina la VM y sus archivos (a menos que `--keep-vm`)
5. 📋 Crea backup de configuración de HAProxy con timestamp
6. 🔧 **Elimina la entrada exacta del servidor** usando `hostname + IP + puerto`
7. 📄 **Muestra el archivo de configuración** después de la modificación
8. ✅ Valida la nueva configuración buscando errores fatales
9. 🔄 Recarga HAProxy si todo es correcto

⚠️ **Nota**: El script elimina directamente sin pedir confirmación. Usa `--keep-vm` si solo quieres remover del HAProxy.

### Detección de IP

El script usa **nmap** para:
- Escanear el rango de red especificado (`.102-254`)
- Conectarse por SSH a cada IP detectada
- Obtener el hostname de cada máquina
- Identificar la VM correcta por su hostname

Esto asegura que se elimine la entrada correcta del HAProxy, incluso si la IP cambió.

### Validación de Configuración

El script valida la configuración de HAProxy buscando **errores fatales**:
- Si encuentra `"Fatal errors found in configuration"` → Restaura el backup automáticamente
- Si no hay errores → Recarga HAProxy y aplica los cambios

### Resultado

- VM eliminada de VirtualBox (o solo de HAProxy si `--keep-vm`)
- Configuración de HAProxy limpia y validada
- Backup de configuración guardado en: `/etc/haproxy/haproxy.cfg.backup.YYYYMMDD_HHMMSS`
- HAProxy recargado automáticamente

### ⚠️ Nota Importante sobre el Puerto

Asegúrate de especificar el puerto correcto con `--backend-port`. Si tu servidor usa un puerto diferente al default (8080), el script podría no encontrar la entrada exacta y buscará solo por hostname.

Ejemplo:
```bash
# Si tu servidor usa puerto 8000
./remove_server.sh ... --backend-port 8000

# Si tu servidor usa puerto 3000
./remove_server.sh ... --backend-port 3000
```

---

## 🎯 Flujo de Trabajo Completo

### 1. Preparación Inicial

```bash
# Configurar el balanceador
./setup_balancer.sh \
  --balancer-host 192.168.56.2 \
  --user debian \
  --password '1234'
```

### 2. Agregar Servidores al Cluster

```bash
# Agregar servidor 1
./add_server.sh \
  --base-vm plantilla-servicio \
  --vm-name servidor-10 \
  --disk-path /home/discos/srvimg.vdi \
  --vm-user debian \
  --vm-password '1234' \
  --network-range 192.168.56 \
  --balancer-host 192.168.56.2 \
  --balancer-user debian \
  --balancer-pass '1234'

# Agregar servidor 2
./add_server.sh \
  --base-vm plantilla-servicio \
  --vm-name servidor-11 \
  --disk-path /home/discos/srvimg.vdi \
  --vm-user debian \
  --vm-password '1234' \
  --network-range 192.168.56 \
  --balancer-host 192.168.56.2 \
  --balancer-user debian \
  --balancer-pass '1234'

# Agregar servidor 3
./add_server.sh \
  --base-vm plantilla-servicio \
  --vm-name servidor-12 \
  --disk-path /home/discos/srvimg.vdi \
  --vm-user debian \
  --vm-password '1234' \
  --network-range 192.168.56 \
  --balancer-host 192.168.56.2 \
  --balancer-user debian \
  --balancer-pass '1234'
```

### 3. Verificar el Cluster

```bash
# Ver estadísticas de HAProxy
curl http://192.168.56.2/haproxy?stats

# O abrir en navegador
firefox http://192.168.56.2/haproxy?stats
```

### 4. Probar el Balanceo

```bash
# Hacer varias peticiones al balanceador
for i in {1..10}; do
  curl http://192.168.56.2/
  echo ""
done
```

### 5. Escalar el Cluster (agregar más servidores)

```bash
./add_server.sh \
  --base-vm plantilla-servicio \
  --vm-name servidor-13 \
  --disk-path /home/discos/srvimg.vdi \
  --vm-user debian \
  --vm-password '1234' \
  --network-range 192.168.56 \
  --balancer-host 192.168.56.2 \
  --balancer-user debian \
  --balancer-pass '1234'
```

### 6. Eliminar Servidores

```bash
# Eliminar un servidor completamente
./remove_server.sh \
  --vm-name servidor-13 \
  --vm-user debian \
  --vm-password '1234' \
  --network-range 192.168.56 \
  --backend-port 8000 \
  --balancer-host 192.168.56.2 \
  --balancer-user debian \
  --balancer-pass '1234'

# Solo remover del HAProxy sin eliminar la VM
./remove_server.sh \
  --vm-name servidor-12 \
  --vm-user debian \
  --vm-password '1234' \
  --network-range 192.168.56 \
  --backend-port 8000 \
  --balancer-host 192.168.56.2 \
  --balancer-user debian \
  --balancer-pass '1234' \
  --keep-vm
```

---

## 📝 Configuración de la VM Plantilla

Para que la detección automática de IP funcione correctamente, la VM plantilla debe:

### 1. Configurar Red con DHCP

Editar `/etc/network/interfaces`:

```bash
source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
allow-hotplug enp0s3
iface enp0s3 inet dhcp

# This is an autoconfigured IPv6 interface
iface enp0s3 inet6 auto
```

### 2. Instalar VirtualBox Guest Additions (recomendado)

```bash
# En la VM
sudo apt-get update
sudo apt-get install -y build-essential dkms linux-headers-$(uname -r)

# Montar el CD de Guest Additions desde VirtualBox
# Devices → Insert Guest Additions CD image...

sudo mount /dev/cdrom /mnt
sudo /mnt/VBoxLinuxAdditions.run
sudo reboot
```

### 3. Configurar SSH

```bash
sudo apt-get install -y openssh-server
sudo systemctl enable ssh
sudo systemctl start ssh
```

---

## 🔧 Troubleshooting

### Problema: No se detecta la IP automáticamente

**Solución 1**: Instalar herramientas de detección
```bash
sudo pacman -S nmap
yay -S arp-scan
```

**Solución 2**: Especificar IP manualmente
```bash
./add_server.sh ... --static-ip 192.168.56.15
```

**Solución 3**: Instalar Guest Additions en la plantilla
```bash
# En la VM plantilla
sudo apt-get install virtualbox-guest-utils
```

### Problema: Error al clonar VM

**Causa**: VM base no existe o tiene problemas

**Solución**:
```bash
# Listar VMs disponibles
VBoxManage list vms

# Verificar estado de la VM base
VBoxManage showvminfo plantilla-servicio
```

### Problema: HAProxy no inicia

**Causa**: Error en configuración

**Solución**:
```bash
# Validar configuración
sudo haproxy -c -f /etc/haproxy/haproxy.cfg

# Ver logs
sudo journalctl -u haproxy -n 50

# Restaurar último backup si hay problemas
sudo cp /etc/haproxy/haproxy.cfg.backup.* /etc/haproxy/haproxy.cfg
sudo systemctl restart haproxy
```

### Problema: Script remove_server.sh dice que la configuración es inválida

**Causa**: Formato incorrecto en haproxy.cfg o puerto equivocado

**Solución 1**: Verificar el puerto correcto
```bash
# Ver qué puertos están configurados
ssh debian@192.168.56.2 "grep 'server' /etc/haproxy/haproxy.cfg"

# Si el servidor usa 8080 en lugar de 8000:
./remove_server.sh ... --backend-port 8080
```

**Solución 2**: Ver el archivo de configuración después de modificación
El script automáticamente muestra el contenido del archivo después de eliminar la entrada. Busca errores de sintaxis.

**Solución 3**: Restaurar backup manualmente
Los backups se guardan automáticamente con timestamp:
```bash
ssh debian@192.168.56.2
ls -lth /etc/haproxy/haproxy.cfg.backup.*
sudo cp /etc/haproxy/haproxy.cfg.backup.20241006_143022 /etc/haproxy/haproxy.cfg
sudo systemctl reload haproxy
```

### Problema: VM no responde después de configurar IP estática

**Causa**: Gateway o DNS incorrectos

**Solución**:
```bash
# Verificar gateway de la red host-only
VBoxManage list hostonlyifs

# Asegurarse de que el gateway coincide
```

### Problema: No hay conectividad a internet en el balanceador

**Causa**: Solo tiene adaptador host-only

**Solución**: Agregar adaptador NAT
```bash
# Apagar la VM primero
VBoxManage modifyvm balancer-debian --nic2 nat

# Iniciar y verificar
VBoxManage startvm balancer-debian --type headless
```

---

## 📊 Monitoreo y Gestión

### Ver configuración actual de HAProxy

```bash
ssh debian@192.168.56.2
sudo cat /etc/haproxy/haproxy.cfg
```

### Ver servidores registrados

```bash
ssh debian@192.168.56.2
sudo grep "^    server" /etc/haproxy/haproxy.cfg
```

### Recargar HAProxy manualmente

```bash
ssh debian@192.168.56.2
sudo systemctl reload haproxy
```

### Ver logs de HAProxy

```bash
ssh debian@192.168.56.2
sudo journalctl -u haproxy -f
```

---

## 🎨 Personalización

### Cambiar puerto del balanceador

Editar `setup_balancer.sh` o usar:
```bash
./setup_balancer.sh ... --port 8080
```

### Cambiar algoritmo de balanceo

Editar `/etc/haproxy/haproxy.cfg` en el balanceador:

```
backend http_back
    balance leastconn  # o: source, uri, etc.
    ...
```

### Agregar health checks personalizados

```
backend http_back
    option httpchk GET /health
    http-check expect status 200
    ...
```

---

## 📚 Referencias

- [Documentación de HAProxy](https://www.haproxy.org/documentation/)
- [VirtualBox Manual](https://www.virtualbox.org/manual/)
- [Debian Network Configuration](https://wiki.debian.org/NetworkConfiguration)

---

## ⚠️ Notas Importantes

1. **Seguridad**: Los scripts usan contraseñas en texto plano por simplicidad. Para producción, considera usar claves SSH.
2. **Red Host-Only**: Las VMs solo son accesibles desde el host. Para acceso externo, configura port forwarding o usa bridge.
3. **Backups Automáticos**: 
   - `remove_server.sh` crea backups automáticos con timestamp antes de modificar HAProxy
   - Los backups se guardan en `/etc/haproxy/haproxy.cfg.backup.YYYYMMDD_HHMMSS`
   - Si la validación falla, el backup se restaura automáticamente
4. **Recursos**: Cada VM consume recursos del host. Ajusta CPU/RAM según disponibilidad.
5. **Puerto del Backend**: 
   - El default para `add_server.sh` es **8000**
   - El default para `remove_server.sh` es **8080**
   - Asegúrate de especificar el puerto correcto con `--backend-port`
6. **Detección de IP**: 
   - Tanto `add_server.sh` como `remove_server.sh` usan **nmap** para escanear la red
   - Se requiere que nmap esté instalado: `sudo pacman -S nmap`
   - Los scripts conectan por SSH a cada IP para obtener el hostname
7. **Validación de HAProxy**:
   - La configuración se valida antes de recargar el servicio
   - Si se detectan "Fatal errors", se restaura el backup automáticamente

---

## 🤝 Contribuciones

Para reportar problemas o sugerir mejoras, por favor crea un issue en el repositorio.

---

**¡Feliz despliegue! 🚀**
