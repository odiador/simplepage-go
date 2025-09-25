#!/bin/bash

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}         Go Image Server - Build Script${NC}"
echo -e "${BLUE}================================================${NC}"
echo

# Verificar que Go esté instalado
if ! command -v go &> /dev/null; then
    echo -e "${RED}ERROR: Go no está instalado o no está en el PATH${NC}"
    exit 1
fi

echo -e "${YELLOW}[INFO]${NC} Versión de Go:"
go version
echo

# Crear directorio de binarios si no existe
mkdir -p bin

echo -e "${YELLOW}[INFO]${NC} Limpiando builds anteriores..."
rm -f bin/image-server-* bin/image-server
rm -rf bin/deploy-*
echo

# Función para compilar con manejo de errores
build_binary() {
    local os=$1
    local arch=$2
    local output_name=$3
    
    echo -e "${YELLOW}[INFO]${NC} Compilando para $os ($arch)..."
    
    if GOOS=$os GOARCH=$arch go build -ldflags="-s -w" -o "bin/$output_name" ./cmd/image-server; then
        echo -e "${GREEN}[OK]${NC} Binario $os creado: bin/$output_name"
        
        # Hacer ejecutable en sistemas Unix
        if [[ "$os" != "windows" ]]; then
            chmod +x "bin/$output_name"
        fi
    else
        echo -e "${RED}ERROR: Falló la compilación para $os${NC}"
        exit 1
    fi
}

