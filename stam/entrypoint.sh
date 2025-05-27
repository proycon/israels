#!/bin/sh

# for use in containers only (see Dockerfile)

set -e

cd /data/stam
make all
