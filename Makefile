.PHONY: init check fmt
init:
	python3 scripts/check.py init
check:
	python3 scripts/check.py check
fmt:
	terraform fmt -recursive
