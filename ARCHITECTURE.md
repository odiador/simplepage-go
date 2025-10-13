# 📊 Arquitectura del Auto-Scaler

## Visión General

```
┌─────────────────────────────────────────────────────────────────┐
│                     SISTEMA AUTO-SCALER                         │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────┐         ┌──────────────────┐
│   Balanceador    │◄────────│  Auto-Scaler     │
│   HAProxy        │  Monitor│  (autoscaler.sh) │
│  192.168.56.101  │   CPU   │                  │
└──────────────────┘         └─────────┬────────┘
         │                             │
         │ Load Balance                │ Manage
         │                             │
    ┌────▼────────────────────────┐    │
    │   Backend Servers Pool      │    │
    │   192.168.56.102-254        │    │
    │                             │    │
    │  ┌──────┐  ┌──────┐        │    │
    │  │ VM 1 │  │ VM 2 │  ...   │◄───┘
    │  └──────┘  └──────┘        │
    └─────────────────────────────┘
```

## Flujo de Decisión

```
                    ┌─────────────────┐
                    │  Inicio Ciclo   │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  Leer CPU del   │
                    │   Balanceador   │
                    └────────┬────────┘
                             │
                ┌────────────▼────────────┐
                │  Contar Servidores      │
                │  Activos en la Red      │
                └────────────┬────────────┘
                             │
                ┌────────────▼────────────┐
                │  Evaluar Decisión       │
                └────────────┬────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
    ┌────▼────┐         ┌────▼────┐        ┌────▼────┐
    │ CPU > 85│         │ CPU OK  │        │CPU < 25 │
    │   (%)   │         │ 25-85%  │        │   (%)   │
    └────┬────┘         └────┬────┘        └────┬────┘
         │                   │                   │
    ┌────▼────┐         ┌────▼────┐        ┌────▼────┐
    │ AGREGAR │         │MANTENER │        │ELIMINAR │
    │ URGENTE │         │         │        │ URGENTE │
    └────┬────┘         └────┬────┘        └────┬────┘
         │                   │                   │
         │                   │                   │
    ┌────▼──────────────────┐│              ┌───▼─────────────────┐
    │quick_add_server.sh    ││              │quick_remove_server  │
    │                       ││              │        .sh          │
    │1. Clona VM plantilla  ││              │                     │
    │2. Detecta IP DHCP     ││              │1. Lista servidores  │
    │3. Configura IP fija   ││              │2. Selecciona uno    │
    │4. Actualiza HAProxy   ││              │3. Detiene VM        │
    │5. Reinicia HAProxy    ││              │4. Elimina VM        │
    └───────────────────────┘│              │5. Actualiza HAProxy │
                             │              └─────────────────────┘
                             │
                    ┌────────▼────────┐
                    │  Esperar        │
                    │  Cooldown (60s) │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  Esperar        │
                    │  Intervalo(20s) │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  Repetir Ciclo  │
                    └─────────────────┘
```

## Umbrales de Decisión

```
 100% │                                    ╔═══════════════╗
      │                                    ║  CRÍTICO      ║
  85% ├────────────────────────────────────╬═══════════════╣
      │                                    ║  AGREGAR      ║
      │                                    ║               ║
  75% ├────────────────────────────────────╬═══════════════╣
      │                                    ║               ║
      │                                    ║  ZONA ÓPTIMA  ║
      │                                    ║               ║
  40% ├────────────────────────────────────╬═══════════════╣
      │                                    ║  ELIMINAR     ║
  25% ├────────────────────────────────────╬═══════════════╣
      │                                    ║  MUY BAJO     ║
   0% └────────────────────────────────────╨───────────────┘
```

## Ciclo de Vida de Servidor

