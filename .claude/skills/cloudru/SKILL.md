---
name: cloudru
description: Управление облаком Cloud.ru Evolution (хостинг проекта) через официальный публичный API без сторонних SDK — ключ доступа сервисного аккаунта, Bearer-токен, curl. Используй всегда, когда речь о cloud.ru, облаке, хостинге, деплое, виртуальных машинах, Container Apps, Artifact Registry, Managed PostgreSQL, Kubernetes, VPC, DNS, балансировщике, Object Storage (s3.cloud.ru), квотах или проекте в облаке, даже если слово «cloud.ru» не прозвучало.
---

# Cloud.ru Evolution через API

Инфраструктура проекта живёт в Cloud.ru (платформа Evolution). Официального MCP-сервера у Cloud.ru нет,
поэтому всё делаем прямыми HTTP-запросами по их OpenAPI-спецификациям. Два скрипта в `scripts/`
берут на себя токен и чтение спецификаций; сторонние SDK и обёртки не используем.

## Как устроен доступ

- **Ключ доступа сервисного аккаунта** (Key ID + Key Secret) меняется на токен:
  `POST https://iam.api.cloud.ru/api/v2/auth/token` с JSON `{"keyId","secret"}` → `accessToken`, `expiresIn` (3600 с).
- Токен идёт в каждый запрос: `Authorization: Bearer <token>`. Скрипт кэширует его и обновляет сам.
- Почти каждый метод требует **ID проекта**: в query `project_id` (Compute) или `projectId` (Container Apps и др.) или в теле. Смотри параметры через `cloudru-spec.py`.
- Учётные данные лежат вне репозитория в `~/.config/cloudru/credentials` (права 600):

```
CLOUDRU_KEY_ID=...
CLOUDRU_KEY_SECRET=...
CLOUDRU_PROJECT_ID=...
```

Секреты не печатать в чат и не класть в репозиторий. Если файла нет — не выдумывать, а
объяснить пользователю, что создать (готовая инструкция: `references/console-setup.md`).

## Рабочий цикл

1. Проверить доступ: `scripts/cloudru-api.sh whoami` (возвращает проект из Organization API).
2. Найти нужный метод: `scripts/cloudru-spec.py SERVICE list [regex]`, затем
   `scripts/cloudru-spec.py SERVICE show METHOD PATH` — печатает параметры, тело и ответ с раскрытыми схемами.
   Не угадывать поля тела по памяти: спеки меняются, show даёт актуальное.
3. Выполнить: `scripts/cloudru-api.sh METHOD SERVICE PATH [JSON|-]`. В PATH работает подстановка `{{project_id}}`.
4. Создание и изменение ресурсов почти всегда асинхронное: ответ содержит операцию или задачу
   (`/v1/operations/{id}`, `/api/v1/tasks/{id}`, `.../operations`). Опрашивать до завершения, прежде чем
   считать ресурс готовым.

Примеры:

```bash
S=.claude/skills/cloudru/scripts
$S/cloudru-api.sh GET org "/v3/projects"                                   # все проекты организации
$S/cloudru-api.sh GET compute "/api/v1/vms?project_id={{project_id}}"      # список ВМ
$S/cloudru-api.sh GET containers "/v2/containers?projectId={{project_id}}" # Container Apps
$S/cloudru-api.sh GET postgresql "/v1/clusters?project_id={{project_id}}"  # кластеры PostgreSQL
$S/cloudru-spec.py containers show POST /v2/containers                     # тело для создания контейнера
$S/cloudru-api.sh POST containers /v2/containers - <<'JSON'
{ "projectId": "...", "name": "...", "configuration": {...}, "template": {...} }
JSON
```

Алиасы сервисов и хостов: `cloudru-api.sh services`; подробности по каждому сервису, спекам и
особенностям (S3, Foundation Models, Terraform) — `references/apis.md`.

## Что важно помнить

- Платные действия (создание ВМ, кластера БД, балансировщика, выделение публичного IP) делать только
  после явного согласия пользователя: баланс списывается сразу. Удаление ресурсов — тоже только по явной просьбе.
- Названия ресурсов именовать по проекту: префикс `regulyatorka-`.
- Если API отвечает 403 — чаще всего у сервисного аккаунта нет роли в проекте или ключ выдан не на тот
  уровень. Роли описаны в `references/console-setup.md`.
- Object Storage — это S3-совместимый API на `https://s3.cloud.ru` (регион `ru-central-1`) с подписью SigV4,
  а не Bearer-токен; ключ там `<tenant_id>:<key_id>` + Key Secret. Детали в `references/apis.md`.
- Личный кабинет: https://console.cloud.ru. Документация: https://cloud.ru/docs. Реестр всех API:
  https://cloud.ru/docs/console_api/ug/topics/overview__reestr_api.
