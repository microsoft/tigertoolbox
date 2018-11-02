
# Multi-stage build setup (https://docs.docker.com/develop/develop-images/multistage-build/)

# Stage 1 (to create a "build" image, ~850MB)
FROM golang:1.11 AS builder
RUN go version

COPY . /app
WORKDIR /app
RUN go get -u github.com/gorilla/mux
RUN go get -u github.com/gorilla/handlers
RUN go get -u github.com/denisenkom/go-mssqldb

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -o app .

# Stage 2 (to create a downsized "container executable", ~7MB)

#  If you need SSL certificates for HTTPS, replace `FROM SCRATCH` with:
#
#   FROM alpine:3.7
#   RUN apk --no-cache add ca-certificates
#
FROM scratch
WORKDIR /root/
COPY --from=builder /app .

EXPOSE 8080
ENTRYPOINT ["./app"]