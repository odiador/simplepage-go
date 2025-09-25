// Package images proporciona funcionalidades para el procesamiento
// y manejo de archivos de imagen en el servidor.
//
// Este paquete se encarga de:
// - Escanear directorios en busca de archivos de imagen válidos
// - Filtrar archivos por extensión (.png, .jpg, .jpeg)
// - Convertir imágenes a formato Base64 para visualización web
// - Proporcionar selección aleatoria de imágenes
//
// Las imágenes son convertidas a Base64 para permitir su inclusión
// directa en el HTML sin necesidad de servir archivos estáticos
// adicionales, simplificando el despliegue del servidor.
package images

import (
	"encoding/base64"
	"math/rand"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Imagen representa una imagen procesada lista para ser mostrada en la web.
// Contiene el nombre del archivo y los datos de la imagen codificados en Base64.
type Imagen struct {
	Name string // Nombre del archivo de imagen (ej: "ubuntu.png")
	Data string // Datos de la imagen codificados en Base64
}

// LoadRandomImages carga y procesa imágenes aleatorias desde un directorio específico.
//
// Esta función:
// - Escanea el directorio especificado
// - Filtra archivos por extensiones válidas usando isImageFile()
// - Selecciona aleatoriamente hasta n archivos
// - Convierte cada imagen seleccionada a formato Base64
// - Retorna una slice de estructuras Imagen listas para usar
//
// Parámetros:
//   folder: Ruta del directorio a escanear
//   n: Número máximo de imágenes a retornar
//
// Retorna:
//   []Imagen: Slice de imágenes procesadas
//   error: Error si no se puede leer el directorio
//
// La función retorna nil si no se encuentran imágenes válidas, pero no
// considera esto como un error para permitir operación con directorios vacíos.
func LoadRandomImages(folder string, n int) ([]Imagen, error) {
	// Leer el contenido del directorio
	files, err := os.ReadDir(folder)
	if err != nil {
		return nil, err
	}

	// Filtrar archivos válidos (solo imágenes, no directorios)
	validFiles := []os.DirEntry{}
	for _, f := range files {
		if !f.IsDir() && isImageFile(f.Name()) {
			validFiles = append(validFiles, f)
		}
	}

	// Si no hay archivos válidos, retornar slice vacía
	if len(validFiles) == 0 {
		return nil, nil
	}

	// Configurar generador aleatorio y mezclar archivos
	rand.Seed(time.Now().UnixNano())
	rand.Shuffle(len(validFiles), func(i, j int) {
		validFiles[i], validFiles[j] = validFiles[j], validFiles[i]
	})

	// Ajustar cantidad si es mayor a archivos disponibles
	if n > len(validFiles) {
		n = len(validFiles)
	}

	// Procesar los primeros n archivos mezclados
	var images []Imagen
	for _, file := range validFiles[:n] {
		// Leer archivo completo
		data, err := os.ReadFile(filepath.Join(folder, file.Name()))
		if err != nil {
			// Si hay error con un archivo, continuar con los demás
			continue
		}
		
		// Codificar a Base64
		encoded := base64.StdEncoding.EncodeToString(data)
		
		// Agregar imagen a la lista
		images = append(images, Imagen{
			Name: file.Name(),
			Data: encoded,
		})
	}

	return images, nil
}

// isImageFile verifica si un archivo tiene una extensión de imagen válida.
//
// Esta función auxiliar determina si un archivo es una imagen soportada
// basándose en su extensión. Las extensiones soportadas son:
// - .png (Portable Network Graphics)
// - .jpg (JPEG)
// - .jpeg (JPEG con extensión completa)
//
// Parámetros:
//   name: Nombre del archivo a verificar
//
// Retorna:
//   bool: true si el archivo tiene una extensión de imagen válida
//
// La comparación se realiza sin distinción de mayúsculas/minúsculas
// para máxima compatibilidad con diferentes sistemas operativos.
func isImageFile(name string) bool {
	ext := strings.ToLower(filepath.Ext(name))
	return ext == ".png" || ext == ".jpg" || ext == ".jpeg"
}