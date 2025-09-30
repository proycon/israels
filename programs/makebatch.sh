#!/bin/sh

# creates a batch script to visualise resources, for use with `stam batch`

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Invalid parameters: expected resource_id, format, and output extension">&2
    exit 1
fi

# take a template and repeats a query for each input resource
while read -r resource_id; do
    if [ -n "$resource_id" ]; then
        htmlout=${resource_id%.txt}
        tr -d '\n' < "$1" | sed -e "s/{resource_id}/$resource_id/" -e "s/{format}/$2/" -e "s/$/ > $htmlout.$3/" 
        echo
    fi
done
