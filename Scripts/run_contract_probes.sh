#!/usr/bin/env bash

set -euo pipefail

module_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
probe_directory="$module_root/.build/ContractProbes"
probe_binary="$probe_directory/BroadCorePolicyProbe"

mkdir -p "$probe_directory"
xcrun swiftc \
    "$module_root/Sources/BroadCore/Domain/Policies/RetryPolicy.swift" \
    "$module_root/Sources/BroadCore/Domain/Policies/TimeoutPolicy.swift" \
    "$module_root/Sources/BroadCore/Domain/Cache/CachePolicy.swift" \
    "$module_root/Sources/BroadCore/Infrastructure/Networking/NetworkFailureClassifier.swift" \
    "$module_root/Scripts/ContractProbes/BroadCorePolicyProbe.swift" \
    -o "$probe_binary"
"$probe_binary"

echo "BroadCore policy and network contract probe passed."
