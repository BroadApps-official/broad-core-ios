# Changelog

Все заметные изменения BroadCore фиксируются здесь с объяснением: что изменилось и почему.

## 1.2.0

### Added

- `BroadSupportLogRecorder` — in-memory ring buffer typed-событий, который
  отдаёт готовый `support-log.txt` (`makeSupportLog()` / `makeSupportLogData()`)
  для вложения в письмо в поддержку. Раньше контракт `SupportEmail.md` требовал
  прикрепить настоящий лог, а платформа не давала источника — host-приложения
  либо подставляли fixture-строку, либо писали собственный логгер. Буфер
  ограничен `capacity`, вытесненные записи считаются, I/O отсутствует; строки
  собираются тем же форматтером, что и Console, поэтому секреты и payload туда
  попасть не могут по построению.
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
