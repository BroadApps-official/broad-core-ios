# Changelog

Все заметные изменения BroadCore фиксируются здесь с объяснением: что изменилось и почему.

## 2.1.0

### Added

- `KeychainAccountIdentifierStore` — стабильный идентификатор аккаунта (customer
  user ID для Adapty и backend) в Keychain с копией в «Связке ключей iCloud».
  Порядок: `legacyIdentifier` хоста → своя запись устройства → запись из iCloud →
  новый идентификатор. Своя запись важнее iCloud, в iCloud пишется только при
  пустой записи, новый идентификатор возвращается только после сохранения, а
  недоступный Keychain даёт `.failed` вместо второго аккаунта.
- `KeychainAccountIdentifierConfiguration` — service, account, access group и
  `synchronizesThroughICloudKeychain` (по умолчанию `true`; `false` держит
  идентификатор только на устройстве).
- `AccountIdentifierProviderProtocol`, `AccountIdentifierResolution` и
  `AccountIdentifierSource` (`legacy` / `device` / `iCloudKeychain` / `generated`):
  хост видит, что это новый телефон существующего аккаунта, и сам решает,
  подтягивать ли его серверные данные.

Изменение аддитивное: существующий API и поведение не меняются.

### Почему

Приложения генерируют customer user ID сами и держат его на устройстве. Новый
телефон на том же Apple ID получает новый аккаунт: подписку Apple возвращает
Restore Purchases, а оплату картой или СБП и купленные токены — ничто, и саппорт
переносит их руками. Один раз написанный и проверенный store закрывает это для
всех приложений вместе с неочевидными случаями: переустановка рядом с другим
телефоном на том же Apple ID и фоновый запуск до первой разблокировки.

## 2.0.0

### Breaking

- В публичный enum `BroadLogEvent` добавлен case `.host`: потребители с
  exhaustive switches должны обработать новое событие. Поэтому выбран major
  bump; существующие платформенные события сохраняют форму и поведение.

### Added

- `BroadLogEvent.host(BroadLogHostEvent)` — типизированный кейс для событий
  самого приложения. До него enum был закрыт, и в `support-log.txt` попадали
  только платформенные шаги: письмо в поддержку уходило без единой строки о том,
  что делал бэкенд приложения в момент проблемы.
- `BroadLogHostEvent` и `BroadLogHostField` принимают заранее объявленные
  коды, имена и символьные значения как `StaticString`, счётчики как `Int`
  и флаги как `Bool`. Runtime-строки не входят в этот API. Форматтер заменяет
  всё вне `A-Za-z0-9._:-` на `-`, ограничивает строки 64 символами и событие
  восемью полями, сохраняя их порядок и повторяющиеся имена.

### Почему

Контракт SupportEmail обещает вложенный лог, по которому саппорт понимает
проблему. Для приложения со своим бэкендом такой лог без его событий
бесполезен: видно, что bootstrap прошёл и пейвол открылся, но не видно, почему
упала генерация. Один host-кейс позволяет приложению добавлять собственные
коды событий с фиксированной формой полей.

## 1.2.0

### Added

- `ServerSynchronizedClock` — доверенное время из ответов бэкенда хоста вместо
  часов устройства: `record(_:)` принимает серверную дату (или `HTTPURLResponse`,
  заголовок разберёт `HTTPServerDate`), смещение и high-water персистятся через
  `KeyValueStoreProtocol`, показания не идут назад. Нужен всему, где время влияет
  на показ или на деньги: срок кампании, обратный отсчёт, тихий период между
  офферами. Раньше такой примитив писало каждое приложение заново.
- `ServerTimeReading` и `ServerTimeProviderProtocol` — чтение всегда несёт ярлык
  доверия (`synchronized` / `unverified`), поэтому хост не может молча остаться
  на часах устройства, а фича может потребовать подтверждённое время явно.
- `BroadSupportLogRecorder` — in-memory ring buffer typed-событий, который
  отдаёт готовый `support-log.txt` (`makeSupportLog()` / `makeSupportLogData()`)
  для вложения в письмо в поддержку. Буфер ограничен `capacity`, вытесненные
  записи считаются, I/O отсутствует; строки собираются тем же безопасным
  форматтером, что и Console.
- `CompositeBroadLogger` — fan-out на несколько `BroadLoggerProtocol`, чтобы
  composition root передавал один logger, пишущий и в OSLog, и в recorder.

### Changed

- Безопасный рендеринг `BroadLogEvent` в строку вынесен из `OSLogBroadLogger` во
  внутренний `BroadLogEventFormatter`; публичный API и вывод OSLog не изменились.
- Sandbox показывает секцию «Support log» с содержимым recorder-а; добавлен
  contract probe `BroadCoreLoggingProbe`.

## 1.1.0

### Added

- `FileSystemKeyValueStore` даёт атомарное файловое хранение с namespace,
  размерным лимитом и compare-and-swap для offline-каталогов, которые не должны
  помещаться в 512-КБ `UserDefaults` value.
- `DebugFlag` и `DebugFlagStore` — примитив debug-переключателей поверх
  `KeyValueStoreProtocol`: опциональный launch-argument override, `defaultValue` и
  `reset`; persistence и namespacing делает инжектируемый store. Даёт приложениям
  общую основу под `#if DEBUG`-тумблеры вместо самодельного стора в каждом проекте.
  Store сам по себе не несёт политики.
- `DebugKeychainScope`, `DebugKeychainCleanupOutcome` и `DebugKeychainCleaner`
  (только `#if DEBUG`) — очистка точных app-owned generic-password сервисов
  Keychain для сброса состояния между test-прогонами. Никогда не запускается на
  старте и не трогает unscoped Keychain-класс — удаляются только названные хостом
  сервисы. В Release не компилируется.
- `OSLogBroadLogger.init(subsystem: String)` — рантайм-инициализатор логгера:
  subsystem можно задать из `Bundle.main.bundleIdentifier`, не повторяя bundle id
  как `StaticString`-литерал. `StaticString`-версия сохранена и делегирует в
  новую, поэтому существующий код не ломается.

### Changed

- верх README теперь ведёт в актуальную cross-module карту создания
  приложения, не дублируя её внутри foundation-модуля;
- README получил визуальную карту bootstrap/cache, быстрый маршрут и точные
  границы critical/background работы, ATT и async feedback;
- восстановлены актуальные схемы из последней полной platform-инструкции без
  старого umbrella-package и app-specific данных.

### Почему

После разделения монолита Core README описывал API, но потерял наглядное
объяснение runtime-порядка. Теперь repository снова самодостаточен для
разработчика и при этом не присваивает UI или monetization-контракты соседних
модулей.

## 1.0.0

### Added

- bounded critical/background bootstrap, retry/timeout и cancellation;
- versioned cache contracts и persistence adapter;
- typed loadable states, errors, logging и safe network classification;
- ATT boundary и Swinject assembly;
- privacy manifest, standalone sandbox, executable probe, DocC/API report;
- reproducible module/quality/release gates без test targets.

### Почему

Foundation вынесен в независимый public repository, чтобы Core можно было
ревьюить и выпускать отдельно, а Monetization/UIFlows зависели от SemVer release,
не от всего общего исходного дерева.
