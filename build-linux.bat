@echo off
echo ================================================
echo    Go Image Server - Linux Cross Compilation
echo ================================================
echo.

:: Verificar que Go esté instalado
where go >nul 2>nul
if %errorlevel% neq 0 (
    echo ERROR: Go no está instalado o no está en el PATH
    pause
    exit /b 1
)

echo [INFO] Versión de Go:
go version
echo.

:: Crear directorio de binarios si no existe
if not exist "bin" mkdir bin

echo [INFO] Limpiando builds anteriores de Linux...
del /Q bin\image-server-linux-* 2>nul
echo.

echo [INFO] Configurando compilación cruzada para Linux...
echo [INFO] Sistema origen: Windows
echo [INFO] Sistema destino: Linux (amd64)
echo.

echo [INFO] Compilando para Linux (amd64)...
set GOOS=linux
set GOARCH=amd64
set CGO_ENABLED=0
go build -ldflags="-s -w" -o bin/image-server-linux-amd64 ./cmd/image-server
if %errorlevel% neq 0 (
    echo ERROR: Falló la compilación cruzada para Linux
    echo.
    echo Posibles causas:
    echo - Dependencias CGO (resuelto con CGO_ENABLED=0)
    echo - Ruta incorrecta al código fuente
    echo - Problemas con go.mod
    pause
    exit /b 1
)

echo [OK] Compilación cruzada exitosa!
echo.

echo ================================================
echo         COMPILACIÓN CRUZADA COMPLETADA
echo ================================================
echo.
echo Binario Linux generado: bin\image-server-linux-amd64
echo.
echo Para transferir a Linux, puedes usar:
echo   - SCP: scp bin\image-server-linux-amd64 usuario@servidor:/path/
echo   - SFTP o herramientas como WinSCP
echo   - USB o red compartida
echo.
echo Para ejecutar en Linux:
echo   1. chmod +x image-server-linux-amd64
echo   2. ./image-server-linux-amd64 [puerto]
echo.
echo Ejemplo en Linux: ./image-server-linux-amd64 8080
echo.

:: Mostrar información del archivo generado
if exist "bin\image-server-linux-amd64" (
    echo Información del archivo:
    dir bin\image-server-linux-amd64
) else (
    echo ERROR: No se encontró el archivo generado
)

echo.
pause