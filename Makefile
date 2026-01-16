TESTS_INIT=tests/minimal_init.lua
TESTS_DIR=tests/

.PHONY: test lint format ci

test:
	@nvim \
		--headless \
		--noplugin \
		-u ${TESTS_INIT} \
		-c "PlenaryBustedDirectory ${TESTS_DIR} { minimal_init = '${TESTS_INIT}' }"

lint:
	stylua --color always --check lua

format:
	stylua lua

ci: lint test
