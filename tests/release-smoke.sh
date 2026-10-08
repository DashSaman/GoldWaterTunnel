#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../install.sh"
[[ "$WATERWALL_VERSION" == v1.46.96 ]]
[[ "$(select_release_asset 'sse2 avx aes')" == Waterwall-linux-gcc-x64-old-cpu.zip ]]
[[ "$(select_release_asset 'sse2 avx avx2 aes')" == Waterwall-linux-gcc-x64.zip ]]
[[ "$(select_release_asset 'sse2 avx2_fake')" == Waterwall-linux-gcc-x64-old-cpu.zip ]]
[[ "$(release_sha256 Waterwall-linux-gcc-x64.zip)" == 81311d5abc48f6ec4d417b16de1ad478d18d5ed19fc7ef64749b47e0a8099337 ]]
[[ "$(release_sha256 Waterwall-linux-gcc-x64-old-cpu.zip)" == 7774dfeb107d8e4e93471cb0964e016ce41ed6b78052948b12d41bef971b488b ]]
if (release_sha256 bogus >/dev/null 2>&1); then exit 1; fi
if (validate_instance_name '../other' >/dev/null 2>&1); then exit 1; fi
if (validate_instance_name '' >/dev/null 2>&1); then exit 1; fi
validate_instance_name 218
validate_instance_name de-backup
validate_instance_exec '{ path=/bin/example ; argv[]=/bin/example -c:/etc/example/core.json ; ignore_errors=no ; }' /bin/example /etc/example
if (validate_instance_exec '{ path=/bin/other ; argv[]=/bin/other ; }' /bin/example /etc/example >/dev/null 2>&1); then exit 1; fi
if (validate_instance_exec '{ path=/bin/example ; argv[]=/bin/example -c:/etc/example/core.json ; } { path=/bin/other ; }' /bin/example /etc/example >/dev/null 2>&1); then exit 1; fi

# A corrupted/offline archive must fail before an existing executable changes.
scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT
printf 'old binary sentinel\n' > "$scratch/existing"
printf 'corrupted release\n' > "$scratch/bad.zip"
export GWT_LOCAL_ARCHIVE="$scratch/bad.zip"
BIN="$scratch/existing"
if (install_binary >/dev/null 2>&1); then
  echo 'corrupt archive unexpectedly accepted' >&2; exit 1
fi
[[ "$(cat "$BIN")" == 'old binary sentinel' ]]
[[ ! -e "$BIN.new" ]]
unset GWT_LOCAL_ARCHIVE

# A well-formed archive with the wrong digest must not even execute its payload.
py=python3
"$py" -c 'import zipfile' >/dev/null 2>&1 || py=python
"$py" "$(dirname "$0")/make-wrong-digest.py" "$scratch/wrong-digest.zip"
export GWT_LOCAL_ARCHIVE="$scratch/wrong-digest.zip" GWT_TEST_MARKER="$scratch/payload-executed"
if (install_binary >/dev/null 2>&1); then echo 'wrong digest accepted' >&2; exit 1; fi
[[ ! -e "$GWT_TEST_MARKER" ]]
[[ "$(cat "$BIN")" == 'old binary sentinel' ]]
echo 'release smoke: PASS'
