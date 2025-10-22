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

tei_dir := tei/2025-10-07
tei_files := $(wildcard $(tei_dir)/letters/*.xml) $(wildcard $(tei_dir)/intro/*.xml) $(wildcard $(tei_dir)/about/*.xml)
#tei_flattened contains the 'virtual' files where one layer of nesting is removed
tei_flattened := $(subst letters/,,$(tei_files))
tei_flattened := $(subst intro/,,$(tei_flattened))
tei_flattened := $(subst about/,,$(tei_flattened))
stam_files := $(tei_flattened:$(tei_dir)/%.xml=work/%.store.stam.json)
webannotation_files := $(tei_flattened:$(tei_dir)/%.xml=work/%.webannotations.jsonl)
html_files := $(tei_flattened:$(tei_dir)/%.xml=work/%.html)

untangle: $(stam_files)
webannotations: $(webannotation_files)

work:
	mkdir -p $@

# untangle from XML source
#  also produces plain text files in *.txt and work/*.normal.txt (normalised)
#  look in multiple subdirectories for the sources (VPATH)
VPATH = $(tei_dir)/letters:$(tei_dir)/intro:$(tei_dir)/about
work/%.store.stam.json: %.xml | work
	@echo "--- Untangling $< ---">&2
	stam fromxml --config config/fromxml/tei.toml \
		--id-prefix "urn:translatin:{resource}#" --force-new $@ -f $<
	@echo "--- Creating normalised variants ---">&2
	stam translatetext --rules config/translatetext/norm.toml $@ 
	@if [ -e $*.normal.txt ]; then \
		echo "--- Translating annotations to normalised variant ---">&2; \
		stam translate --verbose --no-translations --no-resegmentations --ignore-errors \
			--id-strategy suffix=.normal \
			--query "SELECT ANNOTATION WHERE DATA \"http://www.w3.org/1999/02/22-rdf-syntax-ns#\" \"type\";" $@; \
	fi;

vpath #reset VPATH
work/%.webannotations.jsonl: work/%.store.stam.json | env 
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

validate: tei-info
tei-info:
	@echo "--- Validating TEI ---">&2
	mkdir $@
	. env/bin/activate && validate-tei --tei-dir $(tei_dir) --output-dir $@  --schema-dir schema --config config/tei.yml

data/scans:
	@echo "--- Downloading scans from surfdrive ---">&2
	@echo "   Note: The scans must have been shared explicitly with you for this to work,">&2
	@echo "         and you must have rclone with remote $(RCLONE_SURFDRIVE) set up to connect to surfdrive">&2
	rclone \
		-v sync --no-update-modtime --delete-excluded --exclude '.DS_Store' \
		$(RCLONE_SURFDRIVE):israels-Scans-Curated/scans \
		$@

manifests: data/manifests
data/manifests: tei-info scans
	@echo "--- Creating manifests ---">&2
	mkdir -p $@
	. env/bin/activate && generate-manifests --tei-info-dir $< --tei-dir $(tei_dir) --scaninfo-dir data/scans --output-dir $@ --config config/iiif.yml --title $(PROJECT) --base-uri $(BASE_URL) --iiif-base-uri $(BASE_URL)/iiif/ 

apparatus: data/apparatus
data/apparatus: scans
	@echo "--- Converting apparatus from TEI XML ---">&2
	mkdir -p $@
	. env/bin/activate && editem-apparatus-convert --inputdir $(tei_dir)/apparatus --outputdir $@ --sizes data/scans/sizes_illustrations.tsv --project $(PROJECT) --base-url $(CANTALOUPE_URL)/iiif/3

data/html/%.html: work/%.html.batch env
	@echo "--- HTML visualisation via STAM ---">&2
	mkdir -p data/html
	echo $< | programs/makebatch.sh config/stam/query.template html html > $@.batch && stam $*.html.batch $< < $@.batch
	rm $@.html.batch

data/ansi/%.ansi.txt: work/%.html.batch env
	@echo "--- ANSI Text visualisation via STAM ---">&2
	mkdir -p data/ansi
	echo $< | programs/makebatch.sh config/stam/query.template ansi ansi.txt > $@.batch && stam $*.ansi.batch $< < $@.batch
	rm $@.ansi.batch

work/%.html.batch: work/%.store.stam.json
	@echo "--- Preparing for HTML visualisation ---">&2
	stam query --no-header --query 'SELECT RESOURCE ?res' $< | cut -f 2 | sort -n | ./programs/makebatch.sh config/stam/query.template html html > $@ 

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
	mkdir -p data/textsurf/$(PROJECT)
	chmod a+w data/textsurf/$(PROJECT) #TODO: temporary patch, this is obviously not smart in production settings
	cp -f *.txt data/textsurf/$(PROJECT)
	@touch $@

index: .index
.index: annorepo textsurf | env
	. env/bin/activate && peen-indexer \
		--annorepo-host=$(ANNOREPO_URL) \
		--annorepo-container=$(PROJECT) \
		--config config/indexer/config.yml \
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
	-rm -Rf *.stam.json work tei-info manifests

clean-services:
	-make stop
	-rm -Rf .started .annorepo-uploaded .index data/*

clean-annorepo:
	-rm -rf data/mongo
	-rm .annorepo-uploaded

clean-textsurf:
	-rm -rf data/textsurf

clean-index:
	-rm -rf data/elastic
	-rm .index

clean-apparatus:
	-rm -rf data/apparatus

clean-manifests:
	-rm -rf data/manifests

clean-scans:
	-rm -rf data/scans

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
	docker compose --env-file common.env --env-file "custom.env" up -d
else ifneq (,$(wildcard $(HOSTNAME).env))
	@echo "--- Starting services for $(HOSTNAME) ---">&2
	docker compose --env-file common.env --env-file "$(HOSTNAME).env" up -d
else
	@echo "--- Starting services (common configuration only) ---">&2
	docker compose --env-file common.env up -d
endif
	@echo "--- Use 'make logs' to see docker logs" >&2

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
	@echo "  logs                       - to view/follow the logs of all services (docker compose logs)"
	@echo 
	@echo "(individual steps in ascending/chronological dependency order where applicable):"
	@echo "  validate                   - to validate TEI XML input"
	@echo "  scans                      - download scans (from surfdrive, must have been shared with you)"
	@echo "  manifests                  - create IIIF manifests"
	@echo "  apparatus                  - convert apparatus from TEI XML"
	@echo ""
	@echo "  untangle                   - to untangle TEI XML into STAM JSON and plain text"
	@echo "  webannotations             - to generate webannotations"
	@echo "  ingest                     - to populate the various services with data. Subtargets "
	@echo "      annorepo               - to upload the webannotations to Annorepo"
	@echo "      textsurf               - to add the texts to TextSurf"
	@echo "      index                  - to build the search index"
	@echo
	@echo "(cleaning targets):"
	@echo "  clean                      - clean all generated targets (including services, but keeps dependencies intact)"
	@echo "  clean-services             - cleans all data pertaining to the services. subtargets:"
	@echo "  	clean-apparatus"
	@echo "  	clean-scans"
	@echo "  	clean-manifests"
	@echo "  	clean-annorepo"
	@echo "  	clean-textsurf"
	@echo "  	clean-index"
	@echo "  clean-dependencies         - clean local dependencies (python env)"
