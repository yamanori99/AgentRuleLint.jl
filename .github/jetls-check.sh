#!/usr/bin/env bash
# Entry files for `jetls check` (hint+). JetLS follows top-level `include()`.
#
#   ./.github/jetls-check.sh
#   ./.github/jetls-check.sh --print-files   # CI file list
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
shopt -s nullglob

# Package surface only: JETLS follows `include()` from here. Do not pass
# test/runtests.jl — its test-only deps (Aqua, Runic env) are absent from the
# JETLS app environment and produce toplevel errors.
files=(
    src/JAILint.jl
)

if ((${#files[@]} == 0)); then
    echo "jetls-check: no entry files matched" >&2
    exit 1
fi

print_files=false
jetls_args=()
for arg in "$@"; do
    if [[ "$arg" == "--print-files" ]]; then
        print_files=true
    else
        jetls_args+=("$arg")
    fi
done

if [[ "$print_files" == true ]]; then
    # Single line (space-separated) for GITHUB_OUTPUT in CI.
    printf '%s\n' "${files[*]}"
    exit 0
fi

if ! command -v jetls >/dev/null 2>&1; then
    echo "jetls-check: jetls not on PATH (install via Pkg.Apps or use CI jetls-check action)" >&2
    exit 1
fi

_log="$(mktemp)"
cleanup_log() { rm -f "${_log}"; }
trap cleanup_log EXIT
set +e
jetls check --root=. --exit-severity=hint --show-severity=hint "${jetls_args[@]}" "${files[@]}" >"${_log}" 2>&1
_status=$?
set -e
cat "${_log}"
"${root}/.github/jetls-log-gate.sh" "${_log}"
exit "${_status}"
