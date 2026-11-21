#!/usr/bin/env bash
# Installs the peak CLI this action release pins (checksum verified), then runs `peak tests upload` for `files` and
# `peak coverage upload` for `coverage`, with the job's OIDC token. A failed upload only warns: it never fails the job.
set -euo pipefail

VERSION=0.8.0

skip() {
  echo "::warning::$1 Nothing was uploaded."
  exit 0
}

# Split the inputs on spaces and new lines, unexpanded: the CLI matches *, ? and ** itself (and the bash 3.2 that macOS
# runners ship has no globstar).
set -f
read -r -d '' -a files < <(printf '%s\0' "${INPUT_FILES:-}") || true
read -r -d '' -a coverage < <(printf '%s\0' "${INPUT_COVERAGE:-}") || true
set +f
[ ${#files[@]} -gt 0 ] || [ ${#coverage[@]} -gt 0 ] || skip "Set files, coverage or both."

case "$(uname -s)" in Linux) os=linux ;; Darwin) os=darwin ;; *) skip "Runs on Linux and macOS runners only." ;; esac
case "$(uname -m)" in x86_64 | amd64) arch=x64 ;; aarch64 | arm64) arch=arm64 ;; *) skip "Unsupported CPU: $(uname -m)." ;; esac

asset="peak-$VERSION-$os-$arch.tar.gz"
base="https://github.com/PeakInc/homebrew-tap/releases/download/v$VERSION"
dir="${RUNNER_TEMP:-/tmp}/peak-cli-$VERSION"
mkdir -p "$dir"
if [ ! -x "$dir/peak" ]; then
  curl -fsSL --retry 3 -o "$dir/$asset" "$base/$asset" || skip "Could not download the peak CLI."
  curl -fsSL --retry 3 -o "$dir/SHA256SUMS" "$base/SHA256SUMS" || skip "Could not download the peak CLI's checksums."
  expected=$(awk -v f="$asset" '$2 == f { print $1 }' "$dir/SHA256SUMS")
  if command -v sha256sum >/dev/null; then actual=$(sha256sum "$dir/$asset" | cut -d' ' -f1); else actual=$(shasum -a 256 "$dir/$asset" | cut -d' ' -f1); fi
  [ -n "$expected" ] && [ "$expected" = "$actual" ] || skip "The peak CLI download does not match its published checksum."
  tar -xzf "$dir/$asset" -C "$dir" peak
fi

[ -n "${PEAK_JOB_ID:-}" ] || unset PEAK_JOB_ID

# Runs one upload. On failure the warning carries what the CLI said (Peak's error), on one line, with the characters
# GitHub reads in workflow commands escaped.
upload() {
  local what=$1 err="$dir/stderr" said
  shift
  if "$dir/peak" "$@" 2>"$err"; then
    cat "$err" >&2
    return 0
  fi
  cat "$err" >&2
  said=$(tr '\r\n' '  ' <"$err" | sed -e 's/%/%25/g' -e 's/  */ /g' -e 's/ *$//' | cut -c1-500)
  echo "::warning::peak $what upload failed${said:+: $said}"
}

# Each part warns on its own: a failed test upload still sends coverage, and the job never fails.
if [ ${#files[@]} -gt 0 ]; then
  args=(tests upload)
  [ -n "${INPUT_FRAMEWORK:-}" ] && args+=(--framework "$INPUT_FRAMEWORK")
  upload tests "${args[@]}" "${files[@]}"
fi
if [ ${#coverage[@]} -gt 0 ]; then
  upload coverage coverage upload "${coverage[@]}"
fi
exit 0
