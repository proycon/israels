.SHELLFLAGS: -o pipefail -c
.PHONY: deps stam webannotations html docker
.DELETE_ON_ERROR:

all: stam html webannotations

stam: israels-letters.store.stam.json

deps:
	@echo "--- Installing dependencies ---">&2
	cargo install stam-tools

clean:
	-rm tei.index *.txt *.json *.html *.batch *.jsonl

tei.index:
	@echo "--- Building TEI index ---">&2
	find ../tei/2025-04-24/letters -name "*xml" > $@

israels-letters.store.stam.json: tei.index
	@echo "--- Converting XML to STAM (untangling) ---">&2
	stam fromxml --ignore-errors --config tei.toml --id-prefix "{resource}#" --inputfilelist $< --force-new $@

%.html: %.txt israels-letters.store.stam.json
	@echo "--- HTML visualisation via STAM ---">&2
	echo $< | ./makebatch.sh query.template html html > $@.batch && stam batch israels-letters.store.stam.json < $@.batch
	rm $@.batch

%.ansi.txt: %.txt israels-letters.store.stam.json
	@echo "--- ANSI Text visualisation via STAM ---">&2
	echo $< | ./makebatch.sh query.template ansi ansi.txt > $@.batch && stam batch israels-letters.store.stam.json < $@.batch
	rm $@.batch

html.batch: israels-letters.store.stam.json
	@echo "--- Preparing for HTML visualisation ---">&2
	stam query --no-header --query 'SELECT RESOURCE ?res' $< | cut -f 2 | sort -n | ./makebatch.sh query.template html html > $@ 

html: israels-letters.store.stam.json html.batch
	@echo "--- HTML visualisation via STAM (all) ---">&2
	stam batch $< < html.batch

webannotations: israels-letters.webannotations.jsonl

israels-letters.webannotations.jsonl: israels-letters.store.stam.json
	stam query --format w3anno $< > $@

docker:
	docker build -t israels-letters-stam .
