# FJ JSON API

REST API for programmatic access to fj data. Requires bearer token authentication.

## Authentication

All endpoints require a bearer token in the `Authorization` header:

```
Authorization: Bearer fj_sk_...
```

Create API keys via the web UI at `/keys` or manage them in `FJ_HOME/.api_keys.json`.

## Endpoints

### Health

**GET /api/v1/health** - Health check (no authentication required)

```json
{
  "status": "ok"
}
```

### Clients

**GET /api/v1/clients** - List all clients

```json
{
  "clients": [
    {
      "shortname": "acme",
      "company-name": "ACME Corp",
      "c/o-name": null,
      "street": "123 Main St",
      "areacode": "12345",
      "city": "Springfield",
      "country": "US",
      "tax_uid": "US123456789",
      "remarks": null,
      "created": "2024-01-15T10:30:00Z",
      "updated": "2024-01-15T10:30:00Z",
      "revision": 1
    }
  ]
}
```

**GET /api/v1/clients/{shortname}** - Get single client

```json
{
  "shortname": "acme",
  "company-name": "ACME Corp",
  "c/o-name": null,
  "street": "123 Main St",
  "areacode": "12345",
  "city": "Springfield",
  "country": "US",
  "tax_uid": "US123456789",
  "remarks": null,
  "created": "2024-01-15T10:30:00Z",
  "updated": "2024-01-15T10:30:00Z",
  "revision": 1
}
```

### Rates

**GET /api/v1/rates** - List all rates

```json
{
  "rates": [
    {
      "shortname": "standard",
      "hourly": 150,
      "hours_per_day": 8,
      "daily": 1200,
      "weekly": 6000,
      "remarks": null,
      "created": "2024-01-15T10:30:00Z",
      "updated": "2024-01-15T10:30:00Z",
      "revision": 1
    }
  ]
}
```

**GET /api/v1/rates/{shortname}** - Get single rate

```json
{
  "shortname": "standard",
  "hourly": 150,
  "hours_per_day": 8,
  "daily": 1200,
  "weekly": 6000,
  "remarks": null,
  "created": "2024-01-15T10:30:00Z",
  "updated": "2024-01-15T10:30:00Z",
  "revision": 1
}
```

### Invoices

**GET /api/v1/invoices** - List all invoices

```json
{
  "invoices": [
    {
      "id": "2024-001",
      "due_date": "2024-01-29",
      "paid_date": null,
      "client_shortname": "acme",
      "date": "2024-01-15",
      "project_name": "Website Redesign",
      "oms_project": null,
      "year": 2024,
      "applicable_rates": "standard",
      "leistungszeitraum": "January 2024",
      "leistungszeitraum_bis": null,
      "terms_of_payment": "binnen 14 Tagen",
      "coverletter": {
        "greeting": null
      },
      "footer": {
        "show_agb": true
      },
      "vat": {
        "percent": 0,
        "show_exempt_notice": true
      },
      "remarks": null,
      "draft": false,
      "created": "2024-01-15T10:30:00Z",
      "updated": "2024-01-15T10:30:00Z",
      "revision": 1,
      "total": 150000
    }
  ]
}
```

Note: `total` is in EUR (150000 = €150,000.00).

**GET /api/v1/invoices/{id}** - Get single invoice

```json
{
  "id": "2024-001",
  "due_date": "2024-01-29",
  "paid_date": null,
  "client_shortname": "acme",
  "date": "2024-01-15",
  "project_name": "Website Redesign",
  "oms_project": null,
  "year": 2024,
  "applicable_rates": "standard",
  "leistungszeitraum": "January 2024",
  "leistungszeitraum_bis": null,
  "terms_of_payment": "binnen 14 Tagen",
  "coverletter": {
    "greeting": null
  },
  "footer": {
    "show_agb": true
  },
  "vat": {
    "percent": 0,
    "show_exempt_notice": true
  },
  "remarks": null,
  "draft": false,
  "created": "2024-01-15T10:30:00Z",
  "updated": "2024-01-15T10:30:00Z",
  "revision": 1,
  "total": 150000
}
```

**POST /api/v1/invoices/{id}/paid** - Mark invoice as paid

Sets `paid_date` to today. Returns error if already paid.

```json
{
  "success": true,
  "invoice": {
    "id": "2024-001",
    "due_date": "2024-01-29",
    "paid_date": "2024-11-27",
    "client_shortname": "acme",
    "date": "2024-01-15",
    "project_name": "Website Redesign",
    "oms_project": null,
    "year": 2024,
    "applicable_rates": "standard",
    "leistungszeitraum": "January 2024",
    "leistungszeitraum_bis": null,
    "terms_of_payment": "binnen 14 Tagen",
    "coverletter": {
      "greeting": null
    },
    "footer": {
      "show_agb": true
    },
    "vat": {
      "percent": 0,
      "show_exempt_notice": true
    },
    "remarks": null,
    "draft": false,
    "created": "2024-01-15T10:30:00Z",
    "updated": "2024-11-27T14:00:00Z",
    "revision": 1,
    "total": 150000
  }
}
```

