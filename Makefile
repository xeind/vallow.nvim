NVIM ?= nvim
ROOT := $(CURDIR)

.PHONY: test lint

test:
	cd $(ROOT)/tests/fixture && $(NVIM) --headless -u NONE -l $(ROOT)/tests/run.lua

lint:
	stylua --check lua
