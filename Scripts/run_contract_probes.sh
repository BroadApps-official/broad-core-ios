#!/usr/bin/env bash

set -euo pipefail

module_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
probe_directory="$module_root/.build/ContractProbes"
probe_binary="$probe_directory/BroadCorePolicyProbe"
storage_probe_binary="$probe_directory/BroadCoreStorageProbe"
logging_probe_binary="$probe_directory/BroadCoreLoggingProbe"

mkdir -p "$probe_directory"
xcrun swiftc \
    "$module_root/Sources/BroadCore/Domain/Policies/RetryPolicy.swift" \
    "$module_root/Sources/BroadCore/Domain/Policies/TimeoutPolicy.swift" \
    "$module_root/Sources/BroadCore/Domain/Cache/CachePolicy.swift" \
    "$module_root/Sources/BroadCore/Infrastructure/Networking/NetworkFailureClassifier.swift" \
    "$module_root/Scripts/ContractProbes/BroadCorePolicyProbe.swift" \
    -o "$probe_binary"
"$probe_binary"

xcrun swiftc \
    "$module_root/Sources/BroadCore/Application/Storage/KeyValueStoreProtocol.swift" \
    "$module_root/Sources/BroadCore/Infrastructure/Persistence/FileSystemKeyValueStore.swift" \
    "$module_root/Scripts/ContractProbes/BroadCoreStorageProbe.swift" \
    -o "$storage_probe_binary"
"$storage_probe_binary"

xcrun swiftc \
    "$module_root/Sources/BroadCore/Domain/Errors/AppError.swift" \
    "$module_root/Sources/BroadCore/Domain/Logging/BroadLogEvent.swift" \
    "$module_root/Sources/BroadCore/Domain/Logging/BroadLoggerProtocol.swift" \
    "$module_root/Sources/BroadCore/Infrastructure/Logging/BroadLogEventFormatter.swift" \
    "$module_root/Sources/BroadCore/Infrastructure/Logging/BroadSupportLogRecorder.swift" \
    "$module_root/Sources/BroadCore/Infrastructure/Logging/CompositeBroadLogger.swift" \
    "$module_root/Sources/BroadCore/Infrastructure/Logging/NoOpBroadLogger.swift" \
    "$module_root/Scripts/ContractProbes/BroadCoreLoggingProbe.swift" \
    -o "$logging_probe_binary"
"$logging_probe_binary"

echo "BroadCore policy, network, file-storage and logging contract probes passed."
