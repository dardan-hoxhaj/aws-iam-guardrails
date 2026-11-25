# Run `make check` before pushing. It runs the same checks as CI.
STACKS  := bootstrap live
MODULES := $(wildcard modules/*)
TESTED  := bootstrap live modules/scps

.PHONY: check fmt lint validate test scan gate-selftest secrets

check: fmt lint validate test scan gate-selftest secrets

fmt:
	terraform fmt -check -recursive

lint:
	tflint --init --config=$(CURDIR)/.tflint.hcl
	tflint --recursive --config=$(CURDIR)/.tflint.hcl

validate:
	@for d in $(STACKS) $(MODULES); do \
	  echo "== validate $$d"; \
	  terraform -chdir=$$d init -backend=false -input=false >/dev/null && \
	  terraform -chdir=$$d validate || exit 1; \
	done

test:
	@for d in $(TESTED); do \
	  echo "== test $$d"; \
	  terraform -chdir=$$d init -backend=false -input=false >/dev/null && \
	  terraform -chdir=$$d test || exit 1; \
	done

scan:
	checkov --config-file .checkov.yaml

# The gate must FAIL on the deliberately risky fixture, for the right reasons:
# CKV_AWS_1 (admin "*:*" policy) and CKV_AWS_393 (OIDC trust open to any repo).
gate-selftest:
	./scripts/gate-selftest.sh

secrets:
	gitleaks git --redact --verbose .
