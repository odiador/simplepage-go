.PHONY: build test lint docker-build

build:
	go build -o bin/image-server ./cmd/image-server

test:
	go test ./...

lint:
	golangci-lint run

docker-build:
	docker build -t image-server .