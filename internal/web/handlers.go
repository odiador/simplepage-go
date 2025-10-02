// Package web contiene los handlers HTTP y la lógica de presentación
// para el servidor de imágenes.
//
// Este paquete maneja las peticiones HTTP entrantes, interactúa con
// el sistema de procesamiento de imágenes y renderiza las respuestas
// HTML utilizando templates de Go.
//
// La configuración se realiza a través de variables de entorno para
// proporcionar flexibilidad en el despliegue.
package web

import (
	"html/template"
	"net/http"
	"os"

	"github.com/odiador/simplepage-go/internal/images"
)

// PageData representa la estructura de datos que se pasa al template HTML.
// Contiene toda la información necesaria para renderizar la página principal.
type PageData struct {
	Title  string           // Título de la página web
	Host   string           // Nombre del host/servidor
	Images []images.Imagen  // Lista de imágenes a mostrar
}

// HomeHandler retorna un http.HandlerFunc que maneja las peticiones
// a la página principal del servidor de imágenes.
//
// Este handler:
// - Lee la configuración desde variables de entorno
// - Obtiene el hostname del sistema
// - Carga imágenes aleatorias desde el directorio configurado
// - Renderiza el template HTML con los datos obtenidos
//
// Variables de entorno utilizadas:
//   IMAGE_DIR: Directorio de imágenes (default: "images")
//   TEMPLATE_PATH: Ruta del template HTML (default: "internal/templates/index.html")
//
// Retorna un error HTTP 500 si:
// - No se pueden cargar las imágenes del directorio
// - No se puede parsear o ejecutar el template HTML
func HomeHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// Obtener el hostname del sistema
		host, _ := os.Hostname()

		// Obtener rutas desde variables de entorno o usar defaults
		imageDir := os.Getenv("IMAGE_DIR")
		if imageDir == "" {
			imageDir = "images"
		}

		templatePath := os.Getenv("TEMPLATE_PATH")
		if templatePath == "" {
			templatePath = "internal/templates/index.html"
		}

		// Cargar 4 imágenes aleatorias del directorio
		imgs, err := images.LoadRandomImages(imageDir, 4)
		if err != nil {
			http.Error(w, "Error cargando imágenes: "+err.Error(), http.StatusInternalServerError)
			return
		}

		// Preparar los datos para el template
		data := PageData{
			Title:  "Servidor de imágenes",
			Host:   host,
			Images: imgs,
		}

		// Parsear el template HTML
		tmpl, err := template.ParseFiles(templatePath)
		if err != nil {
			http.Error(w, "Error cargando template: "+err.Error(), http.StatusInternalServerError)
			return
		}

		// Ejecutar el template con los datos y enviar la respuesta
		tmpl.Execute(w, data)
	}
}