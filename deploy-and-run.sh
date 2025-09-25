#!/bin/bash

#
# Go Image Server - Script de Despliegue Automático
# =================================================
#
# Este script automatiza el proceso de despliegue y ejecución del servidor
# de imágenes en sistemas Linux. Configura automáticamente las variables
# de entorno, permisos y ejecuta el servidor con la configuración óptima.
#
# Funcionalidades:
# - Configuración automática de variables de entorno
# - Establecimiento de permisos ejecutables
# - Uso de rutas relativas para máxima portabilidad
# - Configuración por defecto lista para producción
#
# Variables de entorno configuradas:
#   PORT=8080                                    # Puerto del servidor
#   IMAGE_DIR="./images"                         # Directorio de imágenes
#   TEMPLATE_PATH="./internal/templates/index.html" # Template HTML
#
# Requisitos:
#   - Binario image-server-linux-amd64 en el directorio actual
#   - Carpeta images/ con archivos de imagen (.png, .jpg, .jpeg)
#   - Carpeta internal/templates/ con index.html
#
# Uso:
#   ./deploy-and-run.sh
#
# El servidor estará disponible en http://localhost:8080
#
# Autores: Juan Amador - Santiago Londoño
# Curso: Computación en la nube 2025-2
#

# Configurar variables de entorno con rutas por defecto
export PORT=8080
export IMAGE_DIR="./images"
export TEMPLATE_PATH="./internal/templates/index.html"

cd /home/debian

# Hacer ejecutable el binario
chmod +x image-server-linux-amd64

# Ejecutar el servidor
./image-server-linux-amd64 $PORT