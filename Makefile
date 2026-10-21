# Perpetua build and maintenance targets.
PREFIX  ?= $(HOME)/.local
VERSION := $(shell sed -n 's/^readonly VERSION="\(.*\)"/\1/p' bin/perpetua)
SHELLS  := bin/perpetua libexec/perpetua/session tests/fixtures/claude tests/fixtures/systemctl install.sh platform/vps/bootstrap.sh
BATS    ?= npx --yes bats@1.11.0
DIST    := dist/perpetua-$(VERSION)

.PHONY: help install uninstall test lint docs docs-serve dist clean version-check

help: ## Show this help
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

install: ## Install into PREFIX (default ~/.local)
	./install.sh --prefix "$(PREFIX)"

uninstall: ## Remove from PREFIX
	./install.sh --prefix "$(PREFIX)" --uninstall

test: ## Run the test suite
	$(BATS) tests/

lint: version-check ## Static analysis (shellcheck, python compile)
	shellcheck -x $(SHELLS)
	python3 -m py_compile libexec/perpetua/record.py

version-check: ## Fail if version strings disagree
	@test "$(VERSION)" = "$$(sed -n 's/^readonly PERPETUA_VERSION="\(.*\)"/\1/p' libexec/perpetua/session)" \
		|| { echo "version mismatch between bin/perpetua and libexec/perpetua/session"; exit 1; }

docs: ## Build the documentation site (strict)
	uvx --with mkdocs-material mkdocs build --strict

docs-serve: ## Serve the documentation locally
	uvx --with mkdocs-material mkdocs serve

dist: version-check ## Build the release tarball
	rm -rf $(DIST) && mkdir -p $(DIST)
	cp -R bin libexec share platform install.sh LICENSE NOTICE README.md README.fr.md CHANGELOG.md $(DIST)/
	tar -C dist -czf $(DIST).tar.gz perpetua-$(VERSION)
	rm -rf $(DIST)
	@echo "$(DIST).tar.gz"

clean: ## Remove build artefacts
	rm -rf dist site
