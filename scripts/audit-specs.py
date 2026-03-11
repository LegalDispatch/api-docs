#!/usr/bin/env python3
"""Quick audit of upstream service public specs."""
import json, yaml, os, sys

os.chdir(os.path.join(os.path.dirname(__file__), "..", ".."))

specs = [
    ("auth", "authentication-service/specs/AuthenticationService_public.json"),
    ("uas", "user-account-service/specs/UserAccountService_public.json"),
    ("sop", "sop-service/specs/ServiceOfProcessService_public.json"),
    ("doc", "document-service/api/openapi-public.yaml"),
    ("pms", "partner-management-service/api/openapi-public.yaml"),
]

for svc, path in specs:
    if not os.path.exists(path):
        print(f"{svc}: NOT FOUND at {path}")
        continue
    with open(path) as f:
        spec = json.load(f) if path.endswith(".json") else yaml.safe_load(f)

    paths = list(spec.get("paths", {}).keys())
    ops = []
    internal = []
    health = []
    for p, methods in spec.get("paths", {}).items():
        if p.startswith("/internal"):
            internal.append(p)
        if p in ("/health", "/ready"):
            health.append(p)
        for m, op in methods.items():
            if isinstance(op, dict) and "operationId" in op:
                ops.append(op["operationId"])

    schemas = spec.get("components", {}).get("schemas", {})
    has_err = "ErrorResponse" in schemas
    err_fields = list(schemas.get("ErrorResponse", {}).get("properties", {}).keys()) if has_err else []

    print(f"\n=== {svc} ({path}) ===")
    print(f"  OpenAPI version: {spec.get('openapi')}")
    print(f"  Public paths: {len(paths)}")
    print(f"  Internal paths leaked: {internal}")
    print(f"  Health/Ready paths leaked: {health}")
    print(f"  OperationIds ({len(ops)}): {ops}")
    print(f"  ErrorResponse schema: {has_err} fields={err_fields}")
