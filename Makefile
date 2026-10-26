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

## verify-java: check every pinned library is loadable by the image JVM
.PHONY: verify-java
verify-java:
	$(REPO_ROOT)/scripts/check-java-requirement.py

## libs: download and SHA-512 verify the pinned Flink libraries
.PHONY: libs
libs:
	$(REPO_ROOT)/scripts/download-flink-libs.sh

# Internal guard, not listed in `make help`: fails with an actionable message
# instead of letting every docker-dependent target print a socket traceback.
.PHONY: docker-ready
docker-ready:
	@docker info >/dev/null 2>&1 || { \
	  echo "ERROR: the Docker daemon is not reachable."; \
	  echo "       On macOS start it with: open -a Docker"; \
	  echo "       Then wait until it answers: docker info"; \
	  exit 1; }

## build: build the Flink image once, so up and pipeline never race on it
.PHONY: build
build: docker-ready | env libs
	$(COMPOSE) build

## up: start the local stack in the background
.PHONY: up
up: build
	$(COMPOSE) up -d --remove-orphans

## down: stop the stack, keeping volumes and data
.PHONY: down
down: docker-ready | env
	$(COMPOSE) down --remove-orphans

## doctor: dump everything needed to diagnose a stack that will not come up
.PHONY: doctor
doctor:
	$(REPO_ROOT)/scripts/diagnose-stack.sh

## ps: show container status and health
.PHONY: ps
ps: docker-ready | env
	$(COMPOSE) ps

## verify-cdc: prove the PostgreSQL -> Kafka CDC slice end to end
.PHONY: verify-cdc
verify-cdc: docker-ready | env
	$(REPO_ROOT)/scripts/verify-ecommerce-cdc.sh

## jobs: list Flink jobs and warn when the pipeline was submitted twice
.PHONY: jobs
jobs: docker-ready | env
	$(REPO_ROOT)/scripts/flink-jobs.py --env-file $(ENV_FILE)

## cancel-jobs: cancel every job on the cluster
.PHONY: cancel-jobs
cancel-jobs: docker-ready | env
	$(REPO_ROOT)/scripts/flink-jobs.py --env-file $(ENV_FILE) --cancel-all

## verify-stream: check the submitted job is running, checkpointing and writing
.PHONY: verify-stream
verify-stream: docker-ready | env
	$(REPO_ROOT)/scripts/verify-streaming.sh

## psql: open a psql shell against the source database
.PHONY: psql
psql: docker-ready | env
	$(COMPOSE) exec postgres psql -U "$${POSTGRES_USER}" -d "$${POSTGRES_DB}"

## pipeline: submit the streaming job to the session cluster
.PHONY: pipeline
pipeline: build
	$(COMPOSE) run --rm pipeline-submit

## sql-client: open a Flink SQL Client shell on the job manager
.PHONY: sql-client
sql-client: docker-ready | env
	$(COMPOSE) exec flink-jobmanager ./bin/sql-client.sh -Drest.address=flink-jobmanager -Drest.port=8081

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
reset: docker-ready | env
	$(COMPOSE) down -v --remove-orphans

## help: list available targets
.PHONY: help
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  make /'
