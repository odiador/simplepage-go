package main

import (
	"context"
	"flag"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/odiador/go/internal/server"
)

func main() {
	// Flags with env support
	portDefault := "8000"
	if p := os.Getenv("PORT"); p != "" {
		portDefault = p
	}
	port := flag.String("port", portDefault, "Puerto para el servidor HTTP")

	imgDirDefault := "./images"
	if d := os.Getenv("IMGDIR"); d != "" {
		imgDirDefault = d
	}
	imgDir := flag.String("imgdir", imgDirDefault, "Directorio de imágenes")

	maxDefault := 10
	if m := os.Getenv("MAX"); m != "" {
		if parsed, err := strconv.Atoi(m); err == nil {
			maxDefault = parsed
		}
	}
	max := flag.Int("max", maxDefault, "Máximo número de imágenes a mostrar")

	thumbWidthDefault := 200
	if tw := os.Getenv("THUMB_WIDTH"); tw != "" {
		if parsed, err := strconv.Atoi(tw); err == nil {
			thumbWidthDefault = parsed
		}
	}
	thumbWidth := flag.Int("thumb-width", thumbWidthDefault, "Ancho de los thumbnails")

	cacheTTLDefault := 5 * time.Minute
	if c := os.Getenv("CACHE_TTL"); c != "" {
		if parsed, err := time.ParseDuration(c); err == nil {
			cacheTTLDefault = parsed
		}
	}
	cacheTTL := flag.Duration("cache-ttl", cacheTTLDefault, "TTL del cache")

	flag.Parse()

	// Validate imgDir
	if _, err := os.Stat(*imgDir); os.IsNotExist(err) {
		log.Fatalf("Directorio de imágenes no existe: %s", *imgDir)
	}

	// Config
	cfg := server.Config{
		ImgDir:     *imgDir,
		Max:        *max,
		ThumbWidth: *thumbWidth,
		CacheTTL:   *cacheTTL,
	}

	// Crear router/servidor
	srv, err := server.New(cfg)
	if err != nil {
		log.Fatalf("Error initializing server: %v", err)
	}

	httpServer := &http.Server{
		Addr:         ":" + *port,
		Handler:      srv,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	// Canal para señales
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)

	// Lanzar servidor
	go func() {
		log.Printf("Servidor escuchando en http://localhost:%s", *port)
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Error en servidor: %v", err)
		}
	}()

	// Esperar señal
	<-stop
	log.Println("Apagando servidor...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := httpServer.Shutdown(ctx); err != nil {
		log.Fatalf("Error al apagar: %v", err)
	}
	log.Println("Servidor detenido correctamente")
}