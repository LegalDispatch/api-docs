#!/usr/bin/env python3
"""Verify merged spec quality."""
import yaml, sys

spec = yaml.safe_load(open("merged/openapi.yaml"))
print(f"OpenAPI: {spec['openapi']}")
print(f"Endpoints: {len(spec['paths'])}")
print(f"Tags: {[t['name'] for t in spec['tags']]}")
print(f"Schemas: {len(spec['components']['schemas'])}")
print(f"Has ErrorResponse: {'ErrorResponse' in spec['components']['schemas']}")
print(f"Has PaginationMeta: {'PaginationMeta' in spec['components']['schemas']}")
print(f"Has BearerAuth: {'BearerAuth' in spec['components']['securitySchemes']}")

internal = [p for p in spec["paths"] if p.startswith("/internal") or p in ("/health", "/ready")]
print(f"Internal path leaks: {internal}")

ops = []
for p, methods in spec["paths"].items():
    for m, op in methods.items():
        if isinstance(op, dict) and "operationId" in op:
            ops.append(op["operationId"])

unprefixed = [o for o in ops if not any(o.startswith(pfx) for pfx in ("auth_", "uas_", "sop_", "doc_", "pms_"))]
print(f"Unprefixed operationIds: {unprefixed}")

errors = []
if internal:
    errors.append(f"Internal paths leaked: {internal}")
if unprefixed:
    errors.append(f"Unprefixed operationIds: {unprefixed}")
if errors:
    for e in errors:
        print(f"FAIL: {e}")
    sys.exit(1)
print("All checks passed!")
