# Pagination

> How to paginate list endpoints in the LegalDispatch API.

## Query Parameters

List endpoints support cursor-free page-based pagination:

| Parameter   | Type    | Default | Description                 |
| ----------- | ------- | ------- | --------------------------- |
| `page`      | integer | 1       | Page number (1-based)       |
| `page_size` | integer | 25      | Items per page (max varies) |

### Example

```bash
curl -X GET "/api/v1/users?page=2&page_size=10" \
  -H "Authorization: Bearer <token>"
```

## Response Shape

Paginated responses wrap the result list in a `data` array and include a `pagination` metadata object:

```json
{
  "data": [
    { "id": "uuid-1", "email": "alice@example.com", "...": "..." },
    { "id": "uuid-2", "email": "bob@example.com", "...": "..." }
  ],
  "pagination": {
    "page": 2,
    "page_size": 10,
    "total_count": 142,
    "total_pages": 6
  }
}
```

### Pagination Metadata

| Field         | Type    | Description                    |
| ------------- | ------- | ------------------------------ |
| `page`        | integer | Current page number            |
| `page_size`   | integer | Items per page                 |
| `total_count` | integer | Total items matching the query |
| `total_pages` | integer | Total number of pages          |

## Iterating All Pages

To fetch all results, increment `page` until `page >= total_pages`:

```python
page = 1
all_items = []

while True:
    resp = requests.get(f"/api/v1/users?page={page}&page_size=50", headers=headers)
    body = resp.json()
    all_items.extend(body["data"])
    if page >= body["pagination"]["total_pages"]:
        break
    page += 1
```

## Notes

- Requesting a page beyond `total_pages` returns an empty `data` array.
- `page_size` upper limits vary by endpoint — check the API reference for specifics.
- All JSON fields use `snake_case`.
