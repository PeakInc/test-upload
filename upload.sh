#!/usr/bin/env bash
# Installs the pinned peak CLI from its GitHub release (checksum verified) and runs `peak tests upload`.
set -euo pipefail

fail() {
  if [ "${INPUT_FAIL_ON_ERROR:-false}" = true ]; then echo "::error::$1"; exit 1; fi
  echo "::warning::$1 Test results were not uploaded."
  exit 0
}

version="${INPUT_VERSION#v}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must be like 0.8.0, not '$INPUT_VERSION'."
case "$(uname -s)" in Linux) os=linux ;; Darwin) os=darwin ;; *) fail "Runs on Linux and macOS runners only." ;; esac
case "$(uname -m)" in x86_64 | amd64) arch=x64 ;; aarch64 | arm64) arch=arm64 ;; *) fail "Unsupported CPU: $(uname -m)." ;; esac

asset="peak-$version-$os-$arch.tar.gz"
base="https://github.com/PeakInc/homebrew-tap/releases/download/v$version"
dir="${RUNNER_TEMP:-/tmp}/peak-cli-$version"
mkdir -p "$dir"
if [ ! -x "$dir/peak" ]; then
  curl -fsSL --retry 3 -o "$dir/$asset" "$base/$asset" || fail "Could not download the peak CLI $version ($asset)."
  curl -fsSL --retry 3 -o "$dir/SHA256SUMS" "$base/SHA256SUMS" || fail "Could not download the peak CLI's checksums."
  expected=$(awk -v f="$asset" '$2 == f { print $1 }' "$dir/SHA256SUMS")
  if command -v sha256sum >/dev/null; then actual=$(sha256sum "$dir/$asset" | cut -d' ' -f1); else actual=$(shasum -a 256 "$dir/$asset" | cut -d' ' -f1); fi
  [ -n "$expected" ] && [ "$expected" = "$actual" ] || fail "The peak CLI download does not match its published checksum."
  tar -xzf "$dir/$asset" -C "$dir" peak
fi

# Split the input on spaces and new lines, unexpanded: the CLI matches *, ? and ** itself (and the bash 3.2 that macOS
# runners ship has no globstar).
set -f
read -r -d '' -a patterns < <(printf '%s\0' "$INPUT_FILES") || true
set +f
[ ${#patterns[@]} -gt 0 ] || fail "files is empty."

echo "peak $version ($os-$arch) · ${#patterns[@]} pattern(s) · job id ${PEAK_JOB_ID:-none} · $([ -n "$PEAK_TOKEN" ] && echo token || echo OIDC)"
args=(tests upload)
[ -n "$INPUT_FRAMEWORK" ] && args+=(--framework "$INPUT_FRAMEWORK")
[ -n "$PEAK_TOKEN" ] || unset PEAK_TOKEN
[ -n "$PEAK_JOB_ID" ] || unset PEAK_JOB_ID
"$dir/peak" "${args[@]}" "${patterns[@]}" || fail "peak tests upload failed."
