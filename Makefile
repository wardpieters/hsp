.PHONY: init check fmt
PYTHON ?= python3
init:
	$(PYTHON) scripts/check.py init
check:
	$(PYTHON) scripts/check.py check
fmt:
	terraform fmt -recursive