```
┌──────────────┐
│  Necesidad   │ (CPU Alta)
│  Detectada   │
└──────┬───────┘
       │
       ▼
┌──────────────┐     ┌─────────────────────────┐
│   Cooldown   │────►│ ¿Han pasado 60s desde   │
│   Check      │     │ la última acción?       │
└──────┬───────┘     └───────┬─────────────────┘
       │                     │
       │                     │ No ──► Esperar
       │                     │
       │                     ▼ Sí
       │              ┌──────────────┐
       │              │  Ejecutar    │
       │              │  Acción      │
       │              └──────┬───────┘
       │                     │
       ▼                     ▼
┌──────────────────────────────────────┐
│        AGREGAR SERVIDOR              │
├──────────────────────────────────────┤
│ 1. VBoxManage clonevm "plantilla"   │
│    ├─> Nombre: servidor-<timestamp> │
│    └─> Modo: linked                 │
│                                      │
│ 2. VBoxManage startvm                │
│    └─> Modo: headless               │
│                                      │
│ 3. Esperar DHCP (30s)                │
│    └─> nmap -sn 192.168.56.0/24     │
│                                      │
│ 4. Detectar IP asignada              │
│    └─> Validar conectividad SSH     │
│                                      │
│ 5. Configurar IP estática            │
│    └─> Editar /etc/network/interfaces│
│                                      │
│ 6. Actualizar HAProxy                │
│    ├─> Agregar línea en backend     │
│    ├─> Validar configuración        │
│    └─> Reiniciar servicio           │
│                                      │
│ 7. Verificar health check            │
│    └─> curl -f http://IP:8080       │
└──────────────────────────────────────┘
       │
       ▼
┌──────────────┐
│  Servidor    │
│  Activo      │
└──────┬───────┘
       │
       │ (CPU Baja)
       ▼
┌──────────────────────────────────────┐
│       ELIMINAR SERVIDOR              │
├──────────────────────────────────────┤
│ 1. Listar servidores activos         │
│    └─> nmap + HAProxy config         │
│                                      │
│ 2. Seleccionar servidor              │
│    └─> Último en la lista            │
│                                      │
│ 3. Remover de HAProxy                │
│    ├─> Eliminar línea del backend   │
│    ├─> Validar configuración        │
│    └─> Reiniciar servicio           │
│                                      │
│ 4. Detener VM                        │
│    └─> VBoxManage controlvm poweroff│
│                                      │
│ 5. Eliminar VM y disco               │
│    └─> VBoxManage unregistervm      │
│         --delete                     │
└──────────────────────────────────────┘
       │
       ▼
┌──────────────┐
│  Servidor    │
│  Eliminado   │
└──────────────┘
```

## Timeline del Modo Prueba

```
Tiempo│ Fase │ CPU  │ Acción Esperada
──────┼──────┼──────┼─────────────────────────────
  0s  │  0   │ ~30% │ Sistema estable
 30s  │  1   │ ~50% │ Carga normal
 90s  │  2   │ ~80% │ → AGREGAR servidor
150s  │      │      │ (Cooldown 60s)
180s  │  3   │ ~95% │ → AGREGAR servidor (urgente)
240s  │  4   │ ~20% │ → ELIMINAR servidor
300s  │      │      │ (Cooldown 60s)
330s  │  5   │  0%  │ → ELIMINAR servidor
390s  │  6   │  -   │ Fin de prueba
```

## Componentes del Sistema

```
┌────────────────────────────────────────────────────────┐
│                  SCRIPTS PRINCIPALES                   │
├────────────────────────────────────────────────────────┤
│                                                        │
│  ┌──────────────────────────────────────────────┐    │
│  │  start_autoscaler.sh                         │    │
│  │  • Menú interactivo                          │    │
│  │  • Validación automática                     │    │
│  │  • Lanzador conveniente                      │    │
│  └────────────────┬─────────────────────────────┘    │
│                   │                                   │
│  ┌────────────────▼─────────────────────────────┐    │
│  │  autoscaler.sh                               │    │
│  │  • Loop de monitoreo                         │    │
│  │  • Lógica de decisión                        │    │
│  │  • Gestión de cooldown                       │    │
│  │  • Logging                                   │    │
│  └────────┬──────────────────┬──────────────────┘    │
│           │                  │                        │
│  ┌────────▼──────────┐  ┌───▼────────────────┐      │
│  │quick_add_server.sh│  │quick_remove_server │      │
│  │• Wrapper simple   │  │       .sh          │      │
│  │• Variables preset │  │• Wrapper simple    │      │
│  └────────┬──────────┘  └───┬────────────────┘      │
│           │                 │                        │
│  ┌────────▼──────────┐  ┌───▼────────────────┐      │
│  │  add_server.sh    │  │  remove_server.sh  │      │
│  │  • Clonación VM   │  │  • Detención VM    │      │
│  │  • Config red     │  │  • Eliminación VM  │      │
│  │  • Update HAProxy │  │  • Update HAProxy  │      │
│  └───────────────────┘  └────────────────────┘      │
│                                                        │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│                  UTILIDADES                            │
├────────────────────────────────────────────────────────┤
│                                                        │
│  ┌──────────────────────────────────────────────┐    │
│  │  validate_autoscaler.sh                      │    │
│  │  • Verifica dependencias                     │    │
│  │  • Prueba conectividad                       │    │
│  │  • Valida configuración                      │    │
│  │  • Reporte detallado                         │    │
│  └──────────────────────────────────────────────┘    │
│                                                        │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│                  DOCUMENTACIÓN                         │
├────────────────────────────────────────────────────────┤
│                                                        │
│  • AUTOSCALER.md           - Guía completa            │
│  • QUICKSTART_AUTOSCALER.md - Inicio rápido          │
│  • ARCHITECTURE.md         - Este archivo             │
│  • README.md               - Visión general           │
│                                                        │
└────────────────────────────────────────────────────────┘
```

