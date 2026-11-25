#!/usr/bin/env bash
# Mutation checks for manifest-sync detectors.
# Copy the repo to a temp worktree, patch the copy only, never write real src/.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REAL_SRC="${ROOT}/src/rules/manifest_sync.jl"
export JULIA_COLOR=no

# id|expected testset label (must match test/test_manifest_sync.jl)
MUTATIONS=(
  "manifest_format|detector: manifest_format unsupported"
  "manifest_top_level|detector: unexpected manifest top-level key"
  "project_deps_in_manifest|detector: project deps missing from manifest"
  "project_dep_uuid|detector: project deps UUID mismatch"
  "manifest_internal_closure|detector: manifest internal deps closure"
  "uuid_uniqueness|detector: manifest UUID uniqueness"
  "manifest_version_filename|detector: Manifest-v filename vs julia_version"
  "project_hash_diff|detector: diff mode stale project_hash"
  "extensions|detector: undeclared extension trigger"
  "sources_warn|detector: sources path disagree (warn)"
  "subproject_manifests|detector: workspace subproject manifest (warn)"
  "orphan_tracked_manifests|detector: tracked manifest without tracked Project.toml"
)

WORK="$(mktemp -d)"
cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT

cp -R "${ROOT}/." "${WORK}/"
SRC="${WORK}/src/rules/manifest_sync.jl"
cp "$SRC" "${WORK}/manifest_sync.jl.bak"
JULIA=(julia --startup-file=no --color=no --project="${WORK}")

assert_real_src_clean() {
  local status
  status="$(git -C "${ROOT}" status --porcelain -- src || true)"
  if [[ -n "${status}" ]]; then
    echo "MUTATION FAIL: real src/ is dirty:" >&2
    echo "${status}" >&2
    exit 1
  fi
}

strip_ansi() {
  sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g'
}

testset_failed_in_log() {
  local log="$1"
  local testset="$2"
  strip_ansi <"$log" | grep -F "$testset" | grep -v 'Test Failed at' | grep -E '\|[[:space:]]*[0-9]+[[:space:]]+[1-9][0-9]*' >/dev/null
}

log_has_load_or_syntax_error() {
  local log="$1"
  strip_ansi <"$log" | grep -qE 'ParseError during|^syntax: error' && return 0
  strip_ansi <"$log" | grep 'ERROR: LoadError' | grep -vq 'Some tests did not pass' && return 0
  return 1
}

run_manifest_tests() {
  "${JULIA[@]}" -e "using Test, AgentRuleLint; const ROOT=\"${WORK}\"; include(joinpath(\"${WORK}\", \"test\", \"test_manifest_sync.jl\"))"
}

smoke_load() {
  "${JULIA[@]}" -e 'using AgentRuleLint' >/dev/null
}

apply_mutation() {
  local id="$1"
  cp "${WORK}/manifest_sync.jl.bak" "$SRC"
  case "$id" in
    manifest_format)
      sed -i 's/^    fmt_ver = _check_manifest_format!(.*)$/    fmt_ver = nothing # mutation/' "$SRC"
      ;;
    manifest_top_level)
      sed -i 's/^    if fmt_ver !== nothing$/    if false # mutation/' "$SRC"
      ;;
    project_deps_in_manifest)
      sed -i '/^function _check_project_deps_in_manifest!/,/^    for (pkg, want_uuid) in sort(collect(wanted))$/{
        /^    for (pkg, want_uuid)/i\    return nothing # mutation
      }' "$SRC"
      ;;
    project_dep_uuid)
      sed -i 's/^        got == want_uuid && continue$/        continue # mutation/' "$SRC"
      ;;
    manifest_internal_closure)
      sed -i 's/^    _check_manifest_internal_closure!(.*)$/    nothing # mutation/' "$SRC"
      ;;
    uuid_uniqueness)
      sed -i 's/^    _check_uuid_uniqueness!(.*)$/    nothing # mutation/' "$SRC"
      ;;
    manifest_version_filename)
      sed -i 's/^    _check_manifest_version_filename!(.*)$/    nothing # mutation/' "$SRC"
      ;;
    project_hash_diff)
      sed -i 's/^    diff_base !== nothing && _check_project_hash_diff!(.*)$/    nothing # mutation/' "$SRC"
      ;;
    extensions)
      sed -i 's/^        _check_extensions!(diags, level, rel, sub_proj, sub_text, intent, do_not)$/        nothing # mutation/' "$SRC"
      ;;
    sources_warn)
      sed -i 's/^    _check_sources_warn!(.*)$/    nothing # mutation/' "$SRC"
      ;;
    subproject_manifests)
      sed -i 's/^    _warn_subproject_manifests!(.*)$/    nothing # mutation/' "$SRC"
      ;;
    orphan_tracked_manifests)
      sed -i 's/^    _report_orphan_tracked_manifests!(.*)$/    nothing # mutation/' "$SRC"
      ;;
    *)
      echo "unknown mutation id: $id" >&2
      return 1
      ;;
  esac
}

assert_real_src_clean

for entry in "${MUTATIONS[@]}"; do
  id="${entry%%|*}"
  testset="${entry#*|}"
  apply_mutation "$id"
  if cmp -s "$SRC" "${WORK}/manifest_sync.jl.bak"; then
    echo "MUTATION FAIL: source unchanged after mutation ${id}" >&2
    exit 1
  fi
  if ! cmp -s "$REAL_SRC" "${WORK}/manifest_sync.jl.bak"; then
    echo "MUTATION FAIL: real src dirty during ${id}" >&2
    exit 1
  fi
  assert_real_src_clean
  set +e
  smoke_load 2>"${WORK}/load.err"
  load_status=$?
  set -e
  if [[ $load_status -ne 0 ]]; then
    echo "MUTATION FAIL: ${id} produced load/precompile error" >&2
    cat "${WORK}/load.err" >&2
    exit 1
  fi
  log="$(mktemp)"
  set +e
  run_manifest_tests >"$log" 2>&1
  status=$?
  set -e
  if log_has_load_or_syntax_error "$log"; then
    echo "MUTATION FAIL: ${id} produced load/syntax error in tests" >&2
    tail -40 "$log" >&2
    rm -f "$log"
    exit 1
  fi
  if ! testset_failed_in_log "$log" "$testset"; then
    echo "MUTATION FAIL: ${id} did not fail testset '${testset}' (exit=${status})" >&2
    grep -F "$testset" "$log" >&2 || tail -30 "$log" >&2
    rm -f "$log"
    exit 1
  fi
  rm -f "$log"
  assert_real_src_clean
  echo "MUTATION OK: ${id} -> '${testset}' failed as expected"
done

assert_real_src_clean
echo "All mutation checks passed."
