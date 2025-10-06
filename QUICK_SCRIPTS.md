# 🚀 Quick Scripts - Gestión Rápida del Cluster

Scripts simplificados para operaciones rápidas sin menú interactivo.

## 📝 Scripts Disponibles

### 1️⃣ `quick_add_server.sh` - Agregar Servidor

Agrega un nuevo servidor al cluster rápidamente.

**Uso:**
```bash
# Interactivo (pregunta el nombre)
./quick_add_server.sh

# Con nombre como argumento
./quick_add_server.sh servidor5
```

**Variables configurables:**
```bash
BASE_VM="plantilla"
DISK_PATH="/home/amador/VirtualBox VMs/plantilla-servicio/servicioimg.vdi"
VM_USER="debian"
VM_PASSWORD="debian"
NETWORK_RANGE="192.168.56.102-254"
BACKEND_PORT="8080"
BALANCER_HOST="192.168.56.101"
BALANCER_USER="debian"
BALANCER_PASSWORD="debian"
```

---

### 2️⃣ `quick_remove_server.sh` - Eliminar Servidor

Elimina un servidor del cluster mostrando primero la lista de servidores activos.

**Uso:**
```bash
# Interactivo (lista servidores y pregunta cuál eliminar)
./quick_remove_server.sh

# Con nombre como argumento
./quick_remove_server.sh servidor5
```

**Variables configurables:**
```bash
VM_USER="debian"
VM_PASSWORD="debian"
NETWORK_RANGE="192.168.56.102-254"
BACKEND_PORT="8080"
BALANCER_HOST="192.168.56.101"
BALANCER_USER="debian"
BALANCER_PASSWORD="debian"
```

---

### 3️⃣ `quick_setup_balancer.sh` - Configurar HAProxy

Configura el balanceador HAProxy con opción de escaneo automático.

**Uso:**
```bash
./quick_setup_balancer.sh
```

Preguntará si desea escanear la red y agregar servidores automáticamente:
- **Sí (S)**: Escanea la red y configura HAProxy con todos los servidores detectados
- **No (n)**: Configura HAProxy vacío (sin servidores backend)

**Variables configurables:**
```bash
BALANCER_HOST="192.168.56.101"
BALANCER_USER="debian"
BALANCER_PASSWORD="debian"
BALANCER_PORT="80"

# Para escaneo automático:
NETWORK_RANGE="192.168.56.102-254"
VM_USER="debian"
VM_PASSWORD="debian"
BACKEND_PORT="8080"
```

---

## 🔧 Personalización

Para cambiar la configuración, edita las variables al inicio de cada script:

```bash
# Ejemplo: quick_add_server.sh
nano quick_add_server.sh

# Modifica las variables:
export BASE_VM="mi-plantilla"
export DISK_PATH="/ruta/a/mi/disco.vdi"
export VM_USER="mi-usuario"
# ... etc
```

O exporta las variables antes de ejecutar:

```bash
export BASE_VM="mi-plantilla"
export BACKEND_PORT="9000"
./quick_add_server.sh servidor10
```

---

## 💡 Ejemplos de Uso

### Agregar 3 servidores rápidamente
```bash
./quick_add_server.sh servidor2
./quick_add_server.sh servidor3
./quick_add_server.sh servidor4
```

### Configurar HAProxy desde cero
```bash
./quick_setup_balancer.sh
# Responder: S (para escanear y detectar servidores)
```

### Eliminar un servidor
```bash
./quick_remove_server.sh
# Mostrará la lista de servidores
# Ingresar el nombre del servidor a eliminar
```

### Eliminar directamente
```bash
./quick_remove_server.sh servidor4
# Confirmará antes de eliminar
```

---

## 🆚 Quick Scripts vs Menu vs Scripts Principales

| Característica | Quick Scripts | Menu (`menu.sh`) | Scripts Principales |
|----------------|---------------|------------------|---------------------|
| **Velocidad** | ⚡ Rápido | 🐢 Medio | 🐌 Completo |
| **Interactividad** | Mínima | Alta | Parámetros |
| **Configuración** | Variables | Editable | CLI |
| **Uso** | Tareas repetitivas | Exploración | Automatización |
| **Ideal para** | Scripts/Automatización | Usuarios nuevos | CI/CD |

---

## 🎯 Cuándo Usar Cada Uno

### Usa `quick_*` cuando:
- ✅ Necesitas velocidad
- ✅ Ya conoces la configuración
- ✅ Quieres automatizar con scripts
- ✅ Agregar/eliminar servidores frecuentemente

### Usa `menu.sh` cuando:
- ✅ Estás aprendiendo el sistema
- ✅ Quieres ver todas las opciones
- ✅ Necesitas editar configuración
- ✅ Prefieres interfaz guiada

### Usa scripts principales cuando:
- ✅ Necesitas máximo control
- ✅ Integración con otros sistemas
- ✅ Parámetros específicos por ejecución
- ✅ Scripts de CI/CD

---

## 📦 Requisitos

Los mismos que los scripts principales:
- `sshpass`
- `nmap` (para quick_remove y quick_setup con escaneo)
- `VirtualBox`

---

## 🔐 Seguridad

⚠️ **IMPORTANTE**: Estos scripts contienen contraseñas en texto plano.

**Para producción:**
1. Usa variables de entorno
2. Archivos `.env` con permisos restrictivos
3. Vaults de secretos (HashiCorp Vault, etc.)

```bash
# Ejemplo con variables de entorno
export BALANCER_PASSWORD="mi-password-seguro"
./quick_setup_balancer.sh
```

---

¡Scripts listos para usar! 🚀
