TESTS_INIT=tests/minimal_init.lua
TESTS_DIR=tests/

.PHONY: help test lint lint-luacheck format fmt-check ci test-release check-env clean coverage coverage-deps

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

coverage-deps: ## Install luacov (one-time, per-user via luarocks)
	@command -v luarocks >/dev/null 2>&1 || { echo "luarocks not found. Install via Homebrew: brew install luarocks"; exit 1; }
	luarocks install --local luacov

coverage: ## Run tests with luacov and print report (requires coverage-deps)
	@command -v luarocks >/dev/null 2>&1 || { echo "luarocks not found"; exit 1; }
	@rm -f luacov.stats.out luacov.report.out .luacov.stats.*.out
	@eval "$$(luarocks --local path)" && \
		export PATH="$$HOME/.luarocks/bin:$$PATH" && \
		command -v luacov >/dev/null 2>&1 || { echo "luacov not found. Run: make coverage-deps"; exit 1; } ; \
		NYAN_COVERAGE=1 LUA_PATH="$$LUA_PATH" LUA_CPATH="$$LUA_CPATH" $(MAKE) test && \
		nvim --headless --noplugin -u NONE -l scripts/luacov_merge.lua && \
		luacov && \
		echo "" && awk '/^Summary$$/,0' luacov.report.out

clean: ## Remove cache directories
	rm -rf .stylua-cache luacov.stats.out luacov.report.out .luacov.stats.*.out
