# Hoja de ruta — Servidor de imágenes en Go

Basada en las especificaciones del documento subido.

A continuación tienes un plan paso a paso (ordenado y con buenas prácticas de Go) para construir la aplicación que se ve en la imagen. Cada paso indica qué hacer y por qué.

## 0) Requisitos previos rápidos

Go ≥ 1.25.1 (ya lo tienes).

git, Docker (opcional), editor (VSCode / GoLand).

Familiaridad mínima con html/template, net/http, go:embed, y manejo de concurrencia (context, sync).

## 1) Inicializar repositorio y módulos

Crear repo y módulo:

```bash
git init
go mod init github.com/<tu_usuario>/image-server
go mod tidy
```

Añadir .gitignore, Makefile (targets: build, docker-build, test, lint).

**Por qué:** módulo limpio, control de versiones y tareas automatizadas.

## 2) Estructura de proyecto recomendada

```
/cmd/image-server/main.go
/internal/server      // handlers, server bootstrap
/internal/images      // lógica de indexado, selección y cache de imágenes
/internal/storage     // thumbnailing, detección de tipo
/web/templates/*.html // templates html (html/template)
/web/static/*         // css, js (Bootstrap via CDN o local)
/configs/config.yaml  // opcional
/images               // carpeta configurable con .jpg/.jpeg/.png
/Dockerfile
/Makefile
```

**Por qué:** separación de responsabilidades facilita pruebas y mantenimiento.

## 3) Configuración y flags

Exponer parámetros por flags y variables de entorno:

- -port (p.ej. 8000)
- -imgdir (carpeta con imágenes)
- -max (máx imágenes a mostrar)
- -thumb-width (si creas thumbnails)
- -cache-ttl

Usa flag estándar o spf13/pflag si quieres compatibilidad POSIX.

Mejores prácticas: valores por flags + env vars, valida al inicio, fall-fast si carpetas no existen.

## 4) Servidor HTTP y bootstrap

Implementa main que:

- parsea flags / env
- inicializa logger estructurado (ej. zap o zerolog)
- carga índice de imágenes (ver paso 5)
- crea http.Server con ReadTimeout, WriteTimeout, IdleTimeout
- registra endpoints: / (página), /healthz, /ready, /metrics (opcional Prometheus)
- maneja graceful shutdown con context y signal.Notify.

Usa html/template para renderizar (nunca text/template para HTML).

**Por qué:** robustez, observabilidad y cierre correcto en producción.

## 5) Indexado de imágenes (solo extensiones permitidas)

Implementa función ScanImages(dir string) ([]ImageMeta, error) que:

- lista archivos en dir
- filtra por extensión .png, .jpg, .jpeg y valida tipo real mediante net/http.DetectContentType o image.DecodeConfig (evita confiar solo en la extensión)
- ignora otros tipos (es requisito).

Mantén un índice en memoria ([]ImageMeta) protegido con sync.RWMutex.

Opcional: usar fsnotify para refrescar índice cuando cambian archivos o refresco periódico con TTL.

**Por qué:** cumplir requisito de ignorar tipos no permitidos y performance (no escanear disco en cada request).

## 6) Selección aleatoria sin repeticiones

Para cada request: rand.Shuffle sobre el slice de metadatos y tomar los N primeros (esto evita repeticiones en la misma vista).

Inicializa RNG con rand.Seed(time.Now().UnixNano()) en main.

Si quieres criptográficamente aleatorio (no necesario aquí), usar crypto/rand.

**Por qué:** garantiza que no haya imágenes repetidas en la página vista por el usuario.

## 7) Generación de Base64 (al crear la página)

Requisito: las imágenes van a llegar codificadas en Base64 al momento de crear la página.

Opciones:

- Simple (rápido): leer cada fichero seleccionado, io.ReadAll, base64.StdEncoding.EncodeToString, inyectar en template como data:image/jpeg;base64,....
- Producción (recomendado): generar thumbnails (p.ej. con github.com/disintegration/imaging) para reducir tamaño antes de base64; codificar ese buffer.

Implementa función func EncodeThumbnailToBase64(path string, width int) (string, error).

Mejores prácticas: no cargar toda la carpeta en memoria, limitar tamaño del thumbnail, reuse buffers.

## 8) Templates y Bootstrap (UI)

Usa html/template y pasar datos (struct con Filename, DataURL, Alt, Title).

Incluye Bootstrap 5.3 vía CDN en <head> o con fallback local (si necesitas offline).

Diseño responsive: grid de tarjetas, img con width/max-width controlado por CSS y clases Bootstrap (card, row, col-md-6, etc.).

Asegura alt para accesibilidad y evita inyectar HTML sin sanitizar.

**Por qué:** la plantilla controla apariencia y evita XSS.

## 9) Manejo de activos y go:embed

Para distribuir un solo binario usa //go:embed web/templates web/static y servir templates/estáticos embebidos.

Alternativa: servir web/static por http.FileServer y templates desde disco en desarrollo.

**Por qué:** despliegue más sencillo y reproducible.

## 10) Cache y rendimiento

Precomputar y cachear base64-thumbnails en memoria con TTL (map + timestamp). Evitar recodificar en cada request.

Limitar número de imágenes por página (max) y tamaño máximo del thumbnail.

Para muchos ficheros, usar LRU (grupo de caching) para no llenar memoria.

Añadir headers HTTP: Cache-Control si tiene sentido.

**Por qué:** mejorar latencia y reducir CPU/memory.

## 11) Concurrencia, timeouts y límites

Usa context en handlers: timeouts/closures si la lectura de disco tarda.

Establece Server timeouts.

