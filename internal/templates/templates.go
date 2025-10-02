package templates

import (
    "embed"
    "html/template"
    "log"
)

//go:embed index.html
var files embed.FS

// Index is the parsed main template used by the server.
var Index *template.Template

func init() {
    var err error
    Index, err = template.ParseFS(files, "index.html")
    if err != nil {
        log.Fatalf("internal/templates: failed to parse template: %v", err)
    }
}
