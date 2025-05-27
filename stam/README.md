# STAM model for Israels letters

This directory contains a script to generate:

* a STAM model for the Israels letters (from TEI XML)
* static HTML visualisation with a few selected annotations (highlights), formulated [in several queries](query.template).
* W3C Web Annotation output for all annotations

## Installation

Make sure you have `cargo` and GNU make installed, the necessary dependency
[stam-tools](https://github.com/annotation/stam-tools) can then be
automatically pulled in and installed as follows:

```
$ make deps
```

Next,  you can generate all data with a simple:

```
$ make all
```

### Container

If you want, a Docker container is provided, from `stam/` run:

```
$ docker build . -t israels-letters-stam
```

Then run from the *root directory* of this repo (not the `stam` directory!) and make sure to map the data inside the container when running:

```
$ docker run --rm -v .:/data israels-letters-stam
```

## Pipeline

TEI-to-XML conversion, or so-called untangling, is performed by `stam fromxml`, this generates a whole lot of plain text files (`*.txt`, one for each letter) stripped of all markup, and stand-off annotations in `israels-letters.store.stam.json`. HTML generation is performed with `stam view`.

W3C Web Annotation exported is performed by `stam export` and saved to `israels-letters.webannotations.jsonl` with one webannotation per line.
