# ArchWork
#
# check runs in CI. The vm-* targets need nested virtualisation and run locally.
# Record vm-* results in docs/STATUS.yml with a commit SHA.

SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := check

SHELL_SCRIPTS := $(shell find . -name '*.sh' -not -path './.git/*' 2>/dev/null)

.PHONY: check lint tracking shellcheck yamllint ansible-lint unit vm-idempotence vm-rebuild vm-health vm-recovery help

## check: L0 lint plus the plan/status cross-check
check: tracking lint

## tracking: prove STATUS.yml agrees with plan.md and the decision log
tracking:
	python3 scripts/check-plan-status.py

## lint: L0
lint: shellcheck yamllint ansible-lint

shellcheck:
	@if [ -z "$(SHELL_SCRIPTS)" ]; then echo "shellcheck: no shell scripts yet"; \
	else shellcheck $(SHELL_SCRIPTS); fi

yamllint:
	yamllint docs/STATUS.yml $(wildcard ansible)

ansible-lint:
	@if [ -d ansible ]; then ansible-lint; else echo "ansible-lint: no ansible/ yet"; fi

## unit: L1
unit:
	@if [ -d tests/unit ]; then bats tests/unit; else echo "unit: no tests/unit yet"; fi

# L2 to L5 need a VM. CI cannot run these, and no CI job should pretend to.
vm-idempotence vm-rebuild vm-health vm-recovery:
	@echo "$@ is not implemented yet. See docs/plan.md for which milestone delivers it."
	@exit 1

help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## //'
