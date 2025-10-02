@echo off
setlocal enabledelayedexpansion

REM
REM Go Image Server - Script de Build Multiplataforma
REM =================================================
REM
REM Este script automatiza el proceso de compilación del servidor de imágenes
REM para múltiples plataformas y arquitecturas. Genera binarios optimizados
REM y crea paquetes completos de despliegue listos para producción.
REM
REM Características:
REM - Compilación cruzada para Linux, Windows, macOS
REM - Optimización de binarios con ldflags para reducir tamaño
REM - Creación automática de paquetes de despliegue
REM - Scripts de ejecución personalizados por plataforma
REM - Documentación automática en cada paquete
REM
REM Uso:
REM   build.bat
REM
REM Requisitos:
REM   - Go 1.25 o superior instalado
REM   - Permisos de escritura en directorio bin\
REM
REM Salida:
REM   bin\
REM   ├── image-server-*           # Binarios por plataforma
REM   └── deploy-*\                # Paquetes completos de despliegue
REM
REM Autores: Juan Amador - Santiago Londoño
REM Curso: Computación en la nube 2025-2
REM

echo ================================================
echo          Go Image Server - Build Script
echo ================================================
echo.

:: Verificar que Go esté instalado
where go >nul 2>nul
if %errorlevel% neq 0 (
    echo ERROR: Go no esta instalado o no esta en el PATH
    pause
    exit /b 1
)

echo [INFO] Version de Go:
go version
echo.

:: Crear directorio de binarios si no existe
if not exist "bin" mkdir bin

echo [INFO] Limpiando builds anteriores...
del /Q bin\image-server-* 2>nul
del /Q bin\image-server 2>nul
rd /S /Q bin\deploy-linux-amd64 2>nul
rd /S /Q bin\deploy-linux-arm64 2>nul
rd /S /Q bin\deploy-windows-amd64 2>nul
rd /S /Q bin\deploy-darwin-amd64 2>nul
rd /S /Q bin\deploy-darwin-arm64 2>nul
echo.

echo [INFO] Compilando para Windows (amd64)...
set GOOS=windows
set GOARCH=amd64
go build -ldflags="-s -w" -o bin/image-server-windows-amd64.exe ./cmd/image-server
if %errorlevel% neq 0 (
    echo ERROR: Fallo la compilacion para Windows
    pause
    exit /b 1
)
echo [OK] Binario Windows creado: bin/image-server-windows-amd64.exe

echo [INFO] Compilando para Linux (amd64)...
set GOOS=linux
set GOARCH=amd64
go build -ldflags="-s -w" -o bin/image-server-linux-amd64 ./cmd/image-server
if %errorlevel% neq 0 (
    echo ERROR: Fallo la compilacion para Linux amd64
    pause
    exit /b 1
)
echo [OK] Binario Linux amd64 creado: bin/image-server-linux-amd64

echo [INFO] Compilando para Linux (arm64)...
set GOOS=linux
set GOARCH=arm64
go build -ldflags="-s -w" -o bin/image-server-linux-arm64 ./cmd/image-server
if %errorlevel% neq 0 (
    echo ERROR: Fallo la compilacion para Linux arm64
    pause
    exit /b 1
)
echo [OK] Binario Linux arm64 creado: bin/image-server-linux-arm64

echo [INFO] Compilando para macOS (amd64)...
set GOOS=darwin
set GOARCH=amd64
go build -ldflags="-s -w" -o bin/image-server-darwin-amd64 ./cmd/image-server
if %errorlevel% neq 0 (
    echo ERROR: Fallo la compilacion para macOS amd64
    pause
    exit /b 1
)
echo [OK] Binario macOS amd64 creado: bin/image-server-darwin-amd64

echo [INFO] Compilando para macOS (arm64 - Apple Silicon)...
set GOOS=darwin
set GOARCH=arm64
go build -ldflags="-s -w" -o bin/image-server-darwin-arm64 ./cmd/image-server
if %errorlevel% neq 0 (
    echo ERROR: Fallo la compilacion para macOS ARM64
    pause
    exit /b 1
)
echo [OK] Binario macOS ARM64 creado: bin/image-server-darwin-arm64

echo.
echo [DEPLOY] Creando paquetes de despliegue...
echo.

:: Crear paquete para Linux amd64
call :create_deploy_package "linux-amd64" "image-server-linux-amd64"

:: Crear paquete para Linux arm64
call :create_deploy_package "linux-arm64" "image-server-linux-arm64"

:: Crear paquete para Windows amd64
call :create_deploy_package "windows-amd64" "image-server-windows-amd64.exe"

:: Crear paquete para macOS amd64
call :create_deploy_package "darwin-amd64" "image-server-darwin-amd64"

