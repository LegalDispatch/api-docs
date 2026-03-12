#!/usr/bin/env bash
# merge-specs.sh — Merge individual service specs into a unified OpenAPI document.
#
# Usage: ./scripts/merge-specs.sh
#
# Prerequisites:
#   npm install -g @redocly/cli
#   pip3 install pyyaml
#
# Pipeline:
#   1. Validate each spec in specs/
#   2. Pre-process: remove ErrorResponse (injected post-merge) + normalize version
#   3. Merge via redocly join
#   4. Post-process: set platform metadata (info, tags, servers, security, schemas, parameters)
#   5. Validate merged output
#
# Upstream services handle: public-only paths, prefixed operationIds, ErrorResponse.
# This script only handles platform-level concerns + the shared ErrorResponse schema.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPECS_DIR="$REPO_ROOT/specs"
MERGED_DIR="$REPO_ROOT/merged"
OUTPUT="$MERGED_DIR/openapi.yaml"
export SPECS_DIR MERGED_DIR OUTPUT

# ─── Colors ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ─── Preflight ───────────────────────────────────────────
if ! command -v redocly &>/dev/null; then
    error "redocly CLI not found. Install with: npm install -g @redocly/cli"
    exit 1
fi

SPEC_FILES=()
for ext in yaml yml json; do
    while IFS= read -r -d '' file; do
        SPEC_FILES+=("$file")
    done < <(find "$SPECS_DIR" -maxdepth 1 -name "*.$ext" -print0 2>/dev/null)
done

