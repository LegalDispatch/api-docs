#!/usr/bin/env bash
# validate-spec.sh — Lint and validate OpenAPI specs.
#
# Usage:
#   ./scripts/validate-spec.sh              # validate all specs + merged
#   ./scripts/validate-spec.sh specs/       # validate individual specs only
#   ./scripts/validate-spec.sh merged/      # validate merged spec only
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

if ! command -v redocly &>/dev/null; then
    error "redocly CLI not found. Install with: npm install -g @redocly/cli"
    exit 1
fi

TARGET="${1:-all}"
ERRORS=0

validate_dir() {
    local dir="$1"
    local label="$2"

    info "Validating $label..."
    for ext in yaml yml json; do
        for spec in "$dir"/*."$ext"; do
            [ -f "$spec" ] || continue
            name="$(basename "$spec")"
            if redocly lint "$spec" --config "$REPO_ROOT/.redocly.yaml" 2>/dev/null; then
                info "  ✓ $name"
            else
                warn "  ✗ $name"
                ERRORS=$((ERRORS + 1))
            fi
        done
    done
}

case "$TARGET" in
    specs/|specs)
        validate_dir "$REPO_ROOT/specs" "individual specs"
        ;;
    merged/|merged)
        validate_dir "$REPO_ROOT/merged" "merged spec"
        ;;
    all)
        validate_dir "$REPO_ROOT/specs" "individual specs"
        validate_dir "$REPO_ROOT/merged" "merged spec"
        ;;
    *)
        error "Unknown target: $TARGET (use 'specs/', 'merged/', or 'all')"
        exit 1
        ;;
esac

if [ "$ERRORS" -gt 0 ]; then
    warn "$ERRORS spec(s) had lint warnings"
    exit 1
else
    info "All specs valid ✓"
fi
