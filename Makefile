.PHONY: init check fmt
TF_DIRS := environments/home environments/host-config modules/platform_network modules/guest_network modules/vm modules/dns_records modules/service_vm modules/proxmox_host
TF_INIT_ARGS ?=
init:
	@set -e; for dir in $(TF_DIRS); do terraform -chdir=$$dir init -backend=false -input=false $(TF_INIT_ARGS); done
check:
	terraform fmt -check -recursive
	@set -e; for dir in $(TF_DIRS); do terraform -chdir=$$dir validate -no-color; terraform -chdir=$$dir test -no-color; done
	node --test tests/nesting-api.test.mjs
	node --test tests/lxc-config.test.mjs
fmt:
	terraform fmt -recursive
