SHELL := /bin/bash 
DOCKER ?= $(shell command -v docker || command -v podman || docker)
ASCIIDOC := asciidoctor/docker-asciidoctor:latest
DIRMOUNTS := /documents
DIRCONTENTS := chapters
DIRSCRIPTS := scripts
DIRBUILDS := output
DIRINCLUDES := includes
DIRWORK := $(shell pwd -P)


.PHONY: all clean install lint format pull assets rules html pdf epub force
.PHONY: check check-rules check-rules-duplicates check-rules-incorrects
.PHONY: next-rule-id watch changelog

all: clean html rules
clean:
	rm -rf $(DIRBUILDS) $(DIRINCLUDES);

install: $(NVM_BIN)/markdownlint
$(NVM_BIN)/markdownlint:
	npm install --global markdownlint-cli;
lint: $(NVM_BIN)/markdownlint
	markdownlint --config .markdownlint.yaml chapters/*.adoc;
format: $(NVM_BIN)/markdownlint
	markdownlint --config .markdownlint.yaml --fix chapters/*.adoc;

pull:
	$(DOCKER) pull $(ASCIIDOC);

check: check-rules
check-rules: check-rules-duplicates check-rules-incorrects
check-rules-duplicates:
	@DUPLICATED="$$(grep -roE "\[#[0-9]+]" $(DIRCONTENTS) | sort |uniq -d)"; \
	if [ -n "$${DUPLICATED}" ]; then \
	    echo "Duplicated Rule IDs: $$(echo "$${DUPLICATED}" | tr -d '\n')"; \
	    echo "Please make sure the Rule ID anchors are unique"; \
	    exit 1; \
	fi;

check-rules-incorrects:
	@INCORRECT="$$(grep -rnE "(^\[[0-9]{1,4}\]|\[ +#?[0-9]+ +\])" $(DIRCONTENTS))"; \
	if [ -n "$${INCORRECT}" ]; then \
	    echo -e "Incorrect Rule IDs:\n $${INCORRECT}"; \
	    echo "Please make sure that the Rule ID anchors conform to '\[#[0-9]+\]'"; \
	    exit 1; \
	fi;

next-rule-id:
	@IFS=$$'\r\n' GLOBIGNORE='*' command eval \
	"RULE_IDS=($$(grep -rh "^.*\[#[0-9]\{1,5\}.*$$" $(DIRCONTENTS) | sort -r))"; \
	echo $$(($$(echo $${RULE_IDS[0]} | tr -d '\[' | tr -d '\]' | tr -d '#') + 1));

changelog:
	$(DIRSCRIPTS)/changelog.sh --update

assets:
	mkdir -p $(DIRBUILDS);
	cp -r assets $(DIRBUILDS)/;
	cp -r models $(DIRBUILDS)/;
	cp -r models/{problem-1.0.{0,1},money-1.0.0}.yaml $(DIRBUILDS);

rules: check-rules
	$(DIRSCRIPTS)/generate-rules-json.sh  | \
	  jq -s '{rules: . | sort}' | tee $(DIRBUILDS)/rules >$(DIRBUILDS)/rules.json;

$(DIRINCLUDES): models/headers-1.0.0.yaml $(DIRSCRIPTS)/generate-includes.sh
	mkdir -p $(DIRINCLUDES); $(DIRSCRIPTS)/generate-includes.sh "$(DIRINCLUDES)";

html: $(DIRINCLUDES) check assets pull
	$(DOCKER) run --interactive --user=$$(id -u):$$(id -g) \
	  --volume=$(DIRWORK):$(DIRMOUNTS)/ \
	  $(ASCIIDOC) asciidoctor -D $(DIRMOUNTS)/$(DIRBUILDS) index.adoc;

watch:
	watchexec --exts adoc,css --ignore output -r make html

# Not used any longer.
pdf: $(DIRINCLUDES) check pull
	$(DOCKER) run --interactive --user=$$(id -u):$$(id -g) \
	  --volume=$(DIRWORK):$(DIRMOUNTS)/ \
	  $(ASCIIDOC) asciidoctor-pdf -v \
		-a pdf-fontsdir=$(DIRMOUNTS)/resources/fonts \
		-a pdf-theme=$(DIRMOUNTS)/resources/themes/pdf-theme.yml \
	    -D $(DIRMOUNTS)/$(DIRBUILDS) index.adoc;
	mv -f $(DIRBUILDS)/index.pdf $(DIRBUILDS)/zalando-guidelines.pdf;

# Not used any longer.
epub: $(DIRINCLUDES) check pull
	$(DOCKER) run --interactive --user=$$(id -u):$$(id -g) \
	  --volume=$(DIRWORK):$(DIRMOUNTS)/ \


Hi [Name],

Thanks for filling in §5b. I’ll merge the LTV standards and amortization thresholds into the spec.

You asked what’s next. Before we tackle the open questions at the end, I’d like to confirm a few data and config points, because they decide whether we can feed the model from our current stack. That stack is our data model, the data collection service, and the Python GenAI service. The optimizer would run inside the GenAI service as a deterministic step before the summary is generated. Once these are answered, the open questions that block the build (OQ-28, 30, 32, 33, 34) get much easier to close. The rest can follow.

Some of these probably need the data collection team or Lucrezia. I’ve noted who I think can answer each one, so feel free to forward.

Most important: these could change the design

Other lenders’ notes. Do we receive every registered mortgage note on a property in rank order, including notes held by other lenders? Or only our own notes? Prior liens and legal capacity (§5.6) depend on the other lenders’ notes. (Data collection team, Collateral system)
Allocation engine output. Do we already get the engine’s allocated and available collateral? If so, is it per limit × property or per limit × note? Is it CHF of note nominal? Can the same spare headroom show as available under several limits (OQ-30)? The contractual scenario depends on this. (Lucrezia, data collection team)
Group Credit Memos. When limits and properties belong to different legal entities, may a property of entity A secure a limit of entity B in the unconstrained scenario? Or only within the same entity? This changes the model itself. (You, Credit / Legal)
§5b keys. For each attribute your tables use (type, age and anything else you added): do we have it as a field in our real-estate data model, and do our codes map 1:1 to your categories? How are mixed-use properties classified? (Data collection team)
Hosting and governance. Can the optimizer run as a deterministic module inside our GenAI service, with the LLM only describing the result and never calculating it? Or does model-risk policy require a separate, independently validated component? (You, Model risk)

Data points

How do we identify a limit as real-estate secured (OQ-32)? Which field gives its exposure: the limit amount, the drawn amount, or drawn plus undrawn? (Data collection team, you)
Do we have the lending value (Belehnungswert) and its valuation date, or only the market value? (Data collection team)
Are construction year and renovation year available and reliable? If one is missing, should we reject the property or use a fallback row, for example the most conservative one? (You, data collection team)
How common are joint liens, meaning one note over several properties? The spec rejects them today, so if they’re common, many Credit Memos would fail. (Lucrezia)
Is non-real-estate collateral (securities, cash, guarantees) on the same limits in our data model? Should we ignore it, or deduct it from the exposure first (OQ-33)? (You)
Do non-CHF limits or properties abroad occur? Should we exclude them or reject the Credit Memo? (You)
What are the typical and maximum numbers of properties and limits per Credit Memo? Do we also need batch re-runs across the portfolio, or only runs when a Credit Memo is created? (You)

Config

Policy tables. Who owns the §5b tables, and how often do they change? Should they live in our code repository (one release per change) or somewhere credit policy can edit them directly? When policy changes, do we re-run an old Credit Memo with the table that was valid on its as-of date? (You, Credit policy)
Amortization. Is the policy always “rate × amount above the threshold”, for example amortize down to the threshold within N years? Or are there fixed minimums, or rates that vary by LTV? If it’s always linear, we can drop two of the three rule types. (You, Credit policy)
RWA. Since a relative figure is enough, I propose one flat indicative weight per row of your table, labelled “indicative” wherever users see it. Together with linear amortization, this removes the LTV-band logic, the most intricate part of the preprocessing. Is that OK, or would you rather drop the RWA stage entirely? (You)

Output and operations

Where should the result appear: a two-column table in the Credit Memo, the UI, the GenAI summary? Who uses the per-limit line items? (You)
If one property lacks data, should the whole calculation stop, as the spec says today? Or should we calculate with what we have and flag the gap? (You)
The spec requires every run to be stored for 10 years and to be re-runnable (§12). Does the Credit Memo platform already keep the payload and the result, or is that new storage? (You, Architecture / Compliance)

If it’s easier, we can go through 1–5 in a 30-minute call and do the rest by email.

Thanks,
	  $(ASCIIDOC) asciidoctor-epub3 -D $(DIRMOUNTS)/$(DIRBUILDS) index.adoc;
	mv -f $(DIRBUILDS)/index.epub $(DIRBUILDS)/zalando-guidelines.epub;
