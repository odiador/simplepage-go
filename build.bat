@echo off
echo ================================================
echo           Go Image Server - Build Script
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

echo [INFO] Limpiando builds anteriores...
del /Q bin\*.exe 2>nul
del /Q bin\image-server 2>nul
echo.

echo [INFO] Compilando para Windows (amd64)...
set GOOS=windows
set GOARCH=amd64
go build -ldflags="-s -w" -o bin/image-server-windows-amd64.exe ./cmd/image-server
if %errorlevel% neq 0 (
    echo ERROR: Falló la compilación para Windows
    pause
    exit /b 1
)
echo [OK] Binario Windows creado: bin/image-server-windows-amd64.exe

echo [INFO] Compilando para Linux (amd64)...
set GOOS=linux
set GOARCH=amd64
go build -ldflags="-s -w" -o bin/image-server-linux-amd64 ./cmd/image-server
if %errorlevel% neq 0 (
    echo ERROR: Falló la compilación para Linux
    pause
    exit /b 1
)
echo [OK] Binario Linux creado: bin/image-server-linux-amd64

echo [INFO] Compilando para macOS (amd64)...
set GOOS=darwin
set GOARCH=amd64
go build -ldflags="-s -w" -o bin/image-server-darwin-amd64 ./cmd/image-server
if %errorlevel% neq 0 (
    echo ERROR: Falló la compilación para macOS
    pause
    exit /b 1
)
echo [OK] Binario macOS creado: bin/image-server-darwin-amd64

echo [INFO] Compilando para macOS (arm64 - Apple Silicon)...
set GOOS=darwin
set GOARCH=arm64
go build -ldflags="-s -w" -o bin/image-server-darwin-arm64 ./cmd/image-server
if %errorlevel% neq 0 (
    echo ERROR: Falló la compilación para macOS ARM64
    pause
    exit /b 1
)
echo [OK] Binario macOS ARM64 creado: bin/image-server-darwin-arm64

echo.
echo ================================================
echo                BUILD COMPLETADO
echo ================================================
echo Binarios generados:
dir /B bin\*
echo.
echo Para ejecutar en Windows: .\bin\image-server-windows-amd64.exe [puerto]
echo Para ejecutar en Linux:   ./bin/image-server-linux-amd64 [puerto]
echo Para ejecutar en macOS:   ./bin/image-server-darwin-amd64 [puerto]
echo.
echo Ejemplo: .\bin\image-server-windows-amd64.exe 8080
echo.
pause