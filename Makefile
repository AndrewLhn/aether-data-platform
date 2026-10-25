# Aether Data Platform — local development entry points.
#
# Every target is non-interactive and idempotent, so CI and a human operator
# run exactly the same commands. Run `make help` for the list.

SHELL := /bin/bash
.DEFAULT_GOAL := help

REPO_ROOT   := $(shell pwd)
ENV_FILE    := $(REPO_ROOT)/.env
COMPOSE_FILE := $(REPO_ROOT)/infra/docker/docker-compose.yml
COMPOSE     := docker compose --env-file $(ENV_FILE) -f $(COMPOSE_FILE)

## env: create .env, or bring an existing one in line with .env.example
.PHONY: env
env:
	@$(REPO_ROOT)/scripts/sync-env.py --env-file $(ENV_FILE) --template $(REPO_ROOT)/.env.example

## verify-libs: re-download every pinned artifact and re-check its digest
.PHONY: verify-libs
verify-libs:
	$(REPO_ROOT)/scripts/check-flink-libs-lock.py --verify-downloads

## libs: download and SHA-512 verify the pinned Flink libraries
.PHONY: libs
libs:
	$(REPO_ROOT)/scripts/download-flink-libs.sh

## build: build the Flink image once, so up and pipeline never race on it
.PHONY: build
build: | env libs
	$(COMPOSE) build

## up: start the local stack in the background
.PHONY: up
up: build
	$(COMPOSE) up -d --remove-orphans

## down: stop the stack, keeping volumes and data
.PHONY: down
down: | env
	$(COMPOSE) down --remove-orphans

## doctor: dump everything needed to diagnose a stack that will not come up
.PHONY: doctor
doctor:
	$(REPO_ROOT)/scripts/diagnose-stack.sh

## ps: show container status and health
.PHONY: ps
ps: | env
	$(COMPOSE) ps

## verify-cdc: prove the PostgreSQL -> Kafka CDC slice end to end
.PHONY: verify-cdc
verify-cdc: | env
	$(REPO_ROOT)/scripts/verify-ecommerce-cdc.sh

## psql: open a psql shell against the source database
.PHONY: psql
psql: | env
	$(COMPOSE) exec postgres psql -U "$${POSTGRES_USER}" -d "$${POSTGRES_DB}"

## pipeline: submit the streaming job to the session cluster
.PHONY: pipeline
pipeline: build
	$(COMPOSE) run --rm pipeline-submit

## sql-client: open a Flink SQL Client shell on the job manager
.PHONY: sql-client
sql-client: | env
	$(COMPOSE) exec flink-jobmanager ./bin/sql-client.sh

## lint: run the same static checks that CI runs
.PHONY: lint
lint:
	$(REPO_ROOT)/scripts/check-compose-portability.sh
	$(REPO_ROOT)/scripts/check-flink-libs-lock.py
	@for f in $(REPO_ROOT)/scripts/*.sh; do bash -n "$$f" || exit 1; done
	@sh -n $(REPO_ROOT)/infra/docker/postgres/init/01-create-debezium-user.sh
	@node -e 'JSON.parse(require("fs").readFileSync("$(REPO_ROOT)/infra/docker/connectors/aether-postgres-cdc.json","utf8"))'
	@echo "Lint passed."

## reset: destroy all local state, including volumes (irreversible)
.PHONY: reset
reset: | env
	$(COMPOSE) down -v --remove-orphans

## help: list available targets
.PHONY: help
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  make /'
