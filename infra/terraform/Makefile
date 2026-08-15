TF               := terraform
POLLER_SRC       := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../src/poller)
PLAY_BY_PLAY_SRC := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../src/play-by-play)
BUILD_DIR        := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../.build)

# ── build ────────────────────────────────────────────────────────────────────
.PHONY: build build-poller build-play-by-play

build: build-poller build-play-by-play

build-poller:
	rm -rf $(BUILD_DIR)/poller
	mkdir -p $(BUILD_DIR)/poller
	pip3 install -r $(POLLER_SRC)/requirements.txt -t $(BUILD_DIR)/poller --quiet
	cp $(POLLER_SRC)/*.py $(BUILD_DIR)/poller/
	cd $(BUILD_DIR)/poller && zip -r ../poller.zip . -x "*.pyc" -x "*/__pycache__/*"

build-play-by-play:
	rm -rf $(BUILD_DIR)/play-by-play
	mkdir -p $(BUILD_DIR)/play-by-play
	pip3 install -r $(PLAY_BY_PLAY_SRC)/requirements.txt \
		-t $(BUILD_DIR)/play-by-play \
		--platform manylinux2014_aarch64 \
		--implementation cp \
		--python-version 312 \
		--only-binary=:all: \
		--quiet
	cp $(PLAY_BY_PLAY_SRC)/*.py $(BUILD_DIR)/play-by-play/
	cd $(BUILD_DIR)/play-by-play && zip -r ../play-by-play.zip . -x "*.pyc" -x "*/__pycache__/*"

# ── local (LocalStack) ──────────────────────────────────────────────────────
.PHONY: local-init local-plan local-apply local-destroy

local-init:
	$(TF) init -reconfigure -backend-config=backends/local.hcl

local-plan: local-init
	$(TF) plan -var-file=local.tfvars

local-apply: local-init
	$(TF) apply -var-file=local.tfvars

local-destroy: local-init
	$(TF) destroy -var-file=local.tfvars

# ── prod (real AWS) ─────────────────────────────────────────────────────────
.PHONY: prod-init prod-plan prod-apply prod-destroy

prod-init:
	$(TF) init -reconfigure -backend-config=backends/prod.hcl

prod-import-bucket: prod-init
	$(TF) import -var-file=prod.tfvars aws_s3_bucket.data_lake baseball-datalake-217412666418

prod-plan: prod-init build
	$(TF) plan -var-file=prod.tfvars

prod-apply: prod-init build
	$(TF) apply -var-file=prod.tfvars

prod-destroy: prod-init
	$(TF) destroy -var-file=prod.tfvars
