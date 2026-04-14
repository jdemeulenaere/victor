#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-victor-dev}"
PROJECT_NUMBER="${PROJECT_NUMBER:-$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')}"
REGION="${REGION:-europe-west1}"
REPOSITORY="${REPOSITORY:-victor-dev}"
SERVICE="${SERVICE:-greeter-backend-dev}"
DEPLOYER="${DEPLOYER:-victor-deployer@${PROJECT_ID}.iam.gserviceaccount.com}"
RUNTIME_SA="${RUNTIME_SA:-${PROJECT_NUMBER}-compute@developer.gserviceaccount.com}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten="bindings[]" \
  --filter="bindings.members:serviceAccount:${DEPLOYER}" \
  --format="value(bindings.role)" \
  | sort -u > "$tmpdir/project_roles.txt"

cat > "$tmpdir/project_roles.expected" <<'EXPECTED_PROJECT_ROLES'
roles/firebaseappdistro.admin
roles/firebasehosting.admin
roles/serviceusage.apiKeysViewer
EXPECTED_PROJECT_ROLES

gcloud artifacts repositories get-iam-policy "$REPOSITORY" \
  --project="$PROJECT_ID" \
  --location="$REGION" \
  --format=json > "$tmpdir/repository_policy.json"

python3 - "$DEPLOYER" "$tmpdir/repository_policy.json" > "$tmpdir/repository_roles.txt" <<'PY'
import json
import sys

member = f"serviceAccount:{sys.argv[1]}"
with open(sys.argv[2], encoding="utf-8") as handle:
    policy = json.load(handle)
roles = sorted(
    binding["role"]
    for binding in policy.get("bindings", [])
    if member in binding.get("members", [])
)
for role in roles:
    print(role)
PY

printf '%s\n' "roles/artifactregistry.writer" > "$tmpdir/repository_roles.expected"

gcloud run services get-iam-policy "$SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --format=json > "$tmpdir/run_policy.json"

python3 - "$DEPLOYER" "$tmpdir/run_policy.json" > "$tmpdir/run_roles.txt" <<'PY'
import json
import sys

member = f"serviceAccount:{sys.argv[1]}"
with open(sys.argv[2], encoding="utf-8") as handle:
    policy = json.load(handle)
roles = sorted(
    binding["role"]
    for binding in policy.get("bindings", [])
    if member in binding.get("members", [])
)
for role in roles:
    print(role)
PY

printf '%s\n' "roles/run.developer" > "$tmpdir/run_roles.expected"

gcloud iam service-accounts get-iam-policy "$RUNTIME_SA" \
  --format=json > "$tmpdir/runtime_sa_policy.json"

python3 - "$DEPLOYER" "$tmpdir/runtime_sa_policy.json" > "$tmpdir/runtime_sa_roles.txt" <<'PY'
import json
import sys

member = f"serviceAccount:{sys.argv[1]}"
with open(sys.argv[2], encoding="utf-8") as handle:
    policy = json.load(handle)
roles = sorted(
    binding["role"]
    for binding in policy.get("bindings", [])
    if member in binding.get("members", [])
)
for role in roles:
    print(role)
PY

printf '%s\n' "roles/iam.serviceAccountUser" > "$tmpdir/runtime_sa_roles.expected"

diff -u "$tmpdir/project_roles.expected" "$tmpdir/project_roles.txt"
diff -u "$tmpdir/repository_roles.expected" "$tmpdir/repository_roles.txt"
diff -u "$tmpdir/run_roles.expected" "$tmpdir/run_roles.txt"
diff -u "$tmpdir/runtime_sa_roles.expected" "$tmpdir/runtime_sa_roles.txt"

echo "CI deployer permissions match the expected steady-state bindings."