Limita tamaño de respuestas si agregas upload endpoints.

Protege estructuras compartidas con sync.RWMutex o sync.Map.

**Por qué:** evitar bloqueos y DoS involuntarios.

## 12) Seguridad básica

Usa html/template (automática escapada).

Valida nombre de archivo y rechaza rutas con ...

Establece cabeceras: Content-Security-Policy, X-Frame-Options: DENY, X-Content-Type-Options: nosniff.

No ejecutes código de terceros. Sanitiza todo input.

Si implementas upload, haz autenticación/CSRF y límites de tamaño.

## 13) Logging y métricas

Logger estructurado (zap/zerolog). Niveles: INFO / WARN / ERROR.

Middleware de logging para requests (método, path, status, latency).

Exportar /metrics para Prometheus (opcional) — útil en despliegues en nube/universidad.

## 14) Tests y calidad de código

Unit tests:

- TestScanImages (archivos válidos/invalidos)
- TestSelectRandomNoRepeat
- TestEncodeThumbnailToBase64

Integration tests con httptest.Server para verificar / render y headers.

go vet, gofmt, golangci-lint en CI.

Cobertura razonable para las funciones críticas.

CI: GitHub Actions que ejecuta go test ./..., linter y build.

## 15) Dockerización / Build reproducible

Multi-stage Dockerfile (build con golang:1.25, artefacto en scratch o distroless).

Ejemplo (simplificado):

```dockerfile
FROM golang:1.25 AS builder
WORKDIR /src
COPY . .
RUN go build -ldflags="-s -w" -o /app/cmd/image-server ./cmd/image-server

FROM gcr.io/distroless/static
COPY --from=builder /app/cmd/image-server /image-server
EXPOSE 8000
ENTRYPOINT ["/image-server"]
```

Añade HEALTHCHECK y variables en runtime.

## 16) Despliegue (local / nube / k8s)

Local: ./image-server -port 8000 -imgdir ./images

Systemd unit file para producción en VM.

Docker-compose para despliegues simples.

Kubernetes: Deployment + Service + ConfigMap para flags/env; readiness/liveness probes a /healthz.

Asegurar volúmenes para /images.

## 17) Observabilidad y mantenimiento

Endpoint /healthz y /ready para orquestadores.

Rotación/evicción de cache y logs.

Monitorizar uso de RAM (base64 en memoria puede crecer rápido).

Documenta cómo actualizar imágenes (drop-in folder, endpoint de re-scan).

## 18) Funcionalidades opcionales (priorizar según tiempo)

Upload protegido por autenticación.

Endpoint API JSON que devuelva lista de imágenes y dataURLs.

Paginación / lazy-load para muchas imágenes.

Soporte para WebP y modern image formats.

CDN/serving de thumbnails en disco para tráfico alto.

## 19) Checklist pre-entrega / criterios de aceptación

- La app corre en :8000 (o puerto flag).
- Página muestra hasta N imágenes seleccionadas al azar (sin repeticiones).
- Sólo archivos .png, .jpg, .jpeg son considerados (otros ignorados).
- Las imágenes en la página están incluidas como Base64 data: al render.
- Uso de html/template, responsive UI con Bootstrap, tests, dockerfile y graceful shutdown.

Para arrancar, lo ideal es generar el esqueleto del proyecto en Go con la estructura básica y un main.go que levante el servidor y sirva la primera página estática (sin lógica de imágenes todavía). Así tendrás la base lista para ir agregando las funciones que vimos en la hoja de ruta.

## 📂 Estructura inicial del proyecto

```
image-server/
├── cmd/
│   └── image-server/
│       └── main.go
├── internal/
│   ├── server/
│   │   └── server.go
│   ├── images/
│   │   └── scan.go
│   └── templates/
│       └── index.html
├── web/
│   └── static/
│       └── style.css
├── go.mod
├── go.sum
└── Makefile
```

## 📌 cmd/image-server/main.go

```go
package main

import (
	"context"
	"flag"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/tu_usuario/image-server/internal/server"
)

func main() {
	// Flags
	port := flag.String("port", "8000", "Puerto para el servidor HTTP")
	imgDir := flag.String("imgdir", "./images", "Directorio de imágenes")
	flag.Parse()

	// Crear router/servidor
	srv := server.New(*imgDir)

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
```

## 📌 internal/server/server.go

```go
package server

import (
	"html/template"
	"net/http"
	"path/filepath"
)

type Server struct {
	mux    *http.ServeMux
	imgDir string
}

func New(imgDir string) *Server {
	s := &Server{
		mux:    http.NewServeMux(),
		imgDir: imgDir,
	}

	// Rutas
	s.mux.HandleFunc("/", s.handleIndex)
	s.mux.Handle("/static/", http.StripPrefix("/static/", http.FileServer(http.Dir("web/static"))))

	return s
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

	data := map[string]any{
		"Title": "Servidor de imágenes",
	}
	t.Execute(w, data)
}
```

## 📌 internal/templates/index.html

```html
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>{{ .Title }}</title>
  <link rel="stylesheet" href="/static/style.css">
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css">
</head>
<body class="bg-light">
  <div class="container mt-5">
    <h1 class="text-center">{{ .Title }}</h1>
    <p class="text-center">Pronto: galería de imágenes</p>
  </div>
</body>
</html>
```

## 📌 web/static/style.css

```css
body {
  font-family: Arial, sans-serif;
}
```

👉 Con esto ya tienes un servidor que:

- Arranca en el puerto 8000.
- Sirve una página básica en /.
- Entrega archivos estáticos (CSS, JS, imágenes de diseño) desde /static/.