:: Crear paquete para macOS arm64
call :create_deploy_package "darwin-arm64" "image-server-darwin-arm64"

echo.
echo ================================================
echo               BUILD COMPLETADO
echo ================================================
echo Binarios generados:
dir /B bin\image-server-*
echo.
echo Paquetes de despliegue:
dir /B bin\deploy-*
echo.
echo Para usar:
echo   1. Copia el directorio completo bin\deploy-[plataforma]\
echo   2. Ejecuta el script run.sh (Linux) o run.bat (Windows)
echo   3. Configura las rutas cuando se solicite
echo.
echo Ejemplo:
echo   cd bin\deploy-windows-amd64
echo   run.bat
echo.
pause
exit /b 0

:: ============================================
:: Función para crear paquete de despliegue
:: ============================================
:create_deploy_package
set platform=%~1
set binary_name=%~2
set deploy_dir=bin\deploy-%platform%

echo [DEPLOY] Creando paquete de despliegue para %platform%...

:: Crear estructura de directorios
if not exist "%deploy_dir%" mkdir "%deploy_dir%"
if not exist "%deploy_dir%\internal\templates" mkdir "%deploy_dir%\internal\templates"
if not exist "%deploy_dir%\images" mkdir "%deploy_dir%\images"
if not exist "%deploy_dir%\scripts" mkdir "%deploy_dir%\scripts"

:: Copiar binario
copy "bin\%binary_name%" "%deploy_dir%\" >nul

:: Copiar template
copy "internal\templates\index.html" "%deploy_dir%\internal\templates\" >nul

:: Copiar imágenes de ejemplo
if exist "images\*.*" (
    copy "images\*.*" "%deploy_dir%\images\" >nul 2>nul
)

:: Crear script de ejecución según plataforma
echo %platform% | findstr /i "linux" >nul
if %errorlevel% equ 0 (
    call :create_run_script_linux "%deploy_dir%" "%binary_name%"
)

echo %platform% | findstr /i "windows" >nul
if %errorlevel% equ 0 (
    call :create_run_script_windows "%deploy_dir%" "%binary_name%"
)

echo %platform% | findstr /i "darwin" >nul
if %errorlevel% equ 0 (
    call :create_run_script_macos "%deploy_dir%" "%binary_name%"
)

:: Crear README
call :create_readme "%deploy_dir%" "%platform%" "%binary_name%"

echo [OK] Paquete creado: %deploy_dir%
goto :eof

:: ============================================
:: Función para crear script de Linux
:: ============================================
:create_run_script_linux
set deploy_dir=%~1
set binary_name=%~2

(
echo #!/bin/bash
echo.
echo # Colores
echo GREEN='\033[0;32m'
echo YELLOW='\033[1;33m'
echo CYAN='\033[0;36m'
echo NC='\033[0m'
echo.
echo echo -e "${CYAN}========================================${NC}"
echo echo -e "${CYAN}       Go Image Server - Launcher${NC}"
echo echo -e "${CYAN}========================================${NC}"
echo echo
echo.
echo # Valores por defecto
echo DEFAULT_PORT="8080"
echo DEFAULT_IMAGE_DIR="./images"
echo DEFAULT_TEMPLATE_DIR="./internal/templates/index.html"
echo.
echo echo -e "${YELLOW}Configuracion del servidor:${NC}"
echo echo
echo.
echo # Pedir puerto
echo read -p "Puerto del servidor [$DEFAULT_PORT]: " PORT
echo PORT=${PORT:-$DEFAULT_PORT}
echo.
echo # Pedir directorio de imagenes
echo read -p "Ruta del directorio de imagenes [$DEFAULT_IMAGE_DIR]: " IMAGE_DIR
echo IMAGE_DIR=${IMAGE_DIR:-$DEFAULT_IMAGE_DIR}
echo.
echo # Pedir ruta del template
echo read -p "Ruta del template HTML [$DEFAULT_TEMPLATE_DIR]: " TEMPLATE_PATH
echo TEMPLATE_PATH=${TEMPLATE_PATH:-$DEFAULT_TEMPLATE_DIR}
echo.
echo echo
echo echo -e "${GREEN}Configuracion:${NC}"
echo echo -e "  Puerto: ${YELLOW}$PORT${NC}"
echo echo -e "  Directorio de imagenes: ${YELLOW}$IMAGE_DIR${NC}"
echo echo -e "  Template HTML: ${YELLOW}$TEMPLATE_PATH${NC}"
echo echo
echo.
echo # Verificar que existan los archivos/directorios
echo if [ ! -d "$IMAGE_DIR" ]; then
echo     echo -e "${YELLOW}[WARN]${NC} El directorio $IMAGE_DIR no existe. Creandolo..."
echo     mkdir -p "$IMAGE_DIR"
echo fi
echo.
echo if [ ! -f "$TEMPLATE_PATH" ]; then
echo     echo -e "${YELLOW}[WARN]${NC} El template $TEMPLATE_PATH no existe."
echo     echo "Usando template por defecto: ./internal/templates/index.html"
echo     TEMPLATE_PATH="./internal/templates/index.html"
echo fi
echo.
echo # Hacer ejecutable el binario
echo chmod +x ./%binary_name%
echo.
echo echo -e "${GREEN}Iniciando servidor...${NC}"
echo echo -e "${CYAN}Accede a: http://localhost:$PORT${NC}"
echo echo
echo.
echo # Exportar variables de entorno para el programa
echo export IMAGE_DIR="$IMAGE_DIR"
echo export TEMPLATE_PATH="$TEMPLATE_PATH"
echo.
echo # Ejecutar servidor
echo ./%binary_name% "$PORT"
) > "%deploy_dir%\run.sh"

