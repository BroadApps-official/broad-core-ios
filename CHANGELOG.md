# Changelog

Все заметные изменения BroadCore фиксируются здесь с объяснением: что изменилось и почему.

## Unreleased

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
