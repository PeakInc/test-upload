#!/usr/bin/env bash
# Installs the peak CLI this action release pins (checksum verified) and puts it on PATH. With `run`, runs the tests
# through `peak tests run` (shard, failed-first, retry-flaky) and exits with their own code. Then runs `peak tests upload`
# with the job's OIDC token. A failed upload only warns: it never fails the job.
set -uo pipefail

VERSION=0.9.0

warn() { echo "::warning::$1"; }

# Runs the tests (when `run` is set) and returns their exit code; 0 without `run`.
tests_code=0
peak=""

install() {
  local os arch asset base dir expected actual
  case "$(uname -s)" in Linux) os=linux ;; Darwin) os=darwin ;; *) warn "The peak CLI runs on Linux and macOS runners only."; return 1 ;; esac
  case "$(uname -m)" in x86_64 | amd64) arch=x64 ;; aarch64 | arm64) arch=arm64 ;; *) warn "Unsupported CPU for the peak CLI: $(uname -m)."; return 1 ;; esac
  asset="peak-$VERSION-$os-$arch.tar.gz"
  base="https://github.com/PeakInc/homebrew-tap/releases/download/v$VERSION"
  dir="${RUNNER_TEMP:-/tmp}/peak-cli-$VERSION"
  mkdir -p "$dir"
  if [ ! -x "$dir/peak" ]; then
    curl -fsSL --retry 3 -o "$dir/$asset" "$base/$asset" || { warn "Could not download the peak CLI."; return 1; }
    curl -fsSL --retry 3 -o "$dir/SHA256SUMS" "$base/SHA256SUMS" || { warn "Could not download the peak CLI's checksums."; return 1; }
    expected=$(awk -v f="$asset" '$2 == f { print $1 }' "$dir/SHA256SUMS")
    if command -v sha256sum >/dev/null; then actual=$(sha256sum "$dir/$asset" | cut -d' ' -f1); else actual=$(shasum -a 256 "$dir/$asset" | cut -d' ' -f1); fi
    [ -n "$expected" ] && [ "$expected" = "$actual" ] || { warn "The peak CLI download does not match its published checksum."; return 1; }
    tar -xzf "$dir/$asset" -C "$dir" peak || { warn "Could not unpack the peak CLI."; return 1; }
  fi
  peak="$dir/peak"
  [ -n "${GITHUB_PATH:-}" ] && echo "$dir" >> "$GITHUB_PATH"
  return 0
}

is_true() { case "$1" in true | True | TRUE | 1 | yes) return 0 ;; *) return 1 ;; esac; }

install || peak=""

if [ -n "${INPUT_WORKING_DIRECTORY:-}" ]; then
  cd "$INPUT_WORKING_DIRECTORY" || { echo "::error::working-directory $INPUT_WORKING_DIRECTORY does not exist."; exit 1; }
fi

flags=()
[ -n "${INPUT_SHARD:-}" ] && flags+=(--shard "$INPUT_SHARD")
is_true "${INPUT_FAILED_FIRST:-}" && flags+=(--failed-first)
is_true "${INPUT_RETRY_FLAKY:-}" && flags+=(--retry-flaky)

if [ -n "${INPUT_RUN:-}" ]; then
  # One command (no new lines or shell operators) is split as bash would split it, so Peak can see the runner. Anything
  # else is a script: it runs as written, and Peak can't shard, order or retry it.
  script=0
  case "$INPUT_RUN" in *$'\n'* | *';'* | *'&'* | *'|'* | *'<'* | *'>'* | *'`'* | *'$('*) script=1 ;; esac
  if [ -z "$peak" ]; then
    warn "Running the tests without the peak CLI: no shard, failed-first or retry-flaky."
    bash --noprofile --norc -eo pipefail -c "$INPUT_RUN"
    tests_code=$?
  elif [ "$script" = 1 ]; then
    [ ${#flags[@]} -gt 0 ] && warn "run is a script, so Peak can't shard, order or retry it; it runs as written. Put the test command alone in run (setup in a step above, cd in working-directory)."
    bash --noprofile --norc -eo pipefail -c "$INPUT_RUN"
    tests_code=$?
  else
    eval "words=($INPUT_RUN)"
    "$peak" tests run "${flags[@]+"${flags[@]}"}" -- "${words[@]}"
    tests_code=$?
  fi
elif [ ${#flags[@]} -gt 0 ]; then
  warn "shard, failed-first and retry-flaky apply only with run."
fi

# Upload, even when the tests failed.
if [ -z "$peak" ]; then
  warn "Test results were not uploaded."
else
  # Split `files` on spaces and new lines, unexpanded: the CLI matches *, ? and ** itself (and the bash 3.2 that macOS
  # runners ship has no globstar).
  set -f
  read -r -d '' -a patterns < <(printf '%s\0' "${INPUT_FILES:-}") || true
  set +f
  if [ ${#patterns[@]} -eq 0 ]; then
    warn "files is empty. Test results were not uploaded."
  else
    args=(tests upload)
    [ -n "${INPUT_FRAMEWORK:-}" ] && args+=(--framework "$INPUT_FRAMEWORK")
    [ -n "${PEAK_JOB_ID:-}" ] || unset PEAK_JOB_ID
    "$peak" "${args[@]}" "${patterns[@]}" || warn "peak tests upload failed. Test results were not uploaded."
  fi
fi

exit "$tests_code"