goto :eof

:: ============================================
:: Función para crear script de Windows
:: ============================================
:create_run_script_windows
set deploy_dir=%~1
set binary_name=%~2

(
echo @echo off
echo echo ========================================
echo echo        Go Image Server - Launcher
echo echo ========================================
echo echo.
echo.
echo :: Valores por defecto
echo set DEFAULT_PORT=8080
echo set DEFAULT_IMAGE_DIR=.\images
echo set DEFAULT_TEMPLATE_DIR=.\internal\templates\index.html
echo.
echo echo Configuracion del servidor:
echo echo.
echo.
echo :: Pedir puerto
echo set /p PORT="Puerto del servidor [%%DEFAULT_PORT%%]: "
echo if "%%PORT%%"=="" set PORT=%%DEFAULT_PORT%%
echo.
echo :: Pedir directorio de imagenes
echo set /p IMAGE_DIR="Ruta del directorio de imagenes [%%DEFAULT_IMAGE_DIR%%]: "
echo if "%%IMAGE_DIR%%"=="" set IMAGE_DIR=%%DEFAULT_IMAGE_DIR%%
echo.
echo :: Pedir ruta del template
echo set /p TEMPLATE_PATH="Ruta del template HTML [%%DEFAULT_TEMPLATE_DIR%%]: "
echo if "%%TEMPLATE_PATH%%"=="" set TEMPLATE_PATH=%%DEFAULT_TEMPLATE_DIR%%
echo.
echo echo.
echo echo Configuracion:
echo echo   Puerto: %%PORT%%
echo echo   Directorio de imagenes: %%IMAGE_DIR%%
echo echo   Template HTML: %%TEMPLATE_PATH%%
echo echo.
echo.
echo :: Verificar que existan los archivos/directorios
echo if not exist "%%IMAGE_DIR%%" ^(
echo     echo [WARN] El directorio %%IMAGE_DIR%% no existe. Creandolo...
echo     mkdir "%%IMAGE_DIR%%"
echo ^)
echo.
echo if not exist "%%TEMPLATE_PATH%%" ^(
echo     echo [WARN] El template %%TEMPLATE_PATH%% no existe.
echo     echo Usando template por defecto: .\internal\templates\index.html
echo     set TEMPLATE_PATH=.\internal\templates\index.html
echo ^)
echo.
echo echo Iniciando servidor...
echo echo Accede a: http://localhost:%%PORT%%
echo echo.
echo.
echo :: Exportar variables de entorno
echo set IMAGE_DIR=%%IMAGE_DIR%%
echo set TEMPLATE_PATH=%%TEMPLATE_PATH%%
echo.
echo :: Ejecutar servidor
echo %binary_name% %%PORT%%
echo pause
) > "%deploy_dir%\run.bat"

goto :eof

:: ============================================
:: Función para crear script de macOS
:: ============================================
:create_run_script_macos
set deploy_dir=%~1
set binary_name=%~2

