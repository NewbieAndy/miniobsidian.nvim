NVIM ?= nvim
PLENARY_DIR ?= $(HOME)/.local/share/nvim/lazy/plenary.nvim

.PHONY: test format-check lint fixture-check ci

test:
	MINIOBSIDIAN_ROOT=$(CURDIR) PLENARY_DIR=$(PLENARY_DIR) \
		$(NVIM) --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests { minimal_init = 'tests/minimal_init.lua' }" \
		-c qa

format-check:
	stylua --check lua plugin tests

lint:
	selene lua

fixture-check:
	./scripts/check-fixtures.sh

ci: format-check lint fixture-check test
