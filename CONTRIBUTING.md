# Как предложить изменение

Repository и документация публичны. Любой разработчик может сделать fork,
создать branch и открыть pull request.

Не добавляйте higher-level BroadApps imports, app-owned IDs/secrets и test
targets. Обновите docs/sandbox/probe/API report/changelog, выполните
`bash Scripts/module_gate.sh` и объясните в PR, что изменилось и почему.
