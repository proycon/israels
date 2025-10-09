all: help
.PHONY: clean untangle webannotations annorepo start stop html
.SECONDARY:
.DELETE_ON_ERROR:

HOSTNAME ?= $(shell hostname -f)
export HOSTNAME
export PATH := $(HOME)/.cargo/bin:$(PATH) 

#----------------- read environment variables from external file(s) ------------
include common.env
export $(shell sed '/^\#/d; s/=.*//' common.env)

ifneq (,$(wildcard $(HOSTNAME).env))
#hostname config exists
include $(HOSTNAME).env
export $(shell sed '/^\#/d; s/=.*//' $(HOSTNAME).env)
endif
ifneq (,$(wildcard custom.env))
#custom config exists
include custom.env
export $(shell sed '/^\#/d; s/=.*//' custom.env)
endif
#--------------------------------------------------------------------------------

tei_files := $(wildcard tei/2025-04-24/letters/*.xml)
stam_files := $(tei_files:tei/2025-04-24/letters/%.xml=stam/%.store.stam.json)
webannotation_files := $(tei_files:tei/2025-04-24/letters/%.xml=stam/%.webannotations.jsonl)
html_files := $(tei_files:tei/2025-04-24/letters/%.xml=stam/%.html)

all: webannotations

untangle: $(stam_files)
webannotations: $(webannotation_files)

# untangle from XML source
#  also produces plain text files in stam/*.txt and stam/*.normal.txt (normalised)
stam/%.store.stam.json: tei/2025-04-24/letters/%.xml
	@echo "--- Untangling $< ---">&2
	stam fromxml --config config/stam/fromxml/tei.toml \
		--id-prefix "urn:translatin:{resource}#" --force-new $@ -f $<
	@echo "--- Creating normalised variants ---">&2
	stam translatetext --rules config/stam/translatetext/norm.toml $@ 
	@if [ -e stam/$*.normal.txt ]; then \
		echo "--- Translating annotations to normalised variant ---">&2; \
		stam translate --verbose --no-translations --no-resegmentations --ignore-errors \
			--id-strategy suffix=.normal \
			--query "SELECT ANNOTATION WHERE DATA \"http://www.w3.org/1999/02/22-rdf-syntax-ns#\" \"type\";" $@; \
	fi;

stam/%.webannotations.jsonl: stam/%.store.stam.json env 
	@echo "--- Exporting web annotations for $< ---">&2
	. env/bin/activate && stam query \
		--add-context "https://ns.huc.knaw.nl/text.jsonld" \
		--add-context "https://ns.huc.knaw.nl/textannodata.jsonld" \
		--ns "tei: http://www.tei-c.org/ns/1.0#" \
		--ns "xml: http://www.w3.org/XML/1998/namespace/" \
		--extra-target-template "$(TEXTSURF_URL)/api2/$(PROJECT)|{resource}/{begin},{end}" \
		--annotation-prefix "$(ANNOREPO_URL)/$(PROJECT)/" \
		--resource-prefix "$(TEXTSURF_URL)/$(PROJECT)" \
		--format w3anno \
		$< | consolidate-web-annotations  > $@;
	@rm .annorepo-uploaded 2> /dev/null || true

stam/%.html: stam/%.html.batch env
	@echo "--- HTML visualisation via STAM ---">&2
	echo $< | programs/makebatch.sh query.template html html > $@.batch && stam stam/$*.html.batch $< < $@.batch
	rm $@.html.batch

stam/%.ansi.txt: stam/%.html.batch env
	@echo "--- ANSI Text visualisation via STAM ---">&2
	echo $< | programs/makebatch.sh query.template ansi ansi.txt > $@.batch && stam stam/$*.ansi.batch $< < $@.batch
	rm $@.ansi.batch

stam/%.html.batch: stam/%.store.stam.json
	@echo "--- Preparing for HTML visualisation ---">&2
	stam query --no-header --query 'SELECT RESOURCE ?res' $< | cut -f 2 | sort -n | ./programs/makebatch.sh stam/query.template html html > $@ 

html: $(html_files)
	@echo "--- HTML visualisation via STAM (all) ---">&2
	stam batch $< < html.batch

ingest: annorepo textsurf

annorepo: .annorepo-uploaded
.annorepo-uploaded: .started env $(webannotation_files)
	@echo "--- Clearing Broccoli cache (prior) ---">&2
	-curl -X DELETE "$(BROCCOLI_URL)/projects/$(PROJECT)/cache"
	@echo "--- Exporting web annotations to Annorepo ---">&2
	. env/bin/activate && upload-web-annotations \
		--annorepo-base-url "$(ANNOREPO_URL)" \
		--container-id "$(PROJECT)" \
		--api-key "$(ANNOREPO_ROOT_API_KEY)" \
		--overwrite-existing-container $(webannotation_files)
	@echo "--- Clearing Broccoli cache (post) ---">&2
	-curl -X DELETE "$(BROCCOLI_URL)/projects/$(PROJECT)/cache"
	@touch $@

textsurf: data/textsurf/.populated
data/textsurf/.populated: .started $(stam-files)
	cp -f stam/*.txt data/textsurf/
	@touch $@

index: .index
.index: annorepo
	. env/bin/activate && peen-indexer \
		--annorepo-host=$(ANNOREPO_URL) \
		--annorepo-container=$(PROJECT) \
		--config etc/indexer/config.yml \
		--elastic-host=$(ELASTIC_URL) \
		--elastic-index=$(PROJECT)
	@touch $@

install-dependencies: 
	@echo "--- Checking global prerequisites---">&2
	@command -v cargo || (echo "Missing dependency: cargo" && false)
	@command -v rustc || (echo "Missing dependency: rustc" && false)
	@command -v curl || (echo "Missing dependency: curl" && false)
	@command -v python3 || (echo "Missing dependency: python3" && false)
	@command -v docker || (echo "Missing dependency: docker" && false)
	@echo "--- Installing local dependencies ---">&2
	command -v stam || cargo install stam-tools
	make env

env:
	@echo "--- Setting up virtual environment ---">&2
	python3 -m venv env && . env/bin/activate && pip install -r requirements.txt
	
clean: clean-services
	-rm -Rf stam/*.stam.json stam/*jsonl stam/*.txt stam/*html

clean-services:
	-make stop
	-rm -Rf .started .annorepo-uploaded .index data/elastic data/mongo data/textsurf

logs:
	docker compose --env-file common.env logs --follow

start: .started
.started:
	mkdir -p data/elastic
	chmod a+rwx data/elastic #temporary patch, this is obviously not smart in production settings
	@ping -c 1 $(HOSTNAME) || (echo "Sanity check failed: detected hostname ($HOSTNAME) does not resolve" && false)
	@touch $@
ifneq (,$(wildcard custom.env))
	@echo "--- Starting services (with custom config) ---">&2
	docker compose --env-file common.env --env-file "custom.env" up &
else ifneq (,$(wildcard $(HOSTNAME).env))
	@echo "--- Starting services for $(HOSTNAME) ---">&2
	docker compose --env-file common.env --env-file "$(HOSTNAME).env" up &
else
	@echo "--- Starting services (common configuration only) ---">&2
	docker compose --env-file common.env up &
endif

stop:
	@echo "--- Stopping services ---">&2 
	docker compose --env-file common.env down
	@rm .started || true

help:
	@echo "Please use \`make <target>', where <target> is one of:"
	@echo "  install-dependencies       - to install the necessary dependencies for the data processing pipeline"
	@echo
	@echo "  start                      - to start all services (docker compose up)"
	@echo "  stop                       - to stop all services (docker compose down)"
	@echo 
	@echo "(individual steps in ascending/chronological dependency order):"
	@echo "  untangle                   - to untangle TEI XML into STAM JSON and plain text"
	@echo "  webannotations             - to generate webannotations"
	@echo "  ingest                     - to populate the various services with data"
	@echo 
	@echo "(individual upload steps in ascending/chronological order where applicable):"
	@echo "  annorepo                   - to upload the webannotations to Annorepo"
	@echo "  textsurf                   - to add the texts to TextSurf"
	@echo "  index                      - to build the search index"
	@echo
	@echo "(cleaning targets):"
	@echo "  clean                      - clean all generated targets (including services, but keeps dependencies intact)"
	@echo "  clean-services             - cleans all data pertaining to the services"
	@echo "  clean-dependencies         - clean local dependencies (python env)"
