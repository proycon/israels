# Israels

This is the data processing and service pipeline for the Israels corpus.
The actual source documents for this project are kept in the [israels-letters](https://gitlab.huc.knaw.nl/eDITem/israels-letters) repository,
which is included as a git submodule in this repo at `datasource/`.

## Architecture

The following schema schematically shows the technical architecture of the entire data processing pipeline:

![Israels Data Processing - Technical Architecture](architecture.png)

### Legend

* bold edges/arrows indicate data flow
* thin edges/arrows indicate caller direction
* square green boxes represent processes 
* squirely yellow boxes represent data 
* blue parallelograms represent services

## Usage

We assume you already have `cargo`, `rustc`,  `python3` and `docker-compose` (or `podman-compose`), `pandoc` and GNU `make` installed globally. If not, please install those first:

* **Debian/Ubuntu Linux**: `apt install cargo python3 docker-compose pandoc make`
* **Alpine Linux**: `apk add cargo python3 docker-cli-compose pandoc-cli make`
* **macOS/Homebrew**: `homebrew install rust python docker-compose pandoc make`

For full usage instructions, please do: 

```
$ make help
```

This lists all the make targets and allows you fine-grained control over what steps to run.

If you want to just run the entire conversion pipeline, including starting all
services and populating them with data, then just do:

```
make
```

All services will run in docker containers, the data conversion pipeline runs
on your host itself. We use `make start` and `make stop` to invoke,
respectively, `docker compose up` and `docker compose down`. You can inspects
their logs via `make logs`.

To override configuration variables for your setup, create a `custom.env` or
`$HOSTNAME.env` and copy and adapt the variables from `common.env` you want to
override.
