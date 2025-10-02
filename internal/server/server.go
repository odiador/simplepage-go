package server

import (
	"fmt"
	"html/template"
	"log/slog"
	"net/http"
	"time"

	"github.com/odiador/simplepage-go/internal/images"
	"github.com/odiador/simplepage-go/internal/templates"
)

type Config struct {
	ImgDir     string
	Max        int
	ThumbWidth int
	CacheTTL   time.Duration
}

type Server struct {
	mux *http.ServeMux
	cfg Config
}

func New(cfg Config) (*Server, error) {
	s := &Server{
		mux: http.NewServeMux(),
		cfg: cfg,
	}

	_, err := images.ScanImages(cfg.ImgDir)
	if err != nil {
		return nil, fmt.Errorf("error scanning images: %w", err)
	}

	// Rutas
	s.mux.HandleFunc("/", s.handleIndex)

	return s, nil
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.mux.ServeHTTP(w, r)
}

func (s *Server) handleIndex(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate")
	w.Header().Set("Pragma", "no-cache")
	w.Header().Set("Expires", "0")

	slog.Info("🌐 Processing index request", "max_images", s.cfg.Max)

	imgs := images.GetRandomImages(s.cfg.Max)
	slog.Info("🎲 Random images selected", "count", len(imgs), "files", func() []string {
		var names []string
		for _, img := range imgs {
			names = append(names, img.Name)
		}
		return names
	}())

	var imageData []map[string]any
	for i, img := range imgs {
		slog.Info("🖼️  Processing image", "index", i+1, "file", img.Name, "path", img.Path)
		src, err := images.EncodeToBase64(img.Path)
		if err != nil {
			slog.Error("❌ Failed to encode image to Base64, skipping", "file", img.Name, "error", err)
			continue
		}
		imageData = append(imageData, map[string]any{
			"Src":  template.HTML(src), // Marcar como HTML seguro
			"Name": img.Name,
		})
		slog.Info("✅ Image processed successfully", "file", img.Name, "base64Length", len(src))
	}

	slog.Info("🚀 Serving images to client", "totalImages", len(imageData))

	data := map[string]any{
		"Title":  "Servidor de imágenes",
		"Images": imageData,
	}

	err := templates.Index.Execute(w, data)
	if err != nil {
		slog.Error("Failed to execute template", "error", err)
		http.Error(w, "Error al renderizar la página", http.StatusInternalServerError)
	}
}