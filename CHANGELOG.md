# Changelog

Все заметные изменения BroadCore фиксируются здесь с объяснением: что изменилось и почему.

## Unreleased

Пока нет изменений.

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
