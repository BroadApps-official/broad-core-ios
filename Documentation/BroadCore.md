# BroadCore guide

BroadCore задаёт foundation contracts, одинаковые для host apps и верхних
модулей: bounded startup, cache semantics, typed states/errors/logging,
persistence и ATT boundaries.

## Bootstrap

`critical` step нужен до безопасного route. `background` запускается после
critical readiness. Каждый step имеет `TimeoutPolicy` и `RetryPolicy`.
Cancellation остаётся cancellation, а не unknown failure.

## Cache

Cache envelope хранит schema, version, saved/expires dates и typed value. Read
result всегда `fresh`, `stale` или `missing(reason)`. Caller явно решает, можно
ли показывать stale UI; cache не создаёт remote authority.

## States and errors

`LoadableState` не смешивает idle/loading/content/empty/error/stale. `AppError`
содержит безопасное user message, diagnostic code, retryability и bounded kind.

## Logging and privacy

События typed; raw error description запрещён. UserDefaults accessed-reason
declaration находится в `PrivacyInfo.xcprivacy`, проверяется source gate и
наличием идентичной копии в sandbox `.app`.

`OSLogBroadLogger` принимает subsystem как `String` (`init(subsystem: String)`) —
его удобно задать из `Bundle.main.bundleIdentifier` без повторения bundle id
литералом. `init(subsystem: StaticString)` сохранён и делегирует в строковую
версию.

## Tracking

System adapter инкапсулирует ATT API. Модуль не выбирает момент запроса. Host или
onboarding flow вызывает use case только после видимого первого слайда.

## Debug flags

`DebugFlagStore` хранит debug-переключатели поверх `KeyValueStoreProtocol` с
опциональным launch-argument override. Persistence и namespacing делает
инжектируемый store. Приложение объявляет свои `DebugFlag` (ключ, аргумент схемы,
`defaultValue`), читает их под `#if DEBUG` и сбрасывает через `reset`. Store не
содержит политики: Release-сборка его просто не создаёт.

```swift
let store = UserDefaultsKeyValueStore(namespace: "\(bundleIdentifier).debug")
let flags = DebugFlagStore(store: store)
let forcePremium = DebugFlag(key: "force-premium", launchArgument: "-debug-force-premium")
if await flags.isOn(forcePremium) { /* ... */ }
```

`DebugKeychainCleaner` (только `#if DEBUG`) удаляет точные app-owned
generic-password сервисы Keychain, которые перечислит хост через
`DebugKeychainScope`, чтобы сбросить состояние между test-прогонами. Он не
запускается на старте и не трогает unscoped Keychain-класс. Release-сборка его не
содержит.

## Проверка

```bash
bash Scripts/module_gate.sh
```
