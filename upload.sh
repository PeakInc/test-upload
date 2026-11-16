#!/usr/bin/env bash
# Installs the peak CLI this action release pins (checksum verified) and runs `peak tests upload` with the job's OIDC
# token. A failed upload only warns: it never fails the job.
set -euo pipefail

VERSION=0.8.0

skip() {
  echo "::warning::$1 Test results were not uploaded."
  exit 0
}

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

# Split the input on spaces and new lines, unexpanded: the CLI matches *, ? and ** itself (and the bash 3.2 that macOS
# runners ship has no globstar).
set -f
read -r -d '' -a patterns < <(printf '%s\0' "$INPUT_FILES") || true
set +f
[ ${#patterns[@]} -gt 0 ] || skip "files is empty."

args=(tests upload)
[ -n "$INPUT_FRAMEWORK" ] && args+=(--framework "$INPUT_FRAMEWORK")
[ -n "$PEAK_JOB_ID" ] || unset PEAK_JOB_ID
"$dir/peak" "${args[@]}" "${patterns[@]}" || skip "peak tests upload failed."
