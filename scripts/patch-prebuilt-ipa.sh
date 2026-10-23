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

# Theos emits jailbreak-targeted install names, while cyan normally rewrites
# them for sideloading. Replacing an already-injected .dylib bypassed cyan's
# dependency fix and caused dyld to look for /Library/Frameworks/CydiaSubstrate
# on a stock iPhone. Reproduce cyan's rewrite for the replacement binary.
command -v otool >/dev/null || { echo "otool is required (macOS runner)" >&2; exit 1; }
command -v install_name_tool >/dev/null || { echo "install_name_tool is required" >&2; exit 1; }
substrate_dependency="$(otool -L "$existing_dylib" | awk '/CydiaSubstrate|libsubstrate/ { print $1; exit }')"
bundled_substrate="@rpath/CydiaSubstrate.framework/CydiaSubstrate"

if [[ -n "$substrate_dependency" && "$substrate_dependency" != "$bundled_substrate" ]]; then
  echo "Fixing Substrate linkage: $substrate_dependency -> $bundled_substrate"
  # Homebrew's ldid does NOT support "-R" (it exits with code 1).
  # On macOS, codesign can remove an existing signature before Mach-O editing.
  # The IPA must still be re-signed after modification.
  if codesign -dv "$existing_dylib" >/dev/null 2>&1; then
    codesign --remove-signature "$existing_dylib"
  fi
  install_name_tool -change "$substrate_dependency" "$bundled_substrate" "$existing_dylib"
fi

if otool -L "$existing_dylib" | grep -F '/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate' >/dev/null; then
  echo "ERROR: replacement still links to the jailbreak-only Substrate path" >&2
  exit 1
fi

if [[ -n "$substrate_dependency" ]]; then
  # Make sure @rpath/CydiaSubstrate.framework/CydiaSubstrate is actually
  # inside the IPA. cyan installs it automatically while injecting .dylibs.
  app_frameworks="$(dirname "$existing_dylib")"
  bundled_framework="$app_frameworks/CydiaSubstrate.framework"
  if [[ ! -s "$bundled_framework/CydiaSubstrate" ]]; then
    echo "Bundled Substrate is absent; copying cyan's sideload-compatible version."
    cyan_framework="$(python3 -c 'from cyan.tbhtypes.executable import Executable; print(Executable.install_dir + "/extras/CydiaSubstrate.framework")')"
    [[ -s "$cyan_framework/CydiaSubstrate" ]] || {
      echo "ERROR: cyan's bundled Substrate dependency is missing." >&2
      exit 1
    }
    rm -rf "$bundled_framework"
    cp -R "$cyan_framework" "$bundled_framework"
  fi

  app_dir="$(find "$scratch/Payload" -mindepth 1 -maxdepth 1 -type d -name '*.app' -print -quit)"
  [[ -n "$app_dir" ]] || { echo "Missing .app bundle" >&2; exit 1; }
  app_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_dir/Info.plist")"
  if ! otool -l "$app_dir/$app_executable" | grep -F '@executable_path/Frameworks' >/dev/null; then
    echo "Adding missing Frameworks rpath to the application executable."
    install_name_tool -add_rpath '@executable_path/Frameworks' "$app_dir/$app_executable"
  fi

  # Fail fast instead of publishing another IPA that crashes at launch.
  otool -L "$existing_dylib" | grep -F "$bundled_substrate" >/dev/null || {
    echo "ERROR: Substrate linkage could not be changed to the app-bundled path." >&2
    exit 1
  }
  echo "Substrate dependency and bundled framework verified."
fi

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