if [ ${#SPEC_FILES[@]} -eq 0 ]; then
    error "No spec files found in $SPECS_DIR"
    exit 1
fi

info "Found ${#SPEC_FILES[@]} spec file(s) in $SPECS_DIR"

# ─── Step 1: Validate individual specs ───────────────────
info "Validating individual specs..."
for spec in "${SPEC_FILES[@]}"; do
    name="$(basename "$spec")"
    if redocly lint "$spec" --config "$REPO_ROOT/.redocly.yaml" 2>/dev/null; then
        info "  ✓ $name"
    else
        warn "  ✗ $name (lint warnings — continuing)"
    fi
done

# ─── Step 2: Pre-process — remove ErrorResponse + normalize version ──
# ErrorResponse is defined in every service spec but differs slightly between
# .NET and Go (descriptions, examples). Remove it before join, inject the
# canonical version in post-processing. Also normalize OpenAPI version to 3.1.0
# (.NET 10 exports 3.1.1, Go specs use 3.1.0).
info "Pre-processing specs..."
PREPROC_DIR=$(mktemp -d)
trap "rm -rf $PREPROC_DIR" EXIT
export PREPROC_DIR

python3 << 'PYEOF'
import yaml, json, os

specs_dir = os.environ["SPECS_DIR"]
preproc_dir = os.environ["PREPROC_DIR"]

# Minimal ErrorResponse placeholder — identical in every spec so redocly join
# merges without conflict. The full canonical version is injected post-merge.
PLACEHOLDER_ERROR = {
    "type": "object",
    "required": ["code", "message", "request_id"],
    "properties": {
        "code": {"type": "string"},
        "message": {"type": "string"},
        "request_id": {"type": "string", "format": "uuid"},
        "details": {"type": "object", "additionalProperties": {"type": "string"}},
    },
}

for filename in sorted(os.listdir(specs_dir)):
    if not filename.endswith((".yaml", ".yml", ".json")):
        continue
    filepath = os.path.join(specs_dir, filename)
    with open(filepath) as f:
        spec = json.load(f) if filename.endswith(".json") else yaml.safe_load(f)

    # Normalize OpenAPI version (.NET 10 → 3.1.1, Go → 3.1.0)
    spec["openapi"] = "3.1.0"

    # Replace ErrorResponse with identical placeholder (avoids join conflicts)
    schemas = spec.get("components", {}).get("schemas", {})
    if "ErrorResponse" in schemas:
        schemas["ErrorResponse"] = PLACEHOLDER_ERROR

    out_name = filename.rsplit(".", 1)[0] + ".yaml"
    out_path = os.path.join(preproc_dir, out_name)
    with open(out_path, "w") as f:
        yaml.dump(spec, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

    print(f"  {filename} → {out_name}")
PYEOF

PREPROC_FILES=()
for f in "$PREPROC_DIR"/*.yaml; do
    [ -f "$f" ] && PREPROC_FILES+=("$f")
done

# ─── Step 3: Merge specs ────────────────────────────────
info "Merging specs via redocly join..."
mkdir -p "$MERGED_DIR"

redocly join "${PREPROC_FILES[@]}" \
    --output "$OUTPUT" \
    --prefix-tags-with-filename=false \
    2>&1 || {
        error "redocly join failed"
        exit 1
    }

info "Merged spec written to $OUTPUT"

# ─── Step 4: Post-process — set platform metadata ───────
info "Post-processing merged spec..."

python3 << 'PYEOF'
import yaml, os

output_path = os.environ.get("OUTPUT", "merged/openapi.yaml")

with open(output_path) as f:
    spec = yaml.safe_load(f)

path_count = len(spec.get("paths", {}))

# ── 4a. Remap service tags to unified navigation groups ──
TAG_MAP = {
    # authentication-service
    "Login": "Authentication",
    "Tokens": "Authentication",
    "Password": "Authentication",
    "Sessions": "Authentication",
    "JWKS": "Authentication",
    "API Keys": "Authentication",
    # user-account-service
    "Users": "Users",
    "Registration": "Users",
    "Invitations": "Users",
    "Server Profiles": "Users",
    # sop-service
    "Service Requests": "Service of Process",
    "Submission": "Service of Process",
    "Transfers": "Service of Process",
    "Fees": "Service of Process",
    "Batch": "Service of Process",
    "Operations": "Service of Process",
    # document-service
    "Documents": "Documents",
    # partner-management-service
    "Admin": "Partners (Admin)",
    "Partner": "Partners",
    "Clients": "Partners",
    # operations-service
    "Work Orders": "Operations",
    "Assignment": "Operations",
    "Dispatch": "Operations",
    "Field Attempts": "Operations",
    "Workers": "Operations",
    "Deliverables": "Operations",
    "Documents & Packaging": "Operations",
    "Review Queue": "Operations",
    "Ops Notes": "Operations",
}

unmapped_tags = set()
for path, methods in spec.get("paths", {}).items():
    if not isinstance(methods, dict):
        continue
    for method, op in methods.items():
        if not isinstance(op, dict) or "tags" not in op:
            continue
        for t in op["tags"]:
            if t not in TAG_MAP:
                unmapped_tags.add(t)
        op["tags"] = list(dict.fromkeys(
            TAG_MAP.get(t, t) for t in op["tags"]
        ))

if unmapped_tags:
    print(f"  ⚠ WARNING: {len(unmapped_tags)} unmapped tag(s) found — these will appear as-is in the docs:")
    for t in sorted(unmapped_tags):
        print(f"    - \"{t}\"")
    print(f"  Add them to TAG_MAP in merge-specs.sh to map to a unified group.")

# ── 4b. Set unified tags ────────────────────────────────
spec["tags"] = [
    {"name": "Authentication", "description": "Login, logout, token management, password reset, sessions, API keys, and JWKS."},
    {"name": "Users", "description": "User accounts, registration, invitations, profiles, and role management."},
    {"name": "Service of Process", "description": "Service requests, submissions, transfers, fees, batch operations, and attempt tracking."},
    {"name": "Documents", "description": "Document downloads and signed URL generation."},
    {"name": "Partners", "description": "Partner self-service: pricing rules, custom statuses, transfer settings, and client management."},
    {"name": "Partners (Admin)", "description": "Super-admin partner management: create partners, update status and plans."},
    {"name": "Operations", "description": "Work orders, agent assignment, dispatch, field attempts, deliverables, document packaging, review queue, and ops notes."},
]

# ── 4c. Set unified info block ───────────────────────────
spec["info"] = {
    "title": "LegalDispatch API",
    "version": "1.0.0",
    "description": (
        "Unified API for the LegalDispatch platform. "
        "Covers authentication, user management, service of process, "
        "document management, partner operations, and work order operations.\n\n"
        "All endpoints require a Bearer JWT token unless otherwise noted. "
        "Error responses follow a standard envelope: "
        '`{ "code": "ERROR_CODE", "message": "...", "request_id": "..." }`'
    ),
    "contact": {"name": "LegalDispatch Engineering", "email": "engineering@legaldispatch.io"},
    "license": {"name": "Proprietary"},
}

# ── 4d. Set servers ──────────────────────────────────────
spec["servers"] = [
    {"url": "https://api.legaldispatch.dev", "description": "Production"},
    {"url": "https://api.staging.legaldispatch.dev", "description": "Staging"},
    {"url": "http://localhost:8080", "description": "Local development (via API gateway)"},
]

# ── 4e. Set unified security ─────────────────────────────
spec.setdefault("components", {})["securitySchemes"] = {
    "BearerAuth": {
        "type": "http",
        "scheme": "bearer",
        "bearerFormat": "JWT",
        "description": "JWT token obtained from POST /api/v1/auth/login. Pass in the Authorization header: Bearer <token>",
    }
}
spec["security"] = [{"BearerAuth": []}]

# ── 4f. Inject canonical shared schemas ──────────────────
schemas = spec.setdefault("components", {}).setdefault("schemas", {})

schemas["ErrorResponse"] = {
    "type": "object",
    "description": "Standard error envelope returned by all endpoints on failure.",
    "required": ["code", "message", "request_id"],
    "properties": {
        "code": {
            "type": "string",
            "description": "Machine-readable error code in SCREAMING_SNAKE_CASE.",
            "example": "ENTITY_NOT_FOUND",
        },
        "message": {
            "type": "string",
            "description": "Human-readable error description.",
            "example": "Document not found",
        },
        "request_id": {
            "type": "string",
            "format": "uuid",
            "description": "Correlation ID from X-Correlation-ID header or generated UUID.",
            "example": "550e8400-e29b-41d4-a716-446655440000",
        },
        "details": {
            "type": "object",
            "additionalProperties": {"type": "string"},
            "description": "Per-field validation errors. Only present for VALIDATION_ERROR.",
            "example": {"email": "Email is required"},
        },
    },
}

schemas["PaginationMeta"] = {
    "type": "object",
    "description": "Pagination metadata included in paginated list responses.",
    "required": ["page", "page_size", "total_count", "total_pages"],
    "properties": {
        "page": {"type": "integer", "description": "Current page number (1-based).", "example": 1},
        "page_size": {"type": "integer", "description": "Number of items per page.", "example": 25},
        "total_count": {"type": "integer", "description": "Total number of items across all pages.", "example": 142},
        "total_pages": {"type": "integer", "description": "Total number of pages.", "example": 6},
    },
}

# ── 4g. Add shared parameters ────────────────────────────
parameters = spec.setdefault("components", {}).setdefault("parameters", {})

parameters["X-Correlation-ID"] = {
    "name": "X-Correlation-ID",
    "in": "header",
    "required": False,
    "description": "Request correlation ID for distributed tracing. Generated if not provided.",
    "schema": {"type": "string", "format": "uuid", "example": "550e8400-e29b-41d4-a716-446655440000"},
}

parameters["page"] = {
    "name": "page",
    "in": "query",
    "required": False,
    "description": "Page number (1-based).",
    "schema": {"type": "integer", "minimum": 1, "default": 1},
}

parameters["page_size"] = {
    "name": "page_size",
    "in": "query",
    "required": False,
    "description": "Number of items per page.",
    "schema": {"type": "integer", "minimum": 1, "maximum": 100, "default": 25},
}

# ── 4h. Remove stale x-tagGroups ─────────────────────────
# redocly join auto-generates x-tagGroups from each spec's granular tags, but
# step 4a remaps all endpoint tags to unified names. The leftover x-tagGroups
# still reference the old granular names, causing empty sections in the docs UI.
# Remove them — the unified tags in 4b are sufficient for navigation.
spec.pop("x-tagGroups", None)

# ── Write back ───────────────────────────────────────────
with open(output_path, "w") as f:
    yaml.dump(spec, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

tag_names = [t["name"] for t in spec.get("tags", [])]
print(f"  Public endpoints: {path_count}")
print(f"  Tags: {', '.join(tag_names)}")
print(f"  Shared schemas: ErrorResponse, PaginationMeta")
print(f"  Shared parameters: X-Correlation-ID, page, page_size")
PYEOF

# ─── Step 5: Validate merged output ─────────────────────
info "Validating merged spec..."
if redocly lint "$OUTPUT" --config "$REPO_ROOT/.redocly.yaml" 2>/dev/null; then
    info "✓ Merged spec is valid"
else
    warn "Merged spec has lint warnings (non-fatal)"
fi

# ─── Summary ─────────────────────────────────────────────
PATHS=$(python3 -c "import yaml; d=yaml.safe_load(open('$OUTPUT')); print(len(d.get('paths',{})))")
info "Done! $OUTPUT contains $PATHS public endpoints"
