#
# Go Image Server - Makefile
# ==========================
#
# Este Makefile automatiza las tareas comunes de desarrollo y despliegue
# del servidor de imágenes. Proporciona comandos simples para compilar,
# probar, validar y dockerizar la aplicación.
#
# Comandos disponibles:
#   make build         - Compila el binario para el sistema actual
#   make test          - Ejecuta las pruebas del proyecto
#   make lint          - Ejecuta análisis estático de código
#   make docker-build  - Construye imagen Docker
#
# Uso:
#   make [comando]
#
# Autores: Juan Amador - Santiago Londoño
# Curso: Computación en la nube 2025-2
#

.PHONY: build test lint docker-build

build:
	go build -o bin/image-server ./cmd/image-server

test:
	go test ./...

lint:
	golangci-lint run

docker-build:
	docker build -t image-server .