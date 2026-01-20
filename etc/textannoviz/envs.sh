#!/bin/sh

envsubst < /usr/share/nginx/html/config.json.template > /usr/share/nginx/html/config.json
# ./docker-entrypoint.sh
