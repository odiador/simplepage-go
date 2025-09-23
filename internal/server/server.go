package server

import (
	"fmt"
	"html/template"
	"net/http"
	"path/filepath"
	"time"

	"github.com/odiador/go/internal/images"
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
	s.mux.Handle("/static/", http.StripPrefix("/static/", http.FileServer(http.Dir("web/static"))))

	return s, nil
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.mux.ServeHTTP(w, r)
}

func (s *Server) handleIndex(w http.ResponseWriter, r *http.Request) {
	tmpl := filepath.Join("internal", "templates", "index.html")
	t, err := template.ParseFiles(tmpl)
	if err != nil {
		http.Error(w, "Error al cargar template", http.StatusInternalServerError)
		return
	}

	imgs := images.GetRandomImages(s.cfg.Max)
	var imageData []map[string]string
	for _, img := range imgs {
		src, err := images.EncodeToBase64(img.Path)
		if err != nil {
			continue
		}
		imageData = append(imageData, map[string]string{"Src": src})
	}

	data := map[string]any{
		"Title": "Servidor de imágenes",
		"Images": imageData,
	}
	t.Execute(w, data)
}