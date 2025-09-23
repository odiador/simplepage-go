FROM golang:1.25 AS builder
WORKDIR /src
COPY . .
RUN go build -ldflags="-s -w" -o /app/cmd/image-server ./cmd/image-server

FROM gcr.io/distroless/static
COPY --from=builder /app/cmd/image-server /image-server
EXPOSE 8000
ENTRYPOINT ["/image-server"]