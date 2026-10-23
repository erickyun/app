#!/usr/bin/env bash
set -Eeuo pipefail

# Replace only NeoFreeBird's tweak and its settings bundle in a prebuilt IPA.
# Usage: patch-prebuilt-ipa.sh input.ipa output.ipa BHTwitter.dylib BHTwitter.bundle

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 input.ipa output.ipa compiled/BHTwitter.dylib resources/BHTwitter.bundle" >&2
  exit 2
fi

base_ipa="$1"
output_ipa="$2"
new_dylib="$3"
new_bundle="$4"

[[ -s "$base_ipa" ]] || { echo "Missing or empty base IPA: $base_ipa" >&2; exit 1; }
[[ -s "$new_dylib" ]] || { echo "Missing built tweak: $new_dylib" >&2; exit 1; }
[[ -d "$new_bundle" ]] || { echo "Missing resources: $new_bundle" >&2; exit 1; }

# Convert input arguments to absolute paths before changing directories.
base_ipa="$(cd "$(dirname "$base_ipa")" && pwd)/$(basename "$base_ipa")"
output_dir="$(mkdir -p "$(dirname "$output_ipa")" && cd "$(dirname "$output_ipa")" && pwd)"
output_ipa="$output_dir/$(basename "$output_ipa")"
new_dylib="$(cd "$(dirname "$new_dylib")" && pwd)/$(basename "$new_dylib")"
new_bundle="$(cd "$(dirname "$new_bundle")" && pwd)/$(basename "$new_bundle")"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

unzip -q "$base_ipa" -d "$scratch"
[[ -d "$scratch/Payload" ]] || { echo "Invalid IPA: missing Payload/" >&2; exit 1; }

# Do not inject a second copy of NeoFreeBird into the already-tweaked IPA.
existing_dylib="$(find "$scratch/Payload" -type f -name BHTwitter.dylib -print -quit)"
if [[ -z "$existing_dylib" ]]; then
  echo "This IPA does not contain BHTwitter.dylib; refusing duplicate injection." >&2
  find "$scratch/Payload" -type f -name '*.dylib' -print >&2
  exit 1
fi
if [[ "$(find "$scratch/Payload" -type f -name BHTwitter.dylib | wc -l | tr -d ' ')" != 1 ]]; then
  echo "Multiple BHTwitter.dylib matches; refusing ambiguous replacement." >&2
  exit 1
fi

existing_bundle="$(find "$scratch/Payload" -type d -name BHTwitter.bundle -print -quit)"
if [[ -z "$existing_bundle" ]]; then
  echo "This IPA does not contain BHTwitter.bundle; refusing incomplete update." >&2
  exit 1
fi
if [[ "$(find "$scratch/Payload" -type d -name BHTwitter.bundle | wc -l | tr -d ' ')" != 1 ]]; then
  echo "Multiple BHTwitter.bundle matches; refusing ambiguous replacement." >&2
  exit 1
fi

echo "Updating tweak: $existing_dylib"
cp -f "$new_dylib" "$existing_dylib"
echo "Updating settings resources: $existing_bundle"
rm -rf "$existing_bundle"
cp -R "$new_bundle" "$existing_bundle"

# Keep all remaining IPA contents (including extensions and existing dylibs).
# The modified app MUST be re-signed with ESign or another signer.
rm -f "$output_ipa"
(
  cd "$scratch"
  zip -qry "$output_ipa" .
)
unzip -tq "$output_ipa" > /dev/null
echo "Created: $output_ipa"
echo "IMPORTANT: Re-sign this IPA before installing."
