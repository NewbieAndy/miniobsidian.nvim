NVIM ?= nvim
PLENARY_DIR ?= $(HOME)/.local/share/nvim/lazy/plenary.nvim

.PHONY: test format-check lint docs-check module-test-check ci

test:
	MINIOBSIDIAN_ROOT=$(CURDIR) PLENARY_DIR=$(PLENARY_DIR) \
		$(NVIM) --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests { minimal_init = 'tests/minimal_init.lua' }" \
		-c qa

format-check:
	stylua --check lua plugin tests

lint:
	selene lua

docs-check:
	NVIM=$(NVIM) sh scripts/check-docs.sh

module-test-check:
	sh scripts/check-module-tests.sh

ci: format-check lint docs-check module-test-check test
