# ArchWork
#
# check runs in CI. The vm-* targets need nested virtualisation and run locally.
# Record vm-* results in docs/STATUS.yml with a commit SHA.

SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := check

# Shell scripts by extension, plus extensionless ones carrying a bash shebang
# (archwork-rollback is installed as a command, so it has no .sh suffix).
SHELL_SCRIPTS := $(shell find . -name '*.sh' -not -path './.git/*' 2>/dev/null) \
                 $(shell grep -rl '^#!/usr/bin/env bash' scripts tests 2>/dev/null | grep -v '\.sh$$')

.PHONY: check lint tracking shellcheck yamllint ansible-lint unit vm-idempotence vm-rebuild vm-health vm-recovery help

## check: L0 lint plus the plan/status cross-check
check: tracking lint unit

## tracking: prove STATUS.yml agrees with plan.md and the decision log
tracking:
	python3 scripts/check-plan-status.py

## lint: L0
lint: shellcheck yamllint ansible-lint

shellcheck:
	@if [ -z "$(SHELL_SCRIPTS)" ]; then echo "shellcheck: no shell scripts yet"; \
	else shellcheck -x $(SHELL_SCRIPTS); fi

yamllint:
	yamllint docs/STATUS.yml $(wildcard ansible)


# Gated on a playbook, not on the directory: ansible/ holds package manifests
# and kernel command line profiles before any playbook exists.
ansible-lint:
	@if [ -n "$$(find ansible -name '*.yml' -path '*play*' 2>/dev/null)" ] || [ -d ansible/roles ]; then \
		ansible-lint; \
	else echo "ansible-lint: no playbooks yet"; fi

## unit: L1
unit:
	@if [ -n "$$(ls tests/unit/*.bats 2>/dev/null)" ]; then bats tests/unit; \
	else echo "unit: no bats tests yet"; fi

## vm-rebuild: L3, needs QEMU and nested virtualisation. Pass ISO=/path/to.iso
vm-rebuild:
	@test -n "$(ISO)" || { echo "vm-rebuild needs ISO=/path/to/archlinux.iso"; exit 1; }
	tests/vm/run-install.sh --iso "$(ISO)" $(VM_ARGS)

## vm-idempotence: L2, install then reconcile twice. Pass ISO=/path/to.iso
vm-idempotence:
	@test -n "$(ISO)" || { echo "vm-idempotence needs ISO=/path/to/archlinux.iso"; exit 1; }
	tests/vm/run-install.sh --iso "$(ISO)" --reconcile $(VM_ARGS)

# L4 and L5 arrive with M5. CI cannot run these, and no CI job should pretend to.
vm-health vm-recovery:
	@echo "$@ is not implemented yet. See docs/plan.md for which milestone delivers it."
	@exit 1

help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## //'
