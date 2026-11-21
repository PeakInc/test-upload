#!/usr/bin/env bash
# Installs the peak CLI this action release pins (checksum verified) and puts it on PATH. With `run`, runs the tests
# through `peak tests run` (shard, failed-first, retry-flaky) and exits with their own code. Then runs `peak tests upload`
# for `files` and `peak coverage upload` for `coverage`, with the job's OIDC token. A failed upload only warns: it never
# fails the job.
set -uo pipefail

VERSION=0.10.0
# Each platform's sha256 for VERSION, from its release's SHA256SUMS and the tap's reviewed formula, pinned here so a
# replaced release asset can't pass the check. Update them with VERSION.
sha256_for() {
  case "$1" in
    linux-x64) echo 9d18330e8f64248858ac7615458520ae43b1b1b53da7506d237381231f6e90b0 ;;
    linux-arm64) echo ab95a057d35010af8dee99ec4ee19a8e9a913743fb437e3e098d819f71d55dd9 ;;
    darwin-x64) echo 21b9b7ad4a639221ed9c294bf4ba5e496b4ba3ff79d1a5499e651abb3624700d ;;
    darwin-arm64) echo 3014e50e2c7c2a443290704fd3d864a8cc9265906d5f788571cec0e0e101d004 ;;
  esac
}

warn() { echo "::warning::$1"; }
is_true() { case "$1" in true | True | TRUE | 1 | yes) return 0 ;; *) return 1 ;; esac; }

peak=""
dir="${RUNNER_TEMP:-/tmp}/peak-cli-$VERSION"
install() {
  local os arch asset base expected actual
  case "$(uname -s)" in Linux) os=linux ;; Darwin) os=darwin ;; *) warn "The peak CLI runs on Linux and macOS runners only."; return 1 ;; esac
  case "$(uname -m)" in x86_64 | amd64) arch=x64 ;; aarch64 | arm64) arch=arm64 ;; *) warn "Unsupported CPU for the peak CLI: $(uname -m)."; return 1 ;; esac
  asset="peak-$VERSION-$os-$arch.tar.gz"
  expected=$(sha256_for "$os-$arch")
  base="https://github.com/PeakInc/homebrew-tap/releases/download/v$VERSION"
  mkdir -p "$dir"
  if [ ! -x "$dir/peak" ]; then
    curl -fsSL --retry 3 -o "$dir/$asset" "$base/$asset" || { warn "Could not download the peak CLI."; return 1; }
    if command -v sha256sum >/dev/null; then actual=$(sha256sum "$dir/$asset" | cut -d' ' -f1); else actual=$(shasum -a 256 "$dir/$asset" | cut -d' ' -f1); fi
    [ -n "$expected" ] && [ "$expected" = "$actual" ] || { warn "The peak CLI download does not match the checksum this action pins."; return 1; }
    tar -xzf "$dir/$asset" -C "$dir" peak || { warn "Could not unpack the peak CLI."; return 1; }
  fi
  peak="$dir/peak"
  [ -n "${GITHUB_PATH:-}" ] && echo "$dir" >> "$GITHUB_PATH"
  return 0
}

install || peak=""

if [ -n "${INPUT_WORKING_DIRECTORY:-}" ]; then
  cd "$INPUT_WORKING_DIRECTORY" || { echo "::error::working-directory $INPUT_WORKING_DIRECTORY does not exist."; exit 1; }
fi

# The tests: their exit code is the step's.
tests_code=0
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

# The uploads, even when the tests failed. Split the inputs on spaces and new lines, unexpanded: the CLI matches *, ?
# and ** itself (and the bash 3.2 that macOS runners ship has no globstar).
set -f
read -r -d '' -a files < <(printf '%s\0' "${INPUT_FILES:-}") || true
read -r -d '' -a coverage < <(printf '%s\0' "${INPUT_COVERAGE:-}") || true
set +f

# Runs one upload. On failure the warning carries what the CLI said (Peak's error), on one line, with the characters
# GitHub reads in workflow commands escaped.
upload() {
  local what=$1 err="$dir/stderr" said
  shift
  if "$peak" "$@" 2>"$err"; then
    cat "$err" >&2
    return 0
  fi
  cat "$err" >&2
  said=$(tr '\r\n' '  ' <"$err" | sed -e 's/%/%25/g' -e 's/  */ /g' -e 's/ *$//' | cut -c1-500)
  warn "peak $what upload failed${said:+: $said}"
}

if [ ${#files[@]} -eq 0 ] && [ ${#coverage[@]} -eq 0 ]; then
  warn "Set files, coverage or both. Nothing was uploaded."
elif [ -z "$peak" ]; then
  warn "Nothing was uploaded."
else
  [ -n "${PEAK_JOB_ID:-}" ] || unset PEAK_JOB_ID
  # Each part warns on its own: a failed test upload still sends coverage.
  if [ ${#files[@]} -gt 0 ]; then
    args=(tests upload)
    [ -n "${INPUT_FRAMEWORK:-}" ] && args+=(--framework "$INPUT_FRAMEWORK")
    upload tests "${args[@]}" "${files[@]}"
  fi
  if [ ${#coverage[@]} -gt 0 ]; then
    upload coverage coverage upload "${coverage[@]}"
  fi
fi

exit "$tests_code"
