# Changelog

> API changes across releases.

## Versioning

The LegalDispatch API is versioned via the URL path (`/api/v1/...`). Breaking changes will be introduced under a new version prefix.

Non-breaking additions (new endpoints, new optional fields) are added to the current version without a version bump.

---

## v1.0.0 — Initial Release

**Unified spec published.** 62 public endpoints across 5 services.

### Authentication (`/api/v1/auth`)

- Login (single + multi-partner), refresh, logout, logout-all
- Password management: change, reset-request, reset
- Session management: list, revoke
- API key management: create, list, revoke, rotate
- JWKS public key endpoint

### Users (`/api/v1/users`)

- User registration, profile, partner context
- Admin user management: list, create, deactivate, update roles
- Permission and role management

### Service of Process (`/api/v1/service-requests`)

- Service request lifecycle: create, list, get, update, cancel
- Attempt tracking: create, update
- Document attachment management

### Documents (`/api/v1/documents`)

- Signed URL generation for document access

### Partners (`/api/v1/partners`)

- Partner onboarding and profile management
- Client management: create, list, update, deactivate
- Admin partner management: list, create, update, suspend
