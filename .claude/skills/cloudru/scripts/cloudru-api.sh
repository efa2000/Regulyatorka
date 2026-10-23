#!/usr/bin/env bash
# Обёртка над публичным API Cloud.ru Evolution (только curl + python3).
#
#   cloudru-api.sh METHOD SERVICE PATH [BODY|-]      # запрос; BODY — JSON-строка, "-" — из stdin
#   cloudru-api.sh token                              # напечатать действующий access token
#   cloudru-api.sh whoami                             # проверка доступа: проект из CLOUDRU_PROJECT_ID
#   cloudru-api.sh services                           # список алиасов сервисов
#
# SERVICE — алиас хоста (compute, vpc, containers, ...) или полный https://-URL.
# В PATH подстановка {{project_id}} -> $CLOUDRU_PROJECT_ID.
#
# Учётные данные: ~/.config/cloudru/credentials (KEY=VALUE, см. SKILL.md) или переменные окружения
# CLOUDRU_KEY_ID, CLOUDRU_KEY_SECRET, CLOUDRU_PROJECT_ID. Токен кэшируется в ~/.cache/cloudru/token.json.
#
# Источник: https://cloud.ru/docs/console_api/ug/topics/guides__auth_api
#           https://cloud.ru/docs/administration/ug/topics/api-ref__authentication
set -euo pipefail

CRED_FILE="${CLOUDRU_CREDENTIALS:-$HOME/.config/cloudru/credentials}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cloudru"
TOKEN_FILE="$CACHE_DIR/token.json"
IAM_TOKEN_URL="https://iam.api.cloud.ru/api/v2/auth/token"

declare -A HOSTS=(
  [iam]=https://iam.api.cloud.ru
  [org]=https://organization.api.cloud.ru
  [compute]=https://compute.api.cloud.ru
  [vpc]=https://vpc.api.cloud.ru
  [dns]=https://dns.api.cloud.ru
  [nlb]=https://nlb.api.cloud.ru
  [magic-router]=https://magic-router.api.cloud.ru
  [containers]=https://containers.api.cloud.ru
  [ar]=https://ar.api.cloud.ru
  [mk8s]=https://mk8s.api.cloud.ru
  [postgresql]=https://postgresql.api.cloud.ru
  [redis]=https://redis.api.cloud.ru
  [secretmanager]=https://secretmanager.api.cloud.ru
  [certificatemanager]=https://certificatemanager.api.cloud.ru
  [foundation-models]=https://foundation-models.api.cloud.ru
)

die() { echo "cloudru-api: $*" >&2; exit 1; }

load_credentials() {
  if [[ -f "$CRED_FILE" ]]; then
    local mode; mode=$(stat -c %a "$CRED_FILE")
    [[ "$mode" == "600" || "$mode" == "400" ]] || echo "cloudru-api: предупреждение: $CRED_FILE должен иметь права 600" >&2
    set -a; # shellcheck disable=SC1090
    source "$CRED_FILE"; set +a
  fi
  : "${CLOUDRU_KEY_ID:?нет CLOUDRU_KEY_ID (создайте $CRED_FILE, см. SKILL.md)}"
  : "${CLOUDRU_KEY_SECRET:?нет CLOUDRU_KEY_SECRET}"
  export CLOUDRU_PROJECT_ID="${CLOUDRU_PROJECT_ID:-}"
}

# Печатает токен из кэша, если до истечения больше 5 минут; иначе пусто.
cached_token() {
  [[ -f "$TOKEN_FILE" ]] || return 0
  python3 -I - "$TOKEN_FILE" "$CLOUDRU_KEY_ID" <<'PY'
import json, sys, time
try:
    d = json.load(open(sys.argv[1]))
    if d.get("keyId") == sys.argv[2] and d["expiresAt"] - time.time() > 300:
        print(d["accessToken"])
except Exception:
    pass
PY
}

fetch_token() {
  mkdir -p "$CACHE_DIR"; chmod 700 "$CACHE_DIR"
  local body resp
  body=$(python3 -I -c 'import json,os;print(json.dumps({"keyId":os.environ["CLOUDRU_KEY_ID"],"secret":os.environ["CLOUDRU_KEY_SECRET"]}))')
  resp=$(curl -sS --fail-with-body -X POST "$IAM_TOKEN_URL" -H 'Content-Type: application/json' -d "$body") \
    || die "не удалось получить токен: $resp"
  python3 -I - "$TOKEN_FILE" "$CLOUDRU_KEY_ID" "$resp" <<'PY'
import json, sys, time, os
path, key_id, raw = sys.argv[1:4]
d = json.loads(raw)
tok = d.get("accessToken") or d.get("access_token")
if not tok:
    sys.exit("cloudru-api: в ответе нет accessToken: " + raw[:300])
exp = int(d.get("expiresIn") or d.get("expires_in") or 3600)
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    json.dump({"keyId": key_id, "accessToken": tok, "expiresAt": time.time() + exp}, f)
print(tok)
PY
}

get_token() {
  local t; t=$(cached_token)
  if [[ -z "$t" ]]; then
    t=$(fetch_token) || exit 1
    [[ -n "$t" ]] || die "пустой токен"
  fi
  printf '%s' "$t"
}

resolve_host() {
  local s="$1"
  if [[ "$s" == https://* ]]; then printf '%s' "${s%/}"; return; fi
  [[ -n "${HOSTS[$s]:-}" ]] || die "неизвестный сервис '$s' (см. 'cloudru-api.sh services')"
  printf '%s' "${HOSTS[$s]}"
}

request() {
  local method="$1" service="$2" path="$3" body="${4:-}"
  local host url token
  host=$(resolve_host "$service")
  path="${path//\{\{project_id\}\}/$CLOUDRU_PROJECT_ID}"
  [[ "$path" == /* ]] || path="/$path"
  url="$host$path"
  token=$(get_token) || exit 1
  local args=(-sS -X "$method" "$url" -H "Authorization: Bearer $token" -H 'Accept: application/json')
  if [[ "$body" == "-" ]]; then args+=(-H 'Content-Type: application/json' --data-binary @-)
  elif [[ -n "$body" ]]; then args+=(-H 'Content-Type: application/json' --data-binary "$body"); fi
  local out code
  out=$(curl "${args[@]}" -w $'\n%{http_code}')
  code="${out##*$'\n'}"; out="${out%$'\n'*}"
  # Красиво печатаем JSON, если это JSON.
  printf '%s' "$out" | python3 -I -c 'import json,sys
raw=sys.stdin.read()
try: print(json.dumps(json.loads(raw), ensure_ascii=False, indent=2))
except Exception: print(raw)'
  [[ "$code" =~ ^2 ]] || { echo "HTTP $code" >&2; exit 22; }
}

cmd="${1:-}"; shift || true
case "$cmd" in
  token)    load_credentials; get_token; echo ;;
  services) for k in "${!HOSTS[@]}"; do printf '%-20s %s\n' "$k" "${HOSTS[$k]}"; done | sort ;;
  whoami)   load_credentials
            [[ -n "$CLOUDRU_PROJECT_ID" ]] || die "нет CLOUDRU_PROJECT_ID"
            request GET org "/v3/projects/{{project_id}}" ;;
  GET|POST|PUT|PATCH|DELETE)
            load_credentials
            [[ $# -ge 2 ]] || die "использование: cloudru-api.sh $cmd SERVICE PATH [BODY|-]"
            request "$cmd" "$1" "$2" "${3:-}" ;;
  *)        sed -n '2,15p' "$0"; exit 1 ;;
esac
