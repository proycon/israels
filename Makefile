all: help
.PHONY: clean untangle webannotations annorepo start stop html
.SECONDARY:
.DELETE_ON_ERROR:

HOSTNAME ?= $(shell hostname -f)
export HOSTNAME
export PATH := $(HOME)/.cargo/bin:$(PATH) 

#----------------- read environment variables from external file(s) ------------
ifneq ($(INCLUDE_ENV),0)
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
endif
#--------------------------------------------------------------------------------

tei_dir := datasource/tei
tei_files := $(wildcard $(tei_dir)/letters/*.xml) $(wildcard $(tei_dir)/about/*.xml)
#tei_flattened contains the 'virtual' files where one layer of nesting is removed
tei_flattened := $(subst letters/,,$(tei_files))
#tei_flattened := $(subst intro/,,$(tei_flattened))
tei_flattened := $(subst about/,,$(tei_flattened))
stam_files := $(tei_flattened:$(tei_dir)/%.xml=work/%.store.stam.json)
webannotation_files := $(tei_flattened:$(tei_dir)/%.xml=work/%.webannotations.jsonl)
html_files := $(tei_flattened:$(tei_dir)/%.xml=data/html/%.html)

untangle: $(stam_files)
stam: $(stam_files)
webannotations: $(webannotation_files)
html: $(html_files)

work:
	mkdir -p $@

# untangle from XML source
#  also produces plain text files in *.txt and work/*.normal.txt (normalised)
#  look in multiple subdirectories for the sources (VPATH)
VPATH = $(tei_dir)/letters:$(tei_dir)/intro:$(tei_dir)/about
work/%.store.stam.json: %.xml etc/stam/fromxml/tei.toml etc/stam/translatetext/norm.toml | work
	@echo "--- Untangling $< ---">&2
	stam fromxml --config etc/stam/fromxml/tei.toml \
		--id-prefix "urn:mace:huc.knaw.nl:israels:{resource}#" --force-new $@ -f $<
	@echo "--- Creating normalised variants ---">&2
	stam translatetext --rules etc/stam/translatetext/norm.toml $@ 
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
tei-info: etc/tei.yml
	@echo "--- Validating TEI ---">&2
	mkdir $@
	. env/bin/activate && validate-tei --tei-dir $(tei_dir) --output-dir $@  --schema-dir schema --config etc/tei.yml

scans: data/scans
data/scans:
	@echo "--- Downloading scans from surfdrive ---">&2
	@echo "   Note: The scans must have been shared explicitly with you for this to work,">&2
	@echo "         and you must have rclone with remote $(RCLONE_SURFDRIVE) set up to connect to surfdrive">&2
	rclone \
		-v sync --no-update-modtime --delete-excluded --exclude '.DS_Store' \
		$(RCLONE_SURFDRIVE):israels-Scans-Curated/scans \
		$@

manifests: data/manifests
data/manifests: tei-info data/scans etc/iiif.yml
	@echo "--- Creating manifests ---">&2
	mkdir -p $@
	. env/bin/activate && generate-manifests --tei-info-dir $< --tei-dir $(tei_dir) --scaninfo-dir data/scans --output-dir $@ --config etc/iiif.yml --title $(PROJECT) --base-uri $(BASE_URL) --iiif-base-uri $(BASE_URL)/iiif/ 

apparatus: data/apparatus
data/apparatus:
	@echo "--- Converting apparatus from TEI XML ---">&2
	mkdir -p $@
	. env/bin/activate && editem-apparatus-convert --inputdir $(tei_dir)/apparatus --outputdir $@ --sizes scanInfo/sizes_illustrations.tsv --project $(PROJECT) --base-url $(CANTALOUPE_URL)/iiif/3


work/%.html.batch: work/%.store.stam.json etc/stam/query.template
	@echo "--- Building script from template for HTML visualisation ---">&2
	#get a list of all resources in the annotation store and output a batch script for each resource (this will usually just be 1 resource)
	stam query --no-header --query 'SELECT RESOURCE ?res' $< | cut -f 2 | sort -n | programs/makebatch.sh etc/stam/query.template html html > $@ 

data/html/%.html: work/%.store.stam.json work/%.html.batch | env
	@echo "--- HTML visualisation via STAM ---">&2
	mkdir -p data/html
	stam batch $< < work/$*.html.batch

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
.index: annorepo textsurf etc/indexer/config.yml | env
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
	cargo install stam-tools
	make env

env: requirements.txt
	@echo "--- Setting up virtual environment ---">&2
	python3 -m venv env && . env/bin/activate && pip install -r requirements.txt
	touch $@
	
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
ifeq ($(MANAGE_SERVICES),1)
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
else
	@echo "--- Services are not managed, not starting them ---">&2
	@touch $@
endif

stop:
ifeq ($(MANAGE_SERVICES),1)
	@echo "--- Stopping services ---">&2 
	docker compose --env-file common.env down
	@rm .started || true
else
	@echo "--- Services are not managed, not stopping them ---">&2
	@rm .started || true
endif

architecture.svg: architecture.mmd
	mmdc -i $< -o $@

architecture.png: architecture.mmd
	mmdc -w 3820 -i $< -o $@


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
	@echo "  html                       - to create static HTML visualisations per letter"
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
