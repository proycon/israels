#!/bin/sh
echo "--- Workflow Check ---">&2
echo "Project: $PROJECT">&2
echo "Working directory: $(realpath .)">&2
if [ -e .git ]; then
    echo "Git: yes ($(git show -s --format='%H %ci' HEAD))">&2
else
    echo "Git: no ">&2
fi
echo "User: $(whoami)">&2
echo "System: $(uname -a)">&2
#shellcheck disable=SC3037
echo -n "Write access: ">&2
(touch .test && rm .test && echo "yes") || (echo "NO!!!" && stat "$(realpath .)" && exit 1)
echo "Base URL: $BASE_URL">&2
echo "Textannoviz URL: $TEXTANNOVIZ_URL">&2
echo "Textsurf URL: $TEXTSURF_URL">&2
echo "Annorepo URL: $ANNOREPO_URL">&2
echo "Broccoli URL: $BROCCOLI_URL">&2
echo "Elastic URL: $ELASTIC_URL">&2
if [ "$MANAGE_SERVICES" = "1" ]; then
	echo "Services managed? yes">&2
	if [ -e .started ]; then echo "Services started? yes">&2; else echo "Services started? no   (run: make start)">&2; fi
	echo "--- Data presence checks ---">&2
	if [ -e data/elastic/indices ] && [ -e .index ]; then echo "Elastic: yes ($(date -r .index))">&2; else echo "Elastic: no    (run: make index)">&2; fi
	if [ -e data/textsurf/.populated ]; then echo "Textsurf: yes ($(date -r data/textsurf/.populated))">&2; else echo "Textsurf: no    (run: make textsurf)">&2; fi
	if [ -e .annorepo-uploaded ] && [ -e data/mongo ]; then echo "Annorepo: yes ($(date -r .annorepo-uploaded))">&2; else echo "Annorepo: no    (run: make annorepo)">&2; fi
else
	echo "Services managed? no   (this means services are not owned by the workflow process itself, but e.g. by a kubernetes deployment)">&2
	echo "--- Data processing checks ---">&2
	if [ -e .index ]; then echo "Elastic: yes ($(date -r .index))">&2; else echo "Elastic: no    (run: make index)">&2; fi
	if [ -e .textsurf-populated ]; then echo "Textsurf: yes ($(date -r .textsurf-populated))">&2; else echo "Textsurf: no    (run: make textsurf)">&2; fi
	if [ -e .annorepo-uploaded ];  then echo "Annorepo: yes ($(date -r .annorepo-uploaded))">&2; else echo "Annorepo: no    (run: make annorepo)">&2; fi
fi
echo "--------------------------">&2
