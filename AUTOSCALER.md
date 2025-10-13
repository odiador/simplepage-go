# Auto-Scaler para Balanceador

Sistema de escalado automático que monitorea la CPU del balanceador HAProxy y ajusta dinámicamente el número de servidores backend según la carga.

## 📋 Características

- **Monitoreo en tiempo real**: Supervisa el uso de CPU del balanceador cada 20 segundos (configurable)
- **Escalado inteligente**: Agrega servidores cuando la carga es alta y los elimina cuando es baja
- **Protección por cooldown**: Evita cambios frecuentes con un período de espera entre acciones
- **Límites configurables**: Define mínimo y máximo de servidores
- **Modo de prueba**: Genera carga artificial para validar el funcionamiento
- **Logging completo**: Registra todas las acciones en `autoscaler.log`

## 🚀 Inicio Rápido

```bash
# Ejecutar con configuración por defecto
./autoscaler.sh

# Ejecutar en modo prueba (genera carga artificial)
./autoscaler.sh --modo-prueba

# Configuración personalizada
./autoscaler.sh --umbral-alto 80 --max-servidores 10 --intervalo 30
```

## ⚙️ Configuración

### Umbrales de CPU (%)

| Parámetro | Default | Descripción |
|-----------|---------|-------------|
| `--umbral-critico` | 85 | CPU crítica - agrega servidor urgentemente |
| `--umbral-alto` | 75 | CPU alta - agrega servidor |
| `--umbral-bajo` | 40 | CPU baja - elimina servidor |
| `--umbral-muy-bajo` | 25 | CPU muy baja - elimina servidor urgentemente |

### Límites de Servidores

| Parámetro | Default | Descripción |
|-----------|---------|-------------|
| `--min-servidores` | 2 | Número mínimo de servidores activos |
| `--max-servidores` | 5 | Número máximo de servidores activos |

### Temporización

| Parámetro | Default | Descripción |
|-----------|---------|-------------|
| `--intervalo` | 20 | Segundos entre cada verificación |
| `--cooldown` | 60 | Segundos de espera entre acciones de escalado |

## 📊 Cómo Funciona

### 1. Monitoreo
El script se conecta al balanceador y obtiene el uso de CPU cada intervalo:
```
CPU Balanceador: 78% | Servidores: 3 | Decisión: AGREGAR
```

### 2. Decisiones de Escalado

```
CPU > 85% y servidores < max → AGREGAR_URGENTE
CPU > 75% y servidores < max → AGREGAR
CPU < 25% y servidores > min → ELIMINAR_URGENTE
CPU < 40% y servidores > min → ELIMINAR
De lo contrario              → MANTENER
```

### 3. Ejecución
- **Agregar**: Ejecuta `quick_add_server.sh` con un nombre único
- **Eliminar**: Ejecuta `quick_remove_server.sh` que selecciona automáticamente el servidor

### 4. Cooldown
Después de cada acción, espera 60 segundos (configurable) antes de permitir otra modificación.

## 🧪 Modo de Prueba

El modo de prueba genera carga artificial en el balanceador para validar el auto-scaler:

```bash
./autoscaler.sh --modo-prueba
```

### Fases de la Prueba

1. **Fase 0 (0-30s)**: Sistema estable - CPU ~30%
2. **Fase 1 (30-90s)**: Carga normal - CPU ~50%
3. **Fase 2 (90-180s)**: Carga alta - CPU ~80% → **Espera agregar servidor**
4. **Fase 3 (180-240s)**: Carga crítica - CPU ~95% → **Espera agregar otro servidor**
5. **Fase 4 (240-330s)**: Carga baja - CPU ~20% → **Espera eliminar servidores**
6. **Fase 5 (330s+)**: Limpieza y fin de prueba

**Requisito**: El balanceador debe tener instalado `stress-ng`:
```bash
# En el balanceador
sudo apt-get update
sudo apt-get install -y stress-ng
```

## 📝 Ejemplos de Uso

### Escenario 1: Producción Estándar
```bash
./autoscaler.sh \
  --umbral-alto 70 \
  --umbral-critico 85 \
  --min-servidores 3 \
  --max-servidores 8 \
  --intervalo 30 \
  --cooldown 120
```

### Escenario 2: Desarrollo/Testing
```bash
./autoscaler.sh \
  --umbral-alto 60 \
  --min-servidores 1 \
  --max-servidores 3 \
  --intervalo 15 \
  --cooldown 30
```

