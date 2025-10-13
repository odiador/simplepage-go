  # Go Image Server

Un servidor web desarrollado en Go que sirve imágenes de distribuciones de Linux a través de una interfaz moderna con Bootstrap.

## 📋 Características

- **Servidor HTTP nativo de Go** - Rápido y eficiente
- **Conversión automática a Base64** - Las imágenes se embeben directamente en HTML
- **Selección aleatoria** - Muestra diferentes imágenes en cada carga
- **Diseño responsivo** - Interfaz adaptable a cualquier dispositivo
- **Tema oscuro moderno** - UI atractiva con animaciones CSS
- **Compilación cruzada** - Binarios para Linux, Windows y macOS
- **Despliegue simplificado** - Scripts automatizados incluidos

## 🚀 Inicio Rápido

### Compilar desde código fuente
```bash
git clone https://github.com/odiador/go.git
cd go
go mod tidy
./build.sh
```

### Ejecutar servidor
```bash
# Opción 1: Script automatizado
./deploy-and-run.sh

# Opción 2: Ejecución directa
./bin/image-server 8080
```

## 📁 Estructura del Proyecto

```
go-image-server/
├── cmd/image-server/           # Aplicación principal
│   └── main.go                 # Punto de entrada del servidor
├── internal/                   # Código interno del proyecto
│   ├── web/handlers.go         # Handlers HTTP
│   ├── images/scan.go          # Procesamiento de imágenes
│   └── templates/index.html    # Template HTML principal
├── images/                     # Imágenes de distribuciones Linux
├── bin/                        # Binarios compilados
├── build.sh                    # Script de compilación multiplataforma
├── deploy-and-run.sh          # Script de despliegue rápido
└── go.mod                     # Dependencias del módulo Go
```

## ⚙️ Configuración

El servidor se puede configurar mediante variables de entorno:

```bash
export PORT=8080                                    # Puerto del servidor
export IMAGE_DIR="./images"                         # Directorio de imágenes
export TEMPLATE_PATH="./internal/templates/index.html" # Ruta del template
```

## 🖼️ Imágenes Soportadas

El servidor procesa automáticamente archivos con las siguientes extensiones:
- `.png` - Portable Network Graphics
- `.jpg` - JPEG
- `.jpeg` - JPEG (extensión completa)

## 🔧 Desarrollo

### Requisitos
- Go 1.25 o superior
- Sistema Unix (Linux/macOS) para scripts de build

### Compilar manualmente
```bash
# Para el sistema actual
go build -o bin/image-server ./cmd/image-server

# Para Linux desde otro sistema
GOOS=linux GOARCH=amd64 go build -o bin/image-server-linux-amd64 ./cmd/image-server
```

### Ejecutar en modo desarrollo
```bash
go run cmd/image-server/main.go 8080
```

## 🌐 API

El servidor expone un único endpoint:

- **GET /** - Página principal con galería de imágenes
  - Retorna HTML con 4 imágenes seleccionadas aleatoriamente
  - Las imágenes están codificadas en Base64 para visualización directa

## 📦 Despliegue

### Despliegue Local
```bash
# Compilar
./build.sh

# Los binarios estarán en bin/
ls -la bin/
```

### Despliegue en Servidor Remoto
```bash
# Transferir paquete completo
scp -r bin/deploy-linux-amd64/* usuario@servidor:/ruta/destino/

# En el servidor remoto
cd /ruta/destino/
./deploy-and-run.sh
```

### Docker (Opcional)
```bash
docker build -t go-image-server .
docker run -p 8080:8080 -v $(pwd)/images:/app/images go-image-server
```

## 🎨 Personalización

### Cambiar Imágenes
1. Reemplaza los archivos en la carpeta `images/`
2. Asegúrate de usar formatos soportados (PNG, JPG, JPEG)
3. Reinicia el servidor

### Modificar Template
1. Edita `internal/templates/index.html`
2. El template usa sintaxis de Go templates
3. Variables disponibles: `{{.Title}}`, `{{.Host}}`, `{{.Images}}`

### Cambiar Estilos
El template incluye CSS personalizado para:
- Gradientes de fondo
- Animaciones de hover en tarjetas
- Tema oscuro completo
- Grid responsivo

## 🧪 Pruebas

```bash
# Verificar que el servidor responde
curl http://localhost:8080

# Verificar imágenes en el directorio
ls -la images/

# Verificar template
cat internal/templates/index.html
```

## 🤖 Auto-Scaler (Nuevo)

Sistema de escalado automático que monitorea la CPU del balanceador HAProxy y ajusta dinámicamente el número de servidores backend según la carga.

### Inicio Rápido del Auto-Scaler

```bash
# Validar configuración y ejecutar
./start_autoscaler.sh

# O ejecutar directamente
./autoscaler.sh

# Modo prueba con carga artificial
./autoscaler.sh --modo-prueba
```

### Características del Auto-Scaler

- ✅ **Monitoreo en tiempo real** - Supervisa CPU del balanceador cada 20 segundos
- ✅ **Escalado inteligente** - Agrega/elimina servidores según umbrales configurables
- ✅ **Protección por cooldown** - Evita cambios frecuentes entre acciones
- ✅ **Límites configurables** - Define mínimo y máximo de servidores
- ✅ **Modo de prueba** - Genera carga artificial para validar funcionamiento
- ✅ **Logging completo** - Registra todas las acciones en `autoscaler.log`

### Documentación Completa

Consulta [AUTOSCALER.md](AUTOSCALER.md) para documentación detallada del auto-scaler.

## 📚 Documentación Técnica

- Cada archivo incluye documentación detallada de funciones y estructuras
- Comentarios explicativos en código complejo
- Variables y parámetros documentados según estándares de Go

## 🤝 Contribuir

1. Fork del repositorio
2. Crear branch para feature (`git checkout -b feature/nueva-funcionalidad`)
3. Commit cambios (`git commit -am 'Agregar nueva funcionalidad'`)
4. Push al branch (`git push origin feature/nueva-funcionalidad`)
5. Crear Pull Request

## 📄 Licencia

Este proyecto es para fines educativos como parte del curso de Computación en la Nube.

## 👥 Autores

- **Juan Amador**
- **Santiago Londoño**

**Curso:** Computación en la nube  
**Período:** 2025-2

---

**¿Necesitas ayuda?** Revisa la documentación en `DOCUMENTACION.md` o los comentarios en el código fuente.
