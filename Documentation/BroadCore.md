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

## Account identifier

`KeychainAccountIdentifierStore` хранит стабильный идентификатор аккаунта — тот,
что приложение передаёт в Adapty как customer user ID и в свой backend. Он лежит
в Keychain и переживает переустановку, а с `synchronizesThroughICloudKeychain`
(по умолчанию `true`) копия уезжает в «Связку ключей iCloud». Новый телефон на
том же Apple ID получает тот же идентификатор и попадает в тот же аккаунт —
вместе с подпиской, в том числе оплаченной картой или СБП, и балансом токенов.
Restore Purchases возвращает только покупки Apple.

Порядок разрешения:

1. `legacyIdentifier` хоста — идентификатор уже установленного приложения. Под
   ним живут покупки и аккаунт backend, поэтому на этом устройстве главный он.
2. Своя запись устройства — важнее iCloud: после переустановки приложение не
   должно взять идентификатор, который туда положил другой телефон.
3. Запись из «Связки ключей iCloud» — своей записи нет, значит это новый телефон.
4. Новый идентификатор — возвращается только после записи на устройство.

В iCloud запись кладётся, только если её там ещё нет: два телефона не
перетягивают её друг у друга. Идентификатор не логируется.

`resolve()` возвращает `.failed(failureError)`, если Keychain не читается —
например, фоновый запуск до первой разблокировки — или новый идентификатор не
удалось сохранить. Хост повторяет позже, а не заводит второй аккаунт.

`AccountIdentifierSource` говорит, откуда идентификатор взялся на этом запуске.
`.iCloudKeychain` бывает ровно один раз — на первом запуске нового телефона;
дальше тот же идентификатор приходит как `.device`.

Что учесть:

- **Общий Apple ID — общий аккаунт.** Если семья сидит на одном Apple ID, второй
  человек попадёт в аккаунт первого: подписка, токены и серверные данные общие.
  Если серверные данные личные (например, история чатов), решайте по
  `.iCloudKeychain`, подтягивать ли их.
- Синхронизация нужна подписанная сборка и включённая «Связка ключей iCloud».
  Без них идентификатор остаётся на устройстве, как при
  `synchronizesThroughICloudKeychain: false`.
- iCloud Keychain приезжает не мгновенно. Если новый телефон запустит приложение
  раньше, получится `.generated`, и устройство останется на своём аккаунте.
- `synchronizesThroughICloudKeychain: false` — отключённый вариант: стабильный
  идентификатор устройства, iCloud не читается и не пишется.

```swift
let accountIdentifiers = KeychainAccountIdentifierStore(
    configuration: KeychainAccountIdentifierConfiguration(service: "\(bundleIdentifier).account"),
    failureError: accountUnavailableError,
    legacyIdentifier: { UserDefaults.standard.string(forKey: "user_id") }
)

switch await accountIdentifiers.resolve() {
case let .resolved(identifier, source):
    /* identifier → Adapty и backend; .iCloudKeychain — новый телефон существующего аккаунта */
case .failed:
    /* Keychain недоступен: повторить позже */
}
```

## Проверка

```bash
bash Scripts/module_gate.sh
```
