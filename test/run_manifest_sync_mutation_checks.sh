#!/usr/bin/env bash
# Mutation checks for manifest-sync detectors (run from repo root).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/src/rules/manifest_sync.jl"
JULIA=(julia --startup-file=no --project="${ROOT}")

declare -A MAP=(
  ["_check_manifest_format!"]="detector: manifest_format unsupported"
  ["_check_manifest_top_level!"]="detector: unexpected manifest top-level key"
  ["_check_project_deps_in_manifest!"]="detector: project deps missing from manifest"
  ["_check_manifest_internal_closure!"]="detector: manifest internal deps closure"
  ["_check_uuid_uniqueness!"]="detector: manifest UUID uniqueness"
  ["_check_manifest_version_filename!"]="detector: Manifest-v filename vs julia_version"
  ["_check_project_hash_diff!"]="detector: diff mode stale project_hash"
  ["_check_extensions!"]="detector: undeclared extension trigger"
  ["_check_sources_warn!"]="detector: sources path disagree (warn)"
  ["_warn_subproject_manifests!"]="detector: workspace subproject manifest (warn)"
  ["_report_orphan_tracked_manifests!"]="detector: tracked manifest without tracked Project.toml"
)

tmpdir="$(mktemp -d)"
cp "$SRC" "${tmpdir}/manifest_sync.jl.bak"
cleanup() {
  cp "${tmpdir}/manifest_sync.jl.bak" "$SRC"
  rm -rf "$tmpdir"
}
trap cleanup EXIT

run_tests() {
  "${JULIA[@]}" -e "using Test, AgentRuleLint; include(joinpath(\"${ROOT}\", \"test\", \"runtests.jl\"))"
}

for fn in "${!MAP[@]}"; do
  testset="${MAP[$fn]}"
  cp "${tmpdir}/manifest_sync.jl.bak" "$SRC"
  sed -i "/^function ${fn}/! s/${fn}!/# MUTATION ${fn}!/g" "$SRC"
  if run_tests 2>/dev/null; then
    echo "MUTATION FAIL: disabling ${fn} did not break tests (expected failure for ${testset})"
    exit 1
  fi
  echo "MUTATION OK: ${fn} -> would break '${testset}'"
done

cp "${tmpdir}/manifest_sync.jl.bak" "$SRC"
sed -i 's/got == want_uuid && continue/continue  # MUTATION uuid/' "$SRC"
if run_tests 2>/dev/null; then
  echo "MUTATION FAIL: skipping UUID compare did not break tests (expected detector: project deps UUID mismatch)"
  exit 1
fi
echo "MUTATION OK: UUID compare -> would break 'detector: project deps UUID mismatch'"

echo "All mutation checks passed."