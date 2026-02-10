FROM alpine:latest

# this builds a container for the corpus processing workflow
# it does *NOT* provide the services, services are external
# and specified via environment variables

# The container contains the input corpus, either fully or in part, so may be quite big

RUN apk update &&\
    apk add cargo rust python3 py3-pip curl make git pandoc openjdk21-jre-headless &&\
    apk upgrade -a

COPY . /usr/src
WORKDIR /usr/src
RUN cd /usr/src && INCLUDE_ENV=0 MANAGE_SERVICES=0 make install-dependencies

ENV PROJECT=israels
ENV INCLUDE_ENV=0
ENV MANAGE_SERVICES=0

ENV BASE_URL=https://${HOSTNAME}
ENV ANNOREPO_ROOT_API_KEY=00000000-0000-0000-0000-000000000000
ENV ANNOREPO_URL=${BASE_URL}:${ANNOREPO_PORT}
ENV ANNOREPO_PORT=8080
ENV TEXTSURF_API_KEY=${ANNOREPO_ROOT_API_KEY}

ENV TEXTSURF_PORT=8083
ENV TEXTSURF_URL=${BASE_URL}:${TEXTSURF_PORT}
ENV ELASTIC_URL=${BASE_URL}:${ELASTIC_PORT}
ENV BROCCOLI_URL=${BASE_URL}:${BROCCOLI_PORT}

ENV TEXTANNOVIZ_PORT=8088
ENV TEXTANNOVIZ_VERSION=1.0.0
ENV TEXTANNOVIZ_URL=${BASE_URL}:${TEXTANNOVIZ_PORT}

ENV CANTALOUPE_PORT=8084
ENV CANTALOUPE_URL=${BASE_URL}:${CANTALOUPE_PORT}

#HTTP server for static files such as apparatus and manifests
ENV NGINX_PORT=8040
ENV NGINX_URL=${BASE_URL}:${NGINX_PORT}

ENTRYPOINT ["make"]
