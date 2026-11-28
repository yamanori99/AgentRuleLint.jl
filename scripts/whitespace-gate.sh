#!/usr/bin/env bash
# Trailing-newline audit on all tracked text files and git diff --check on a commit range.
#
#   ./scripts/whitespace-gate.sh
#   WHITESPACE_GATE_DIFF_RANGE='origin/main...HEAD' ./scripts/whitespace-gate.sh
#
# Range rule (WHITESPACE_GATE_DIFF_RANGE overrides):
#   pull_request CI: origin/${GITHUB_BASE_REF}...HEAD (PR commits vs merge-base)
#   push CI: ${GITHUB_BEFORE}..${GITHUB_SHA} when before is not the empty sha
#   otherwise: origin/main...HEAD when origin/main exists, else HEAD~1..HEAD
#
# Binary paths are skipped using git's numstat/git-grep -I heuristics (no extension list).
set -euo pipefail

root="${WHITESPACE_GATE_REPO:-$(
  cd "$(dirname "$0")/.." && pwd
)}"
cd "$root"

# Explicit path exclusions: one entry per line as path<TAB>reason (no globs).
# shellcheck disable=SC2034
declare -a EXCLUSIONS=()

declare -a NEWLINE_FAILURES=()
DIFF_CHECK_RANGE=""

is_excluded() {
  local f="$1"
  local entry
  for entry in "${EXCLUSIONS[@]}"; do
    [[ "${entry%%$'\t'*}" == "$f" ]] && return 0
  done
  return 1
}

is_binary_tracked() {
  local f="$1"
  local ns
  ns="$(git diff --numstat HEAD -- "$f" 2>/dev/null | head -1 || true)"
  [[ -n "$ns" && "$ns" == -* ]]
}

is_text_tracked() {
  local f="$1"
  is_binary_tracked "$f" && return 1
  git grep -I -q . -- "$f" 2>/dev/null && return 0
  git grep -I -q '^' -- "$f" 2>/dev/null && return 0
  local sz
  sz="$(git cat-file -s "HEAD:$f" 2>/dev/null || echo 1)"
  [[ "${sz}" -eq 0 ]]
}

audit_trailing_newline() {
  local f path size last_oct last_two_oct
  while IFS= read -r -d '' f; do
    is_excluded "$f" && continue
    is_text_tracked "$f" || continue
    path="${root}/${f}"
    [[ -f "$path" ]] || continue
    size="$(wc -c <"${path}" | tr -d ' ')"
    if [[ "${size}" -eq 0 ]]; then
      NEWLINE_FAILURES+=("empty text file (expected a single trailing newline): ${f}")
      continue
    fi
    # Do not use $(tail -c 1): command substitution strips a trailing newline on macOS.
    last_oct="$(tail -c 1 "${path}" | od -An -tu1 | tr -d ' [:space:]')"
    if [[ -z "${last_oct}" ]] || [[ "${last_oct}" != "10" ]]; then
      NEWLINE_FAILURES+=("missing final newline: ${f}")
      continue
    fi
    last_two_oct="$(tail -c 2 "${path}" | od -An -tu1 | tr -d ' [:space:]')"
    if [[ "${last_two_oct}" == "1010" ]]; then
      NEWLINE_FAILURES+=("multiple trailing newlines: ${f}")
    fi
  done < <(git ls-files -z)
}

choose_diff_range() {
  if [[ -n "${WHITESPACE_GATE_DIFF_RANGE:-}" ]]; then
    DIFF_CHECK_RANGE="${WHITESPACE_GATE_DIFF_RANGE}"
    return 0
  fi
  if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" && -n "${GITHUB_BASE_REF:-}" ]]; then
    git fetch origin "${GITHUB_BASE_REF}" --no-tags 2>/dev/null || true
    DIFF_CHECK_RANGE="origin/${GITHUB_BASE_REF}...HEAD"
    return 0
  fi
  if [[ "${GITHUB_EVENT_NAME:-}" == "push" && -n "${GITHUB_BEFORE:-}" ]]; then
    if [[ "${GITHUB_BEFORE}" != "0000000000000000000000000000000000000000" ]]; then
      DIFF_CHECK_RANGE="${GITHUB_BEFORE}..${GITHUB_SHA:-HEAD}"
      return 0
    fi
  fi
  if git rev-parse --verify origin/main >/dev/null 2>&1; then
    DIFF_CHECK_RANGE="origin/main...HEAD"
    return 0
  fi
  if git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
    DIFF_CHECK_RANGE="HEAD~1..HEAD"
    return 0
  fi
  DIFF_CHECK_RANGE=""
}

run_diff_check() {
  choose_diff_range
  echo "whitespace-gate: git diff --check range: ${DIFF_CHECK_RANGE:-<skipped (no parent)>}"
  [[ -n "${DIFF_CHECK_RANGE}" ]] || return 0
  git diff --check "${DIFF_CHECK_RANGE}"
}

audit_trailing_newline

if ((${#NEWLINE_FAILURES[@]} > 0)); then
  echo "whitespace-gate: trailing newline audit failed (${#NEWLINE_FAILURES[@]} file(s)):" >&2
  printf '%s\n' "${NEWLINE_FAILURES[@]}" >&2
  exit 1
fi

run_diff_check
echo "whitespace-gate: ok"
