# Contributor guide

## Boundary

BroadCore — нижний foundation layer. Domain не импортирует UIKit, SwiftUI,
StoreKit, Adapty или AppTrackingTransparency. Infrastructure adapters не
принимают product decisions. Другие BroadApps imports запрещены.

## Layout

```text
Sources/BroadCore/Domain             models, policies, states, protocols
Sources/BroadCore/Application        bootstrap/use cases/DI
Sources/BroadCore/Data               repositories
Sources/BroadCore/Infrastructure     system adapters
Sources/BroadCore/Resources          PrivacyInfo.xcprivacy
Examples/BroadCoreSandbox            standalone iPhone example
Scripts/ContractProbes               executable non-test probes
```

## Invariants

- Любая startup операция имеет конечный timeout.
- Retry bounded и не скрывает cancellation.
- Cache не авторизует чувствительные remote gates.
- Raw error/URL/credentials не входят в typed logs.
- ATT вызывается только через adapter по решению видимого UI flow.
- UserDefaults и OSLog используются только каноническими adapters.
- Privacy manifest source и копия внутри sandbox app совпадают.

## Public API

Additive API получает minor, compatible fix — patch, breaking API/behavior —
major. Сначала выпускайте additive Core contract, затем обновляйте consumers;
удаление deprecated API возможно в следующем major.

```bash
bash Scripts/generate_public_api_report.sh --update
```

## Contract probes

Probe компилирует production sources, не дублирует алгоритм и возвращает nonzero
при нарушении. XCTest/Swift Testing и `Tests/` не добавляются.

## Release

Release notes отвечают: **Что изменилось и почему?**

1. Обновите changelog/docs/sandbox/API report.
2. Пройдите clean `bash Scripts/module_gate.sh`.
3. Создайте tag `x.y.z` и дождитесь release workflow.
4. Обновите Core range в consumers.
5. Соберите exact combination в integration repository.
6. После PASS обновите compatibility catalog и public docs.
