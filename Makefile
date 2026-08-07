NVIM ?= nvim
PLENARY_DIR ?= $(HOME)/.local/share/nvim/lazy/plenary.nvim

.PHONY: test format-check lint ci

test:
	MINIOBSIDIAN_ROOT=$(CURDIR) PLENARY_DIR=$(PLENARY_DIR) \
		$(NVIM) --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests { minimal_init = 'tests/minimal_init.lua' }" \
		-c qa

format-check:
	stylua --check lua plugin tests

lint:
	selene lua

ci: format-check lint test
