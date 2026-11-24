#!/usr/bin/env bash
# Mutation checks for manifest-sync detectors (src/rules/manifest_sync.jl only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/src/rules/manifest_sync.jl"
export JULIA_COLOR=no
JULIA=(julia --startup-file=no --color=no --project="${ROOT}")
DISABLED_LINE='const _MANIFEST_SYNC_DISABLED = Set{Symbol}()'

# symbol:expected testset label (must match test/test_manifest_sync.jl)
MUTATIONS=(
  "manifest_format:detector: manifest_format unsupported"
  "manifest_top_level:detector: unexpected manifest top-level key"
  "project_deps_in_manifest:detector: project deps missing from manifest"
  "project_dep_uuid:detector: project deps UUID mismatch"
  "manifest_internal_closure:detector: manifest internal deps closure"
  "uuid_uniqueness:detector: manifest UUID uniqueness"
  "manifest_version_filename:detector: Manifest-v filename vs julia_version"
  "project_hash_diff:detector: diff mode stale project_hash"
  "extensions:detector: undeclared extension trigger"
  "sources_warn:detector: sources path disagree (warn)"
  "subproject_manifests:detector: workspace subproject manifest (warn)"
  "orphan_tracked_manifests:detector: tracked manifest without tracked Project.toml"
)

tmpdir="$(mktemp -d)"
cp "$SRC" "${tmpdir}/manifest_sync.jl.bak"
cleanup() {
  cp "${tmpdir}/manifest_sync.jl.bak" "$SRC"
  rm -rf "$tmpdir"
}
trap cleanup EXIT

strip_ansi() {
  sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g'
}

testset_failed_in_log() {
  local log="$1"
  local testset="$2"
  # Summary row: "<testset> | <pass> <fail> ..." (fail must be > 0).
  strip_ansi <"$log" | grep -F "$testset" | grep -v 'Test Failed at' | grep -E '\|[[:space:]]*[0-9]+[[:space:]]+[1-9][0-9]*' >/dev/null
}

run_manifest_tests() {
  "${JULIA[@]}" -e "using Test, AgentRuleLint; const ROOT=\"${ROOT}\"; include(joinpath(\"${ROOT}\", \"test\", \"test_manifest_sync.jl\"))"
}

for entry in "${MUTATIONS[@]}"; do
  sym="${entry%%:*}"
  testset="${entry#*:}"
  cp "${tmpdir}/manifest_sync.jl.bak" "$SRC"
  repl="const _MANIFEST_SYNC_DISABLED = Set{Symbol}([:${sym}])"
  sed -i "s|^${DISABLED_LINE}\$|${repl}|" "$SRC"
  if cmp -s "$SRC" "${tmpdir}/manifest_sync.jl.bak"; then
    echo "MUTATION FAIL: source unchanged after disabling :${sym}" >&2
    exit 1
  fi
  log="$(mktemp)"
  set +e
  run_manifest_tests >"$log" 2>&1
  status=$?
  set -e
  if echo "$log" | grep -qE 'LoadError|ParseError during|syntax: '; then
    echo "MUTATION FAIL: :${sym} produced load/syntax error (not a targeted test failure)" >&2
    tail -40 "$log" >&2
    rm -f "$log"
    exit 1
  fi
  if ! testset_failed_in_log "$log" "$testset"; then
    echo "MUTATION FAIL: :${sym} did not fail testset '${testset}' (exit=${status})" >&2
    grep -F "$testset" "$log" >&2 || tail -30 "$log" >&2
    rm -f "$log"
    exit 1
  fi
  rm -f "$log"
  echo "MUTATION OK: :${sym} -> '${testset}' failed as expected"
done

echo "All mutation checks passed."
