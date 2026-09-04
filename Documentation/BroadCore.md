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

`UserDefaultsKeyValueStore` предназначен для небольших flags/state и по
умолчанию ограничивает value 512 КБ. Большие offline-каталоги подключаются через
`FileSystemKeyValueStore`: host передаёт cache directory, namespace и явный
лимит. Запись атомарная, key не становится именем файла, conditional write и
remove сохраняют общий compare-and-swap contract.

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

## Server time

`ServerSynchronizedClock` даёт текущее время, выведенное из ответов бэкенда
хоста, а не из часов устройства. Всё платное, что зависит от времени — срок
кампании, обратный отсчёт, тихий период между офферами — не должно считаться по
устройским часам: пользователь переводит дату вперёд и заканчивает окно раньше,
переводит назад и открывает новое.

Хост отдаёт только источник: на каждый ответ своего HTTP-слоя вызывает
`record(_:)` с `Date` из заголовка (или сразу с `HTTPURLResponse` — заголовок
разберёт `HTTPServerDate`). Смещение к часам устройства сохраняется через
`KeyValueStoreProtocol`, поэтому окно переживает перезапуск: relaunch через два
часа видит те же два часа. Показания не идут назад — перевод часов назад ничего
не даёт. Серверная дата остаётся авторитетом и может подвинуть отметку в обе
стороны; устройство — только вперёд.

Чтение всегда несёт ярлык доверия. `ServerTimeReading.unverified` — это часы
устройства до первого ответа бэкенда, и вызывающий обязан решить, что с этим
делать, а не работать молча.

```swift
let clock = ServerSynchronizedClock(store: keyValueStore)

// В HTTP-слое приложения, на каждый ответ:
await clock.record(httpResponse)

// Там, где время влияет на показ или на деньги:
switch await clock.reading() {
case let .synchronized(now): /* можно считать сроки */
case .unverified: /* отказываемся, а не считаем по устройству */
}
```

## Проверка

```bash
bash Scripts/module_gate.sh
```
