# =============================================================================
# statcast-ingest-pipeline — root Makefile
#
# Thin wrapper around the repo's local dev loop: Python env setup, LocalStack,
# SAM local invokes against the fixture events in src/events/, and delegation
# to infra/terraform/Makefile for packaging Lambdas and running Terraform.
# =============================================================================

VENV   := .venv
PYTHON := $(VENV)/bin/python
PIP    := $(VENV)/bin/pip

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}'

# ── Python env ────────────────────────────────────────────────────────────────
.PHONY: venv install

venv: ## Create the local virtualenv
	python3 -m venv $(VENV)

install: venv ## Install dev deps + each Lambda's own requirements
	$(PIP) install -r requirements-dev.txt
	$(PIP) install -r src/poller/requirements.txt
	$(PIP) install -r src/play-by-play/requirements.txt

.PHONY: test
test: ## Run the test suite
	$(VENV)/bin/pytest

# ── LocalStack ───────────────────────────────────────────────────────────────
.PHONY: localstack-up localstack-down localstack-logs

localstack-up: ## Start LocalStack (docker compose)
	docker compose up -d

localstack-down: ## Stop LocalStack
	docker compose down

localstack-logs: ## Tail LocalStack logs
	docker compose logs -f localstack

# ── Lambda packaging (delegates to infra/terraform/Makefile) ────────────────
.PHONY: build

build: ## Zip the poller + play-by-play Lambdas into .build/
	$(MAKE) -C infra/terraform build

# ── SAM local invoke ─────────────────────────────────────────────────────────
# Each Lambda checks AWS_SAM_LOCAL and points its boto3 clients at
# host.docker.internal:4566 itself, so no --env-vars file is needed here —
# just make sure `make localstack-up` is running first.
# NOTE: -t must point at the *built* template so deps from requirements.txt
# are actually mounted into the container — pointing at src/template.yaml
# mounts the raw source dir and skips installed dependencies entirely.
SAM_TEMPLATE := .aws-sam/build/template.yaml
# Real ARN/bucket values from `make tf-local-apply` — sam local invoke can't
# resolve !Ref against a real stack, so it substitutes garbage without this.
SAM_ENV_VARS := src/events/local-env-vars.json

.PHONY: sam-build invoke-poller-daily invoke-poller-backfill invoke-play-by-play

sam-build: ## Build Lambda dependencies for sam local invoke
	sam build -t src/template.yaml

invoke-poller-daily: sam-build ## Invoke PollerFunction locally with the daily-poll event
	sam local invoke PollerFunction -t $(SAM_TEMPLATE) -e src/events/daily.json --env-vars $(SAM_ENV_VARS)

invoke-poller-backfill: sam-build ## Invoke PollerFunction locally with the backfill event
	sam local invoke PollerFunction -t $(SAM_TEMPLATE) -e src/events/backfill.json --env-vars $(SAM_ENV_VARS)

invoke-play-by-play: sam-build ## Invoke PlayByPlayFunction locally with a fake SQS/SNS event
	sam local invoke PlayByPlayFunction -t $(SAM_TEMPLATE) -e src/events/play-by-play-sqs.json --env-vars $(SAM_ENV_VARS)

# ── Terraform (delegates to infra/terraform/Makefile) ────────────────────────
# e.g. `make tf-local-plan`, `make tf-prod-apply`, `make tf-local-destroy`
tf-%:
	$(MAKE) -C infra/terraform $*

# ── Cleanup ───────────────────────────────────────────────────────────────────
.PHONY: clean

clean: ## Remove build artifacts and caches
	rm -rf .build .aws-sam .pytest_cache
	find . -name '__pycache__' -not -path './$(VENV)/*' -exec rm -rf {} +
