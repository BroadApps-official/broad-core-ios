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

## Tracking

System adapter инкапсулирует ATT API. Модуль не выбирает момент запроса. Host или
onboarding flow вызывает use case только после видимого первого слайда.

## Проверка

```bash
bash Scripts/module_gate.sh
```
