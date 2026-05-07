TESTS_INIT=tests/minimal_init.lua
TESTS_DIR=tests/

.PHONY: help test lint lint-luacheck format fmt-check ci test-release check-env clean

help: ## List available targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  %-16s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

test: ## Run plenary test suite under headless nvim
	@nvim \
		--headless \
		--noplugin \
		-u ${TESTS_INIT} \
		-c "PlenaryBustedDirectory ${TESTS_DIR} { minimal_init = '${TESTS_INIT}' }"

lint: ## Check formatting with stylua
	stylua --color always --check lua

lint-luacheck: ## Run luacheck static analysis
	luacheck lua/ tests/

format: ## Apply stylua formatting
	stylua lua

fmt-check: lint ## Alias for lint (stylua check)

ci: lint lint-luacheck test ## Run full local CI parity (stylua + luacheck + tests)

test-release: ## Dry-run the release-please bump locally (no push, no tag)
	./scripts/test_release.sh

check-env: ## Verify gh CLI is authenticated
	@gh auth status >/dev/null 2>&1 || { echo "gh CLI not authenticated. Run: gh auth login"; exit 1; }
	@echo "gh CLI authenticated."

clean: ## Remove cache directories
	rm -rf .stylua-cache
