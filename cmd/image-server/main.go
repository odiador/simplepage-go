// Package main implementa el servidor HTTP principal para el Go Image Server.
//
// Este servidor web está diseñado para servir imágenes de distribuciones de Linux
// a través de una interfaz web moderna construida con Bootstrap. El servidor
// convierte automáticamente las imágenes a formato Base64 para su visualización
// directa en el navegador web.
//
// Uso:
//   go run main.go [puerto]
//   ./image-server [puerto]
//
// Si no se especifica puerto, el servidor usará el puerto 8000 por defecto.
//
// Variables de entorno soportadas:
//   IMAGE_DIR: Directorio donde se encuentran las imágenes (default: ./images)
//   TEMPLATE_PATH: Ruta del template HTML (default: ./internal/templates/index.html)
//
// Autores: Juan Amador - Santiago Londoño
// Curso: Computación en la nube 2025-2
package main

import (
	"log"
	"net/http"
	"os"

	"github.com/odiador/go/internal/web"
)

// main es el punto de entrada de la aplicación.
// Configura el puerto del servidor y inicia el servidor HTTP.
func main() {
	// Puerto por defecto
	port := "8000"
	
	// Si se proporciona un argumento, usarlo como puerto
	if len(os.Args) > 1 {
		port = os.Args[1]
	}

	// Mostrar información del servidor
	log.Printf("Servidor escuchando en http://localhost:%s", port)
	
	// Iniciar el servidor HTTP con el handler principal
	if err := http.ListenAndServe(":"+port, web.HomeHandler()); err != nil {
		log.Fatal("Error iniciando servidor:", err)
	}
}