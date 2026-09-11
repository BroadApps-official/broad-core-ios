#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
probe_directory="$(mktemp -d)"
trap 'rm -rf "$probe_directory"' EXIT

sources=(
    "$module_root/Sources/BroadCore/Domain/Errors/AppError.swift"
    "$module_root/Sources/BroadCore/Domain/Logging/BroadLogEvent.swift"
    "$module_root/Sources/BroadCore/Domain/Logging/BroadLogHostEvent.swift"
)

# Each boundary is checked separately so one expected diagnostic cannot hide
# an accidentally introduced runtime-String overload at another boundary.
for expression in \
    'BroadLogHostEvent(code: runtime)' \
    'BroadLogHostField(runtime, "READY")' \
    'BroadLogHostField(runtime, 1)' \
    'BroadLogHostField(runtime, true)' \
    'BroadLogHostField("status", runtime)'; do
    printf 'func runtimeStringBoundary(_ runtime: String) { _ = %s }\n' \
        "$expression" > "$probe_directory/RuntimeStringBoundary.swift"
    if xcrun swiftc -typecheck "${sources[@]}" \
        "$probe_directory/RuntimeStringBoundary.swift" \
        > "$probe_directory/diagnostics.log" 2>&1; then
        echo "Host logging unexpectedly accepts a runtime String: $expression"
        exit 1
    fi
    if ! rg -q \
        -e "cannot convert value of type 'String' to expected argument type 'StaticString'" \
        -e "candidate expects value of type 'StaticString' for parameter #2 \(got 'String'\)" \
        "$probe_directory/diagnostics.log"; then
        cat "$probe_directory/diagnostics.log"
        echo "Host log API probe failed for an unexpected reason."
        exit 1
    fi
done

echo "Host log API accepts declared codes, counters and flags; runtime String boundaries are enforced."
