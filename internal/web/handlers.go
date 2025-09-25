package web

import (
	"html/template"
	"net/http"
	"os"

	"github.com/odiador/go/internal/images"
)

// Datos que pasamos al template
type PageData struct {
	Title  string
	Host   string
	Images []images.Imagen
}

func HomeHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
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

		// Cargar 4 imágenes aleatorias
		imgs, err := images.LoadRandomImages(imageDir, 4)
		if err != nil {
			http.Error(w, "Error cargando imágenes: "+err.Error(), http.StatusInternalServerError)
			return
		}

		data := PageData{
			Title:  "Servidor de imágenes",
			Host:   host,
			Images: imgs,
		}

		tmpl, err := template.ParseFiles(templatePath)
		if err != nil {
			http.Error(w, "Error cargando template: "+err.Error(), http.StatusInternalServerError)
			return
		}

		tmpl.Execute(w, data)
	}
}