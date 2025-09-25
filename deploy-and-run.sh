#!/bin/bash

# Configurar variables de entorno con rutas por defecto
export PORT=8080
export IMAGE_DIR="./images"
export TEMPLATE_PATH="./internal/templates/index.html"

cd /home/debian

# Hacer ejecutable el binario
chmod +x image-server-linux-amd64

# Ejecutar el servidor
./image-server-linux-amd64 $PORT