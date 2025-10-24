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
