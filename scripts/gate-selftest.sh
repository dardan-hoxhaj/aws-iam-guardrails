#!/usr/bin/env bash
# Proves the security gate works: checkov MUST fail on tests/gate-fixtures/risky-iam,
# and must fail for the expected checks. Runs from inside the fixture folder so the
# repo's .checkov.yaml (which skips this folder) is not picked up.
set -uo pipefail

cd "$(dirname "$0")/../tests/gate-fixtures/risky-iam" || exit 1

output="$(checkov -d . --framework terraform --compact --quiet 2>/dev/null)"
status=$?

if [ "$status" -eq 0 ]; then
  echo "FAIL: checkov passed the risky IAM fixture. The security gate is broken."
  exit 1
fi

for check in CKV_AWS_1 CKV_AWS_393; do
  if ! grep -q "$check:" <<<"$output"; then
    echo "FAIL: expected checkov to report $check on the risky fixture."
    exit 1
  fi
done

echo "OK: checkov blocks the risky fixture (admin *:* policy and an OIDC trust open to any repo)."
