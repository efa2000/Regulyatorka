# Сервисы Cloud.ru Evolution: хосты, спецификации, особенности

Актуально на 23.10.2026. Источник — страницы «Справочник API» каждого сервиса
(реестр: https://cloud.ru/docs/console_api/ug/topics/overview__reestr_api). Спеки качает и разбирает
`scripts/cloudru-spec.py`; алиас в первой колонке — одинаковый для обоих скриптов.

| Алиас | Хост | Спека | Параметр проекта | Заметки |
|---|---|---|---|---|
| iam | https://iam.api.cloud.ru | iam-gw-public.yaml | — | токен (`/api/v2/auth/token`), сервисные аккаунты, ключи, роли, impersonate |
| org | https://organization.api.cloud.ru | api.op.v3.yaml | — | `/v3/projects`, `/v3/customers`, `/v3/organizationUnits`, квоты |
| compute | https://compute.api.cloud.ru | openapi-v3.yaml (0.7 МБ) | query `project_id` | ВМ, диски, образы, флейворы, подсети, SG, floating IP, NAT, бэкапы; новые ВМ — `POST /api/v1.1/vms`; задачи `/api/v1/tasks/{id}` |
| vpc | https://vpc.api.cloud.ru | openapi.yaml | query `projectId` | VPC, адресные пулы, статические маршруты, VIP; операции `/v1/vpcs/operations/{id}` |
| dns | https://dns.api.cloud.ru | openapi.yaml | query `projectId` | публичные/приватные зоны и записи |
| nlb | https://nlb.api.cloud.ru | swagger.yaml | см. show | `/v2/networkLoadBalancers`, `/v2/targetGroups`, `/v2/operations/{id}` |
| magic-router | https://magic-router.api.cloud.ru | openapi.yaml | см. show | маршрутизатор между сетями |
| containers | https://containers.api.cloud.ru | openapi.yaml | query/body `projectId` | Container Apps: `/v2/containers`, старт/стоп, логи, ревизии; входит во free tier |
| ar | https://ar.api.cloud.ru | openapi.yaml | query `projectId` | Artifact Registry: `/v1/registries`; docker login описан в доке сервиса |
| mk8s | https://mk8s.api.cloud.ru | openapi-v3.yaml | query `projectId` | Managed Kubernetes: кластеры, нод-пулы, `:getKubeConfig` |
| postgresql | https://postgresql.api.cloud.ru | openapi-postgresql.yaml | query `project_id` | Managed PostgreSQL: `/v1/clusters`, базы, пользователи, бэкапы, `/v1/specifications`, `/v1/versions` |
| redis | https://redis.api.cloud.ru | ссылка на спеку на странице не найдена | — | смотреть https://cloud.ru/docs/redis/ug/topics/api-ref |
| secretmanager | https://secretmanager.api.cloud.ru | — | — | https://cloud.ru/docs/scsm/ug/topics/api-ref |
| certificatemanager | https://certificatemanager.api.cloud.ru | — | — | https://cloud.ru/docs/certificate-manager/ug/topics/api-ref |
| foundation-models | https://foundation-models.api.cloud.ru/v1/ | openapi__foundation-models.yaml | — | OpenAI-совместимый API; авторизация обычно API-ключом, см. доку |

Нет в скриптах (есть в реестре): ClickHouse, OpenSearch, Kafka, Spark, Trino, Airflow, Metastore, BI, AI Agents,
Notebooks, Key Management, Monitoring, Audit/Client Logging, Cost Control (`billing`, методы `v1/consumption`,
`v2/consumption`), Support API. Хост и спеку брать со страницы сервиса в реестре и передавать в
`cloudru-api.sh` полным URL.

## Аутентификация, подробно

- Обмен ключа на токен, v2 (используем): `POST https://iam.api.cloud.ru/api/v2/auth/token`,
  JSON `{"keyId": "...", "secret": "...", "serviceAccountId": "необязательно, для impersonate"}`.
  Ответ: `accessToken`, `expiresIn` (сек), `idToken`, `notBefore`. Срок жизни 1 час, не настраивается.
- v1: `POST https://iam.api.cloud.ru/api/v1/auth/token` с теми же `keyId`/`secret` — продолжает работать.
- OIDC-вариант из квикстарта: `POST https://auth.iam.cloud.ru/auth/system/openid/token`,
  form-urlencoded `grant_type=access_key&client_id=<KEY_ID>&client_secret=<SECRET>`.
- Статический API-ключ: заголовок `Authorization: Api-Key <key>` без обмена на токен. Создаётся только для
  сервисного аккаунта, привязан к списку сервисов, менее безопасен. Нужен там, где обмен на токен невозможен.
- Impersonate: роль `iam.serviceaccount.impersonator` позволяет получить токен другого сервисного аккаунта
  без его ключей (поле `serviceAccountId` в v2).

Документация: https://cloud.ru/docs/console_api/ug/topics/guides__auth_api,
https://cloud.ru/docs/administration/ug/topics/api-ref__authentication.

## Object Storage (S3)

- Эндпоинт `https://s3.cloud.ru`, регион `ru-central-1`, подпись AWS SigV4.
- Access key = `<tenant_id>:<key_id>` (или через точку), secret = Key Secret того же ключа доступа.
  tenant_id смотрится в консоли: Хранение данных → Object Storage → Параметры работы с API.
- Bearer-токен здесь не работает. Для запросов использовать `aws s3 ... --endpoint-url https://s3.cloud.ru`
  (официальная дока показывает именно AWS CLI) или подписывать SigV4 вручную.
- Дока: https://cloud.ru/docs/s3e/ug/topics/api__getting-started, https://cloud.ru/docs/s3e/ug/topics/api__api-key.

## Terraform (официальный провайдер Cloud.ru)

Провайдер `cloudru/cloud` поставляется самим Cloud.ru через зеркало `https://evo-tf-provider-generic.ar.cloud.ru/`
(`.terraformrc` → `provider_installation.network_mirror`). Блок `provider "cloudru"` принимает `auth_key_id`,
`auth_secret`, `project_id`. Примеры: https://github.com/CLOUDdotRu/evo-terraform/tree/main/reference.
Дока: https://cloud.ru/docs/terraform-evolution/ug/topics/quickstart. Вариант на будущее, если захочется IaC;
сейчас не используем.

## Сторонний MCP (не используем)

В доке Container Apps упоминается MCP-сервер `cloudru-containerapps-mcp` (Go, репозиторий Nick1994209, не
организация Cloud.ru). По правилу «без чужих SDK» не ставим. Если Cloud.ru выпустит собственный MCP —
пересмотреть: https://cloud.ru/docs/container-apps-evolution/ug/topics/guides__mcp-server.

## Free tier

Бесплатные объёмы есть у Object Storage, Container Apps и Managed BI при неотрицательном балансе;
ВМ и PostgreSQL в список не входят. Лимиты смотреть на https://cloud.ru/docs/evolution/overview/topics/free-tier.
