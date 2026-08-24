# BroadCore agent rules

- Меняйте только этот repository.
- Domain не импортирует UI, tracking, commerce или vendor SDK frameworks.
- Другие BroadApps modules запрещены.
- UserDefaults, OSLog и ATT остаются только в канонических adapters.
- Не добавляйте `Tests/`, test targets, XCTest, Swift Testing или UI tests.
- Не добавляйте secrets, real IDs, raw error/URL/user/payment data.
- Public API меняется вместе с DocC, sandbox, report, changelog и SemVer intent.
- Перед сдачей выполните `bash Scripts/module_gate.sh` и не заявляйте PASS иначе.
