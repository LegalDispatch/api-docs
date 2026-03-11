#!/usr/bin/env bash
# merge-specs.sh — Merge individual service specs into a unified OpenAPI document.
#
# Usage: ./scripts/merge-specs.sh
#
# Prerequisites:
#   npm install -g @redocly/cli
#
# What it does:
#   1. Validates each spec in specs/
#   2. Merges them into merged/openapi.yaml using redocly join
#   3. Strips internal routes, health checks, and metrics
#   4. Validates the merged output
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPECS_DIR="$REPO_ROOT/specs"
MERGED_DIR="$REPO_ROOT/merged"
OUTPUT="$MERGED_DIR/openapi.yaml"

# ─── Colors ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ─── Preflight ───────────────────────────────────────────
if ! command -v redocly &>/dev/null; then
    error "redocly CLI not found. Install with: npm install -g @redocly/cli"
    exit 1
fi

# Collect all spec files (JSON + YAML)
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
VALID=true
for spec in "${SPEC_FILES[@]}"; do
    name="$(basename "$spec")"
    if redocly lint "$spec" --config "$REPO_ROOT/.redocly.yaml" 2>/dev/null; then
        info "  ✓ $name"
    else
        warn "  ✗ $name (lint warnings — continuing)"
    fi
done

# ─── Step 2: Merge specs ────────────────────────────────
info "Merging specs into unified document..."
mkdir -p "$MERGED_DIR"

# Build the redocly join command with all spec files
# Tags are assigned based on filename prefix
redocly join "${SPEC_FILES[@]}" \
    --output "$OUTPUT" \
    --prefix-tags-with-filename=false \
    2>&1 || {
        error "redocly join failed"
        exit 1
    }

info "Merged spec written to $OUTPUT"

# ─── Step 3: Strip internal routes ──────────────────────
info "Stripping internal routes, health checks, and metrics..."

# Use Python to filter the merged spec (available on all CI runners)
python3 << 'PYEOF'
import yaml
import sys
import os

output_path = os.environ.get("OUTPUT", "merged/openapi.yaml")

with open(output_path, "r") as f:
    spec = yaml.safe_load(f)

# Paths to strip
strip_prefixes = ("/internal", "/health", "/ready", "/metrics")

original_count = len(spec.get("paths", {}))
filtered_paths = {}
for path, methods in spec.get("paths", {}).items():
    if not any(path.startswith(prefix) for prefix in strip_prefixes):
        filtered_paths[path] = methods

spec["paths"] = filtered_paths
stripped_count = original_count - len(filtered_paths)

# Simplify security schemes to single BearerAuth
spec.setdefault("components", {})["securitySchemes"] = {
    "BearerAuth": {
        "type": "http",
        "scheme": "bearer",
        "bearerFormat": "JWT",
        "description": "JWT token obtained from POST /api/v1/auth/login. Pass in the Authorization header: Bearer <token>"
    }
}

# Set unified info block
spec["info"] = {
    "title": "LegalDispatch API",
    "version": "1.0.0",
    "description": (
        "Unified API for the LegalDispatch platform. "
        "Covers authentication, user management, service of process, "
        "document management, and partner operations.\n\n"
        "All endpoints require a Bearer JWT token unless otherwise noted. "
        "Error responses follow a standard envelope: "
        '`{ "code": "ERROR_CODE", "message": "...", "request_id": "..." }`'
    ),
    "contact": {
        "name": "LegalDispatch Engineering",
        "email": "engineering@legaldispatch.io"
    },
    "license": {
        "name": "Proprietary"
    }
}

# Write back
with open(output_path, "w") as f:
    yaml.dump(spec, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

print(f"  Stripped {stripped_count} internal/infra paths ({original_count} → {len(filtered_paths)})")
PYEOF

# ─── Step 4: Validate merged output ─────────────────────
info "Validating merged spec..."
if redocly lint "$OUTPUT" --config "$REPO_ROOT/.redocly.yaml" 2>/dev/null; then
    info "✓ Merged spec is valid"
else
    warn "Merged spec has lint warnings (non-fatal)"
fi

# ─── Summary ────────────────────────────────────────────
PATHS=$(python3 -c "import yaml; d=yaml.safe_load(open('$OUTPUT')); print(len(d.get('paths',{})))")
info "Done! $OUTPUT contains $PATHS public endpoints"