### Escenario 3: Alta Disponibilidad
```bash
./autoscaler.sh \
  --umbral-alto 50 \
  --umbral-critico 70 \
  --min-servidores 5 \
  --max-servidores 15 \
  --intervalo 10 \
  --cooldown 90
```

## 📁 Archivos Generados

- `autoscaler.log`: Log completo de todas las operaciones
- `/tmp/autoscaler_cooldown`: Estado del cooldown
- `/tmp/autoscaler_state`: Estado general del sistema (opcional)

## 🔍 Monitoreo en Tiempo Real

Ver el log en tiempo real:
```bash
tail -f autoscaler.log
```

Ver solo las decisiones de escalado:
```bash
grep -E "AGREGANDO|ELIMINANDO|MANTENER" autoscaler.log
```

Ver el estado del sistema:
```bash
grep "📊 SISTEMA" autoscaler.log | tail -20
```

## ⚠️ Requisitos

### Dependencias del Sistema
```bash
sudo pacman -S sshpass nmap
```

### Scripts Requeridos
- `quick_add_server.sh`: Script para agregar servidores
- `quick_remove_server.sh`: Script para eliminar servidores

### Configuración de Red
- **Balanceador**: 192.168.56.101
- **Servidores**: 192.168.56.102-254
- **Usuario SSH**: debian
- **Contraseña**: debian

## 🛑 Detener el Auto-Scaler

Presiona `Ctrl+C` para detener el script de forma segura. El script:
1. Detendrá el monitoreo
2. Limpiará procesos de stress (si están activos)
3. Guardará el estado final en el log

## 🐛 Solución de Problemas

### Error: "No se puede conectar al balanceador"
```bash
# Verificar conectividad
ping 192.168.56.101
ssh debian@192.168.56.101

# Verificar sshpass
which sshpass
```

### Error: "Script no ejecutable"
```bash
chmod +x quick_add_server.sh quick_remove_server.sh autoscaler.sh
```

### Error: "nmap no disponible"
```bash
sudo pacman -S nmap
```

### CPU siempre en 0%
El script intenta múltiples métodos para obtener la CPU:
1. `top -bn1`
2. `mpstat`
3. `/proc/loadavg`

Verifica manualmente en el balanceador:
```bash
ssh debian@192.168.56.101
top -bn1 | grep 'Cpu(s)'
```

## 📈 Métricas y Estadísticas

El log incluye información detallada:

```
[2025-10-12 15:30:45] 📊 SISTEMA | CPU Balanceador: 78% | Servidores: 3 | Stress: NO | Decisión: AGREGAR
[2025-10-12 15:30:45]    🖥️  Servidores activos: 192.168.56.102 192.168.56.103 192.168.56.104
[2025-10-12 15:30:45] 📈 AGREGANDO - CPU balanceador alta: 78%
[2025-10-12 15:30:45] 🚀 EJECUTANDO: quick_add_server.sh (servidores: 3 → 4)
[2025-10-12 15:31:12] ✅ quick_add_server.sh ejecutado exitosamente - VM: servidor-1728745812
```

## 🔒 Seguridad

- Las contraseñas están en texto plano en el script (para entorno de desarrollo)
- Para producción, considera usar:
  - Claves SSH sin contraseña
  - Variables de entorno
  - Gestores de secretos (Vault, etc.)

## 📚 Arquitectura

```
┌─────────────────────────┐
│   autoscaler.sh         │
│   (Monitoreo de CPU)    │
└───────────┬─────────────┘
            │
            ├──> quick_add_server.sh
            │    └──> add_server.sh
            │         └──> VirtualBox VM
            │
            └──> quick_remove_server.sh
                 └──> remove_server.sh
                      └──> VirtualBox VM
```

## 🤝 Contribuir

Para mejorar el auto-scaler:

1. Ajusta los umbrales según tu carga real
2. Modifica los intervalos según tus necesidades
3. Agrega métricas adicionales (memoria, disco, etc.)
4. Implementa notificaciones (email, Slack, etc.)

## 📄 Licencia

Este script es parte del proyecto simplepage-go.

## 🆘 Soporte

Para problemas o preguntas:
1. Revisa el log: `tail -f autoscaler.log`
2. Verifica la conectividad con el balanceador
3. Asegúrate de que los scripts de gestión funcionen individualmente
4. Comprueba que VirtualBox esté funcionando correctamente

---

**Nota**: Este auto-scaler está diseñado para el entorno específico con VirtualBox y HAProxy. Ajusta las configuraciones según tu infraestructura.