### Offers

**GET /api/v1/offers** - List all offers

```json
{
  "offers": [
    {
      "id": "2024-001",
      "accepted_date": null,
      "declined_date": null,
      "client_shortname": "acme",
      "date": "2024-01-10",
      "project_name": "New Feature",
      "oms_project": null,
      "applicable_rates": "standard",
      "valid_thru": "2024-02-10",
      "coverletter": {
        "greeting": null,
        "show_rates": false
      },
      "devtime": "2 weeks",
      "footer": {
        "show_allnetto": true,
        "show_agb": true
      },
      "vat": {
        "percent": 0,
        "show_exempt_notice": true
      },
      "remarks": null,
      "draft": false,
      "created": "2024-01-10T10:30:00Z",
      "updated": "2024-01-10T10:30:00Z",
      "revision": 1,
      "total": 600000
    }
  ]
}
```

**GET /api/v1/offers/{id}** - Get single offer

```json
{
  "id": "2024-001",
  "accepted_date": null,
  "declined_date": null,
  "client_shortname": "acme",
  "date": "2024-01-10",
  "project_name": "New Feature",
  "oms_project": null,
  "applicable_rates": "standard",
  "valid_thru": "2024-02-10",
  "coverletter": {
    "greeting": null,
    "show_rates": false
  },
  "devtime": "2 weeks",
  "footer": {
    "show_allnetto": true,
    "show_agb": true
  },
  "vat": {
    "percent": 0,
    "show_exempt_notice": true
  },
  "remarks": null,
  "draft": false,
  "created": "2024-01-10T10:30:00Z",
  "updated": "2024-01-10T10:30:00Z",
  "revision": 1,
  "total": 600000
}
```

**POST /api/v1/offers/{id}/accept** - Mark offer as accepted

Sets `accepted_date` to today. Returns error if already accepted or declined.

```json
{
  "success": true,
  "offer": {
    "id": "2024-001",
    "accepted_date": "2024-11-27",
    "declined_date": null,
    "client_shortname": "acme",
    "date": "2024-01-10",
    "project_name": "New Feature",
    "oms_project": null,
    "applicable_rates": "standard",
    "valid_thru": "2024-02-10",
    "coverletter": {
      "greeting": null,
      "show_rates": false
    },
    "devtime": "2 weeks",
    "footer": {
      "show_allnetto": true,
      "show_agb": true
    },
    "vat": {
      "percent": 0,
      "show_exempt_notice": true
    },
    "remarks": null,
    "draft": false,
    "created": "2024-01-10T10:30:00Z",
    "updated": "2024-11-27T14:00:00Z",
    "revision": 1,
    "total": 600000
  }
}
```

**POST /api/v1/offers/{id}/reject** - Mark offer as rejected

Sets `declined_date` to today. Returns error if already accepted or declined.

```json
{
  "success": true,
  "offer": {
    "id": "2024-001",
    "accepted_date": null,
    "declined_date": "2024-11-27",
    "client_shortname": "acme",
    "date": "2024-01-10",
    "project_name": "New Feature",
    "oms_project": null,
    "applicable_rates": "standard",
    "valid_thru": "2024-02-10",
    "coverletter": {
      "greeting": null,
      "show_rates": false
    },
    "devtime": "2 weeks",
    "footer": {
      "show_allnetto": true,
      "show_agb": true
    },
    "vat": {
      "percent": 0,
      "show_exempt_notice": true
    },
    "remarks": null,
    "draft": false,
    "created": "2024-01-10T10:30:00Z",
    "updated": "2024-11-27T14:00:00Z",
    "revision": 1,
    "total": 600000
  }
}
```

### Summary

**GET /api/v1/summary** - Get financial summary

```json
{
  "invoices": {
    "total": 15,
    "open": 3,
    "total_amount": 4500000,
    "open_amount": 450000
  },
  "offers": {
    "total": 8,
    "open": 2,
    "pending_amount": 300000,
    "accepted_amount": 1200000
  }
}
```

All amounts are in EUR.

## Error Responses

All errors return JSON with an `error` field:

```json
{"error": "Invalid or missing API key"}
```

```json
{"error": "Client not found"}
```

```json
{"error": "Invoice not found"}
```

```json
{"error": "Invoice is already marked as paid"}
```

```json
{"error": "Offer not found"}
```

```json
{"error": "Offer is already accepted"}
```

```json
{"error": "Offer is already declined"}
```

```json
{"error": "Unknown API endpoint"}
```

```json
{"error": "Use POST for status changes"}
```

```json
{"error": "Invalid invoice action"}
```

```json
{"error": "Invalid offer action"}
```

HTTP status codes:
- `401 Unauthorized` - Missing or invalid API key
- `404 Not Found` - Resource not found
- `400 Bad Request` - Invalid request or action not allowed
- `405 Method Not Allowed` - Wrong HTTP method for endpoint