# Función para crear paquete de despliegue
create_deploy_package() {
    local platform=$1
    local binary_name=$2
    local deploy_dir="bin/deploy-$platform"
    
    echo -e "${CYAN}[DEPLOY]${NC} Creando paquete de despliegue para $platform..."
    
    # Crear estructura de directorios
    mkdir -p "$deploy_dir"/{internal/templates,images,scripts}
    
    # Copiar binario
    cp "bin/$binary_name" "$deploy_dir/"
    
    # Copiar template
    cp internal/templates/index.html "$deploy_dir/internal/templates/"
    
    # Copiar imágenes de ejemplo
    if [ -d "images" ]; then
        cp images/* "$deploy_dir/images/" 2>/dev/null || echo -e "${YELLOW}[WARN]${NC} No se encontraron imágenes para copiar"
    fi
    
    # Crear script de ejecución personalizado
    if [[ "$platform" == "linux"* ]]; then
        create_run_script_linux "$deploy_dir" "$binary_name"
    elif [[ "$platform" == "windows"* ]]; then
        create_run_script_windows "$deploy_dir" "$binary_name"
    fi
    
    # Crear README
    create_readme "$deploy_dir" "$platform" "$binary_name"
    
    echo -e "${GREEN}[OK]${NC} Paquete creado: $deploy_dir"
}

# Función para crear script de ejecución Linux
create_run_script_linux() {
    local deploy_dir=$1
    local binary_name=$2
    
    cat > "$deploy_dir/run.sh" << 'EOF'
#!/bin/bash

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}       Go Image Server - Launcher${NC}"
echo -e "${CYAN}========================================${NC}"
echo

# Valores por defecto
DEFAULT_PORT="8080"
DEFAULT_IMAGE_DIR="./images"
DEFAULT_TEMPLATE_DIR="./internal/templates/index.html"

echo -e "${YELLOW}Configuración del servidor:${NC}"
echo

# Pedir puerto
read -p "Puerto del servidor [$DEFAULT_PORT]: " PORT
PORT=${PORT:-$DEFAULT_PORT}

# Pedir directorio de imágenes
read -p "Ruta del directorio de imágenes [$DEFAULT_IMAGE_DIR]: " IMAGE_DIR
IMAGE_DIR=${IMAGE_DIR:-$DEFAULT_IMAGE_DIR}

# Pedir ruta del template
read -p "Ruta del template HTML [$DEFAULT_TEMPLATE_DIR]: " TEMPLATE_PATH
TEMPLATE_PATH=${TEMPLATE_PATH:-$DEFAULT_TEMPLATE_DIR}

echo
echo -e "${GREEN}Configuración:${NC}"
echo -e "  Puerto: ${YELLOW}$PORT${NC}"
echo -e "  Directorio de imágenes: ${YELLOW}$IMAGE_DIR${NC}"
echo -e "  Template HTML: ${YELLOW}$TEMPLATE_PATH${NC}"
echo

# Verificar que existan los archivos/directorios
if [ ! -d "$IMAGE_DIR" ]; then
    echo -e "${YELLOW}[WARN]${NC} El directorio $IMAGE_DIR no existe. Creándolo..."
    mkdir -p "$IMAGE_DIR"
fi

if [ ! -f "$TEMPLATE_PATH" ]; then
    echo -e "${YELLOW}[WARN]${NC} El template $TEMPLATE_PATH no existe."
    echo "Usando template por defecto: ./internal/templates/index.html"
    TEMPLATE_PATH="./internal/templates/index.html"
fi

# Hacer ejecutable el binario
chmod +x ./BINARY_NAME

echo -e "${GREEN}Iniciando servidor...${NC}"
echo -e "${CYAN}Accede a: http://localhost:$PORT${NC}"
echo

# Exportar variables de entorno para el programa
export IMAGE_DIR="$IMAGE_DIR"
export TEMPLATE_PATH="$TEMPLATE_PATH"

# Ejecutar servidor
./BINARY_NAME "$PORT"
EOF
    
    # Reemplazar BINARY_NAME con el nombre real
    sed -i "s/BINARY_NAME/$binary_name/g" "$deploy_dir/run.sh"
    chmod +x "$deploy_dir/run.sh"
}

# Función para crear script de ejecución Windows
create_run_script_windows() {
    local deploy_dir=$1
    local binary_name=$2
    
    cat > "$deploy_dir/run.bat" << 'EOF'
@echo off
echo ========================================
echo        Go Image Server - Launcher
echo ========================================
echo.

:: Valores por defecto
set DEFAULT_PORT=8080
set DEFAULT_IMAGE_DIR=.\images
set DEFAULT_TEMPLATE_DIR=.\internal\templates\index.html

echo Configuracion del servidor:
echo.

:: Pedir puerto
set /p PORT="Puerto del servidor [%DEFAULT_PORT%]: "
if "%PORT%"=="" set PORT=%DEFAULT_PORT%

:: Pedir directorio de imagenes
set /p IMAGE_DIR="Ruta del directorio de imagenes [%DEFAULT_IMAGE_DIR%]: "
if "%IMAGE_DIR%"=="" set IMAGE_DIR=%DEFAULT_IMAGE_DIR%

:: Pedir ruta del template
set /p TEMPLATE_PATH="Ruta del template HTML [%DEFAULT_TEMPLATE_DIR%]: "
if "%TEMPLATE_PATH%"=="" set TEMPLATE_PATH=%DEFAULT_TEMPLATE_DIR%

echo.
echo Configuracion:
echo   Puerto: %PORT%
echo   Directorio de imagenes: %IMAGE_DIR%
echo   Template HTML: %TEMPLATE_PATH%
echo.

:: Verificar que existan los archivos/directorios
if not exist "%IMAGE_DIR%" (
    echo [WARN] El directorio %IMAGE_DIR% no existe. Creandolo...
    mkdir "%IMAGE_DIR%"
)

if not exist "%TEMPLATE_PATH%" (
    echo [WARN] El template %TEMPLATE_PATH% no existe.
    echo Usando template por defecto: .\internal\templates\index.html
    set TEMPLATE_PATH=.\internal\templates\index.html
)

echo Iniciando servidor...
echo Accede a: http://localhost:%PORT%
echo.

:: Exportar variables de entorno
set IMAGE_DIR=%IMAGE_DIR%
set TEMPLATE_PATH=%TEMPLATE_PATH%

:: Ejecutar servidor
BINARY_NAME %PORT%
pause
EOF
    
    # Reemplazar BINARY_NAME con el nombre real
    sed "s/BINARY_NAME/$binary_name/g" "$deploy_dir/run.bat" > "$deploy_dir/run_temp.bat"
    mv "$deploy_dir/run_temp.bat" "$deploy_dir/run.bat"
}

# Función para crear README
create_readme() {
    local deploy_dir=$1
    local platform=$2
    local binary_name=$3
    
    cat > "$deploy_dir/README.md" << EOF
# Go Image Server - Paquete de Despliegue

## 📁 Contenido del paquete

- \`$binary_name\` - Binario ejecutable del servidor
- \`internal/templates/index.html\` - Template HTML del servidor
- \`images/\` - Directorio para las imágenes (ejemplos incluidos)
- \`run.sh\` o \`run.bat\` - Script de lanzamiento interactivo
- \`README.md\` - Este archivo

## 🚀 Uso Rápido

### Opción 1: Script interactivo
\`\`\`bash
# En Linux/macOS:
./run.sh

# En Windows:
run.bat
\`\`\`

### Opción 2: Ejecución directa
\`\`\`bash
# Usar configuración por defecto
./$binary_name 8080

# El servidor buscará:
# - Imágenes en: ./images/
# - Template en: ./internal/templates/index.html
\`\`\`

## ⚙️ Configuración

### Variables de entorno soportadas:
- \`IMAGE_DIR\` - Directorio de imágenes (default: ./images)
- \`TEMPLATE_PATH\` - Ruta del template HTML (default: ./internal/templates/index.html)

### Ejemplo con rutas personalizadas:
\`\`\`bash
export IMAGE_DIR="/ruta/a/mis/imagenes"
export TEMPLATE_PATH="/ruta/a/mi/template.html"
./$binary_name 8080
\`\`\`

## 📋 Requisitos

- Solo el binario ejecutable (sin dependencias adicionales)
- Directorio con imágenes PNG/JPG
- Template HTML (incluido)

## 🌐 Acceso

Una vez iniciado, accede a: \`http://localhost:[puerto]\`

---
*Generado automáticamente por el build script de Go Image Server*
EOF
}

# Compilar para diferentes plataformas
build_binary "linux" "amd64" "image-server-linux-amd64"
build_binary "linux" "arm64" "image-server-linux-arm64"
build_binary "windows" "amd64" "image-server-windows-amd64.exe"
build_binary "darwin" "amd64" "image-server-darwin-amd64"
build_binary "darwin" "arm64" "image-server-darwin-arm64"

# Crear un binario para el sistema actual sin sufijo
echo -e "${YELLOW}[INFO]${NC} Creando binario para el sistema actual..."
if go build -ldflags="-s -w" -o bin/image-server ./cmd/image-server; then
    chmod +x bin/image-server
    echo -e "${GREEN}[OK]${NC} Binario local creado: bin/image-server"
else
    echo -e "${RED}ERROR: Falló la compilación del binario local${NC}"
    exit 1
fi

echo
echo -e "${CYAN}[DEPLOY]${NC} Creando paquetes de despliegue..."

# Crear paquetes de despliegue
create_deploy_package "linux-amd64" "image-server-linux-amd64"
create_deploy_package "linux-arm64" "image-server-linux-arm64"
create_deploy_package "windows-amd64" "image-server-windows-amd64.exe"
create_deploy_package "darwin-amd64" "image-server-darwin-amd64"
create_deploy_package "darwin-arm64" "image-server-darwin-arm64"

echo
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}              BUILD COMPLETADO${NC}"
echo -e "${BLUE}================================================${NC}"
echo -e "${YELLOW}Binarios generados:${NC}"
ls -la bin/image-server-*
echo
echo -e "${YELLOW}Paquetes de despliegue:${NC}"
ls -la bin/deploy-*/
echo
echo -e "${GREEN}Para usar:${NC}"
echo -e "  1. ${YELLOW}Copia el directorio completo bin/deploy-[plataforma]/${NC}"
echo -e "  2. ${YELLOW}Ejecuta el script run.sh (Linux) o run.bat (Windows)${NC}"
echo -e "  3. ${YELLOW}Configura las rutas cuando se solicite${NC}"
echo
echo -e "${GREEN}Ejemplo:${NC}"
echo -e "  ${CYAN}scp -r bin/deploy-linux-amd64 usuario@servidor:/home/usuario/image-server${NC}"
echo -e "  ${CYAN}ssh usuario@servidor 'cd /home/usuario/image-server && ./run.sh'${NC}"
echo

# Mostrar tamaños de archivos
echo -e "${YELLOW}Tamaños de binarios:${NC}"
du -sh bin/image-server-* | sort -h
echo