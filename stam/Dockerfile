FROM alpine:latest

RUN apk update && apk add cargo make && cargo install --root /usr/ stam-tools

COPY entrypoint.sh /

VOLUME /data

ENTRYPOINT ["/entrypoint.sh"]