(
echo #!/bin/bash
echo.
echo # Colores
echo GREEN='\033[0;32m'
echo YELLOW='\033[1;33m'
echo CYAN='\033[0;36m'
echo NC='\033[0m'
echo.
echo echo -e "${CYAN}========================================${NC}"
echo echo -e "${CYAN}       Go Image Server - Launcher${NC}"
echo echo -e "${CYAN}========================================${NC}"
echo echo
echo.
echo # Valores por defecto
echo DEFAULT_PORT="8080"
echo DEFAULT_IMAGE_DIR="./images"
echo DEFAULT_TEMPLATE_DIR="./internal/templates/index.html"
echo.
echo echo -e "${YELLOW}Configuracion del servidor:${NC}"
echo echo
echo.
echo # Pedir puerto
echo read -p "Puerto del servidor [$DEFAULT_PORT]: " PORT
echo PORT=${PORT:-$DEFAULT_PORT}
echo.
echo # Pedir directorio de imagenes
echo read -p "Ruta del directorio de imagenes [$DEFAULT_IMAGE_DIR]: " IMAGE_DIR
echo IMAGE_DIR=${IMAGE_DIR:-$DEFAULT_IMAGE_DIR}
echo.
echo # Pedir ruta del template
echo read -p "Ruta del template HTML [$DEFAULT_TEMPLATE_DIR]: " TEMPLATE_PATH
echo TEMPLATE_PATH=${TEMPLATE_PATH:-$DEFAULT_TEMPLATE_DIR}
echo.
echo echo
echo echo -e "${GREEN}Configuracion:${NC}"
echo echo -e "  Puerto: ${YELLOW}$PORT${NC}"
echo echo -e "  Directorio de imagenes: ${YELLOW}$IMAGE_DIR${NC}"
echo echo -e "  Template HTML: ${YELLOW}$TEMPLATE_PATH${NC}"
echo echo
echo.
echo # Verificar que existan los archivos/directorios
echo if [ ! -d "$IMAGE_DIR" ]; then
echo     echo -e "${YELLOW}[WARN]${NC} El directorio $IMAGE_DIR no existe. Creandolo..."
echo     mkdir -p "$IMAGE_DIR"
echo fi
echo.
echo if [ ! -f "$TEMPLATE_PATH" ]; then
echo     echo -e "${YELLOW}[WARN]${NC} El template $TEMPLATE_PATH no existe."
echo     echo "Usando template por defecto: ./internal/templates/index.html"
echo     TEMPLATE_PATH="./internal/templates/index.html"
echo fi
echo.
echo # Hacer ejecutable el binario
echo chmod +x ./%binary_name%
echo.
echo echo -e "${GREEN}Iniciando servidor...${NC}"
echo echo -e "${CYAN}Accede a: http://localhost:$PORT${NC}"
echo echo
echo.
echo # Exportar variables de entorno para el programa
echo export IMAGE_DIR="$IMAGE_DIR"
echo export TEMPLATE_PATH="$TEMPLATE_PATH"
echo.
echo # Ejecutar servidor
echo ./%binary_name% "$PORT"
) > "%deploy_dir%\run.sh"

goto :eof

:: ============================================
:: Función para crear README
:: ============================================
:create_readme
set deploy_dir=%~1
set platform=%~2
set binary_name=%~3

(
echo # Go Image Server - Paquete de Despliegue
echo.
echo ## 📁 Contenido del paquete
echo.
echo - `%binary_name%` - Binario ejecutable del servidor
echo - `internal/templates/index.html` - Template HTML del servidor
echo - `images/` - Directorio para las imagenes ^(ejemplos incluidos^)
echo - `run.sh` o `run.bat` - Script de lanzamiento interactivo
echo - `README.md` - Este archivo
echo.
echo ## 🚀 Uso Rapido
echo.
echo ### Opcion 1: Script interactivo
echo ```bash
echo # En Linux/macOS:
echo ./run.sh
echo.
echo # En Windows:
echo run.bat
echo ```
echo.
echo ### Opcion 2: Ejecucion directa
echo ```bash
echo # Usar configuracion por defecto
echo ./%binary_name% 8080
echo.
echo # El servidor buscara:
echo # - Imagenes en: ./images/
echo # - Template en: ./internal/templates/index.html
echo ```
echo.
echo ## ⚙️ Configuracion
echo.
echo ### Variables de entorno soportadas:
echo - `IMAGE_DIR` - Directorio de imagenes ^(default: ./images^)
echo - `TEMPLATE_PATH` - Ruta del template HTML ^(default: ./internal/templates/index.html^)
echo.
echo ### Ejemplo con rutas personalizadas:
echo ```bash
echo export IMAGE_DIR="/ruta/a/mis/imagenes"
echo export TEMPLATE_PATH="/ruta/a/mi/template.html"
echo ./%binary_name% 8080
echo ```
echo.
echo ## 📋 Requisitos
echo.
echo - Solo el binario ejecutable ^(sin dependencias adicionales^)
echo - Directorio con imagenes PNG/JPG
echo - Template HTML ^(incluido^)
echo.
echo ## 🌐 Acceso
echo.
echo Una vez iniciado, accede a: `http://localhost:[puerto]`
echo.
echo ---
echo *Generado automaticamente por el build script de Go Image Server*
) > "%deploy_dir%\README.md"

goto :eof