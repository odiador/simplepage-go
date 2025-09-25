package main

import (
	"log"
	"net/http"
	"os"

	"github.com/odiador/go/internal/web"
)

func main() {
	port := "8000"
	if len(os.Args) > 1 {
		port = os.Args[1]
	}

	log.Printf("Servidor escuchando en http://localhost:%s", port)
	if err := http.ListenAndServe(":"+port, web.HomeHandler()); err != nil {
		log.Fatal("Error iniciando servidor:", err)
	}
}