## Interacción con VirtualBox

```
                    ┌─────────────────┐
                    │  Auto-Scaler    │
                    └────────┬────────┘
                             │
                   ┌─────────▼──────────┐
                   │   VBoxManage API   │
                   └────────┬───────────┘
                            │
              ┌─────────────┼─────────────┐
              │             │             │
         ┌────▼───┐    ┌────▼───┐   ┌────▼───┐
         │ Clone  │    │ Start  │   │ Delete │
         │   VM   │    │   VM   │   │   VM   │
         └────┬───┘    └────┬───┘   └────┬───┘
              │             │             │
              └─────────────┼─────────────┘
                            │
                   ┌────────▼────────┐
                   │  VirtualBox     │
                   │  Host-Only      │
                   │  Network        │
                   └─────────────────┘
                   192.168.56.0/24
```

## Flujo de Datos

```
  1. Monitoreo
     ┌─────────────────────────────────────┐
     │  autoscaler.sh                      │
     │    ├─> SSH al balanceador           │
     │    ├─> Ejecutar: top -bn1           │
     │    └─> Parsear % CPU                │
     └─────────────────────────────────────┘
              │
              ▼
  2. Decisión
     ┌─────────────────────────────────────┐
     │  evaluate_scaling()                 │
     │    ├─> Comparar con umbrales        │
     │    ├─> Verificar límites            │
     │    └─> Retornar acción              │
     └─────────────────────────────────────┘
              │
              ▼
  3. Cooldown
     ┌─────────────────────────────────────┐
     │  check_cooldown()                   │
     │    ├─> Leer timestamp anterior      │
     │    ├─> Calcular diferencia          │
     │    └─> Permitir o bloquear          │
     └─────────────────────────────────────┘
              │
              ▼
  4. Ejecución
     ┌─────────────────────────────────────┐
     │  add_server() / remove_server()     │
     │    ├─> Llamar script apropiado      │
     │    ├─> Log de inicio                │
     │    ├─> Esperar completación         │
     │    └─> Log de resultado             │
     └─────────────────────────────────────┘
              │
              ▼
  5. Logging
     ┌─────────────────────────────────────┐
     │  log_message()                      │
     │    ├─> Timestamp                    │
     │    ├─> Mensaje formateado           │
     │    ├─> stdout (terminal)            │
     │    └─> autoscaler.log (archivo)     │
     └─────────────────────────────────────┘
```

## Arquitectura de Archivos

```
/home/amador/gh/simplepage-go/
│
├── autoscaler.sh                 # Script principal
├── start_autoscaler.sh          # Launcher interactivo
├── validate_autoscaler.sh       # Validador de sistema
│
├── quick_add_server.sh          # Wrapper para agregar
├── quick_remove_server.sh       # Wrapper para eliminar
├── add_server.sh                # Lógica completa de agregar
├── remove_server.sh             # Lógica completa de eliminar
│
├── AUTOSCALER.md                # Documentación completa
├── QUICKSTART_AUTOSCALER.md     # Guía rápida
├── ARCHITECTURE.md              # Este archivo
│
├── autoscaler.log               # Log de operaciones (generado)
│
└── /tmp/
    ├── autoscaler_cooldown      # Estado de cooldown
    └── autoscaler_state         # Estado general (opcional)
```

## Métricas y Monitoring

```
┌──────────────────────────────────────────────────────┐
│              DASHBOARD CONCEPTUAL                    │
├──────────────────────────────────────────────────────┤
│                                                      │
│  CPU Balanceador: ██████████░░░░░░░░░░ 52%         │
│                                                      │
│  Servidores Activos: 3 / 5 (max)                   │
│  ┌─────┐ ┌─────┐ ┌─────┐                          │
│  │ VM1 │ │ VM2 │ │ VM3 │                          │
│  │  ✓  │ │  ✓  │ │  ✓  │                          │
│  └─────┘ └─────┘ └─────┘                          │
│                                                      │
│  Última Acción: AGREGAR (hace 45s)                 │
│  Cooldown: 15s restantes                           │
│                                                      │
│  Próxima Evaluación: 12s                           │
│                                                      │
│  Decisión Actual: MANTENER                         │
│                                                      │
└──────────────────────────────────────────────────────┘
```

---

**Nota:** Esta arquitectura está diseñada para ser modular, escalable y fácil de mantener. Cada componente tiene una responsabilidad clara y bien definida.
