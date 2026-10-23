#!/usr/bin/env python3
"""Работа с официальными OpenAPI-спецификациями Cloud.ru Evolution (кэш в ~/.cache/cloudru/specs).

  cloudru-spec.py services                      # какие спеки известны
  cloudru-spec.py SERVICE list [REGEX]          # методы: METHOD PATH — summary (фильтр по регулярке)
  cloudru-spec.py SERVICE show METHOD PATH      # параметры, тело запроса и ответ метода (схемы раскрыты)
  cloudru-spec.py SERVICE schema NAME           # одна схема из components
  cloudru-spec.py SERVICE refresh               # перекачать спеку

Ссылки на спеки взяты со страниц «Справочник API» каждого сервиса: https://cloud.ru/docs/console_api/ug/topics/overview__reestr_api
"""
import json, os, re, sys, time, urllib.request
import yaml

SPECS = {
    "iam":        "https://cloud.ru/docs/api/specs/administration/ug/_specs/iam-gw-public.yaml",
    "org":        "https://cloud.ru/docs/api/specs/administration/ug/_specs/api.op.v3.yaml",
    "compute":    "https://cloud.ru/docs/api/specs/virtual-machines/ug/_downloads/43c42ff22a171c77371e690a08181c3f/openapi-v3.yaml",
    "vpc":        "https://cloud.ru/docs/api/specs/evolution-vpc/ug/_downloads/113b453e0e2aa12a22311dfa29cac9ef/openapi.yaml",
    "dns":        "https://cloud.ru/docs/api/specs/evolution-dns/ug/_specs/openapi.yaml",
    "nlb":        "https://cloud.ru/docs/api/specs/nlb/ug/_downloads/35c3bddb6944861dfa54ad51711fec3b/swagger.yaml",
    "magic-router": "https://cloud.ru/docs/api/specs/magic-router/ug/_downloads/113b453e0e2aa12a22311dfa29cac9ef/openapi.yaml",
    "containers": "https://cloud.ru/docs/api/specs/container-apps-evolution/ug/_specs/openapi.yaml",
    "ar":         "https://cloud.ru/docs/api/specs/artifact-registry-evolution/ug/_specs/openapi.yaml",
    "mk8s":       "https://cloud.ru/docs/api/specs/kubernetes-evolution/ug/_specs/openapi-v3.yaml",
    "postgresql": "https://cloud.ru/docs/api/specs/paas-postgresql/ug/_specs/openapi-postgresql.yaml",
    "foundation-models": "https://cloud.ru/docs/api/specs/foundation-models/ug/_downloads/f2949c1237d79b17b2df8e523e02a89a/openapi__foundation-models.yaml",
}
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "cloudru", "specs")
MAX_AGE = 7 * 86400
METHODS = ("get", "post", "put", "patch", "delete")


def spec_path(service):
    if service not in SPECS:
        sys.exit(f"неизвестный сервис {service!r}; доступны: {', '.join(sorted(SPECS))}")
    return os.path.join(CACHE, f"{service}.yaml")


def load(service, refresh=False):
    p = spec_path(service)
    if refresh or not os.path.exists(p) or time.time() - os.path.getmtime(p) > MAX_AGE:
        os.makedirs(CACHE, exist_ok=True)
        req = urllib.request.Request(SPECS[service], headers={"User-Agent": "curl/8"})
        with urllib.request.urlopen(req, timeout=60) as r, open(p, "wb") as f:
            f.write(r.read())
    with open(p, encoding="utf-8") as f:
        return yaml.safe_load(f)


def resolve(spec, node, depth=0, seen=None):
    """Раскрывает $ref рекурсивно (с защитой от циклов), чтобы show печатал готовую структуру."""
    seen = seen or set()
    if isinstance(node, dict):
        if "$ref" in node:
            ref = node["$ref"]
            if ref in seen or depth > 12:
                return {"$ref": ref}
            cur = spec
            for part in ref.lstrip("#/").split("/"):
                cur = cur[part]
            return resolve(spec, cur, depth + 1, seen | {ref})
        return {k: resolve(spec, v, depth + 1, seen) for k, v in node.items()}
    if isinstance(node, list):
        return [resolve(spec, v, depth + 1, seen) for v in node]
    return node


def compact(node):
    """Убирает многословные поля, оставляя структуру и короткие описания."""
    if isinstance(node, dict):
        out = {}
        for k, v in node.items():
            if k in ("x-originalParamName", "tags", "operationId", "examples"):
                continue
            if k == "description" and isinstance(v, str):
                v = re.sub(r"\s+", " ", v).strip()
                if len(v) > 160:
                    v = v[:157] + "..."
            out[k] = compact(v)
        return out
    if isinstance(node, list):
        return [compact(v) for v in node]
    return node


def cmd_list(spec, regex):
    rx = re.compile(regex, re.I) if regex else None
    servers = [s.get("url") for s in spec.get("servers", [])]
    if servers:
        print("servers:", ", ".join(servers))
    for path, item in spec.get("paths", {}).items():
        for m in METHODS:
            if m in item:
                line = f"{m.upper():6} {path}"
                summary = item[m].get("summary") or (item[m].get("description") or "").split("\n")[0]
                if summary:
                    line += f"  — {summary.strip()}"
                if not rx or rx.search(line):
                    print(line)


def cmd_show(spec, method, path):
    item = spec.get("paths", {}).get(path)
    if not item or method.lower() not in item:
        sys.exit(f"нет {method.upper()} {path} (см. list)")
    op = dict(item[method.lower()])
    op["parameters"] = (item.get("parameters") or []) + (op.get("parameters") or [])
    # Оставляем только 2xx-ответы
    op["responses"] = {k: v for k, v in (op.get("responses") or {}).items() if str(k).startswith("2")}
    print(json.dumps(compact(resolve(spec, op)), ensure_ascii=False, indent=2, default=str))


def cmd_schema(spec, name):
    comps = spec.get("components", {}).get("schemas", {}) or spec.get("definitions", {})
    if name not in comps:
        hits = [k for k in comps if name.lower() in k.lower()]
        sys.exit("нет схемы; похожие: " + ", ".join(hits[:30]))
    print(json.dumps(compact(resolve(spec, comps[name])), ensure_ascii=False, indent=2, default=str))


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__); return
    if argv[0] == "services":
        for k, v in sorted(SPECS.items()):
            print(f"{k:18} {v}")
        return
    service, action = argv[0], (argv[1] if len(argv) > 1 else "list")
    if action == "refresh":
        load(service, refresh=True); print("ok"); return
    spec = load(service)
    if action == "list":
        cmd_list(spec, argv[2] if len(argv) > 2 else None)
    elif action == "show" and len(argv) >= 4:
        cmd_show(spec, argv[2], argv[3])
    elif action == "schema" and len(argv) >= 3:
        cmd_schema(spec, argv[2])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
