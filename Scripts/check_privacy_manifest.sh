#!/usr/bin/env bash

set -euo pipefail

module_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$module_root/Sources/BroadCore/Resources/PrivacyInfo.xcprivacy"

if [[ ! -f "$manifest" ]]; then
    echo "BroadCore privacy manifest is missing."
    exit 1
fi

plutil -lint "$manifest" >/dev/null
manifest_json="$(plutil -convert json -o - "$manifest")"
if ! MANIFEST_JSON="$manifest_json" /usr/bin/ruby -rjson -e '
  manifest = JSON.parse(ENV.fetch("MANIFEST_JSON"))
  abort "tracking must be false" unless manifest["NSPrivacyTracking"] == false
  abort "tracking domains must be empty" unless manifest["NSPrivacyTrackingDomains"] == []
  abort "collected data must be empty" unless manifest["NSPrivacyCollectedDataTypes"] == []
  entries = manifest["NSPrivacyAccessedAPITypes"]
  abort "one accessed API entry is required" unless entries.is_a?(Array) && entries.length == 1
  entry = entries.first
  abort "UserDefaults category is required" unless entry["NSPrivacyAccessedAPIType"] == "NSPrivacyAccessedAPICategoryUserDefaults"
  reasons = entry["NSPrivacyAccessedAPITypeReasons"]
  abort "approved reasons differ" unless reasons.sort == ["1C8F.1", "CA92.1"]
'; then
    echo "BroadCore privacy manifest semantic contract failed."
    exit 1
fi

if (($# > 0)); then
    built_app="$1"
    if [[ ! -d "$built_app" ]]; then
        echo "Built sandbox app is missing: $built_app"
        exit 1
    fi
    bundled_candidates=()
    while IFS= read -r -d '' candidate; do
        bundle_name="$(basename "$(dirname "$candidate")")"
        if [[ "$bundle_name" == *_BroadCore.bundle ]]; then
            bundled_candidates+=("$candidate")
        fi
    done < <(find "$built_app" -type f -name PrivacyInfo.xcprivacy -print0)

    if ((${#bundled_candidates[@]} != 1)); then
        echo "Built app must contain exactly one BroadCore privacy manifest."
        exit 1
    fi
    bundled_json="$(plutil -convert json -o - "${bundled_candidates[0]}")"
    if [[ "$bundled_json" != "$manifest_json" ]]; then
        echo "Bundled BroadCore privacy manifest differs from source."
        exit 1
    fi
    echo "BroadCore privacy manifest is valid and bundled."
else
    echo "BroadCore privacy manifest source contract passed."
fi
