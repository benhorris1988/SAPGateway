# SAP Gateway (mock)

A configurable mock of an **SAP NetWeaver Gateway / OData v2** service, plus a
Flutter front-end to manage it.

The shape of the data (services, EntitySets, SAP field codes like KUNNR/MATNR/VBELN)
is lifted from the `ConnectorExpenses` operator-console mock-ups, but here the
endpoints are real and queryable.

```
sapgateway/
├── server/   Dart shelf server: OData v2 endpoints + JSON admin API
└── app/      Flutter front-end (web, Android, iOS) to manage the gateway
```

## Running the server

```bash
cd server
dart pub get
dart run bin/server.dart        # listens on :8080
```

REST API (recommended):    `http://localhost:8080/api/v1/`
OData root (legacy):       `http://localhost:8080/sap/opu/odata/sap/`
Per-service metadata:      `http://localhost:8080/sap/opu/odata/sap/ZSALES_SRV/$metadata`
EntitySet (JSON):          `http://localhost:8080/sap/opu/odata/sap/ZSALES_SRV/CustomerSet?$format=json&$top=5`
Admin (JSON):              `http://localhost:8080/admin/services`

Supported OData v2 query options: `$top`, `$skip`, `$orderby`, `$select`,
`$inlinecount=allpages`, `$format=json|xml`, and a `$filter` subset
(`eq`, `ne`, `gt`, `ge`, `lt`, `le`, `and`, `or`, parens, `substringof`,
`startswith`, `endswith`).

## REST API

A flat, REST-style surface mounted at `/api/v1/` exposes the same data
as the OData layer but in a shape that's nicer to consume from non-SAP
clients. It is the recommended interface for reading data and for
writing expenses back into SAP.

```
GET    /api/v1/                       # discovery: list of collections
GET    /api/v1/{collection}           # list (paged, filterable, sortable)
GET    /api/v1/{collection}/{id}      # single entity
POST   /api/v1/{collection}           # create  -> 201 + entity
PUT    /api/v1/{collection}/{id}      # replace -> 200 + entity
PATCH  /api/v1/{collection}/{id}      # partial -> 200 + entity
DELETE /api/v1/{collection}/{id}      # 204
```

Collection name is the EntitySet name lowercased, with the trailing
`Set` stripped and `s` appended — so `CustomerSet` → `customers`,
`ExpenseSet` → `expenses`, `MaterialSet` → `materials`, etc.
Composite keys are joined with commas in declaration order, e.g.
`/api/v1/salesorderitems/0000010001,000010`.

List query parameters:

| param    | meaning                                                       |
|----------|---------------------------------------------------------------|
| `limit`  | page size (default 50, `0` for no limit)                      |
| `offset` | rows to skip                                                  |
| `sort`   | comma-separated fields; prefix `-` for descending             |
| `search` | case-insensitive substring across all fields                  |
| _other_  | any other param is treated as an equality filter on that field |

List response shape:

```json
{ "data": [ ... ], "total": 123, "limit": 50, "offset": 0 }
```

### Reading

```bash
# all customers in the US, newest first
curl 'http://localhost:8080/api/v1/customers?Land1=US&sort=-Erdat'

# free-text search across materials
curl 'http://localhost:8080/api/v1/materials?search=pipe'
```

### Writing expenses back to SAP

```bash
# create a new expense document
curl -X POST http://localhost:8080/api/v1/expenses \
  -H 'content-type: application/json' \
  -d '{
        "Belnr":  "1900000099",
        "Pernr":  "00010001",
        "Bldat":  "2026-05-22T00:00:00",
        "Wrbtr":  "42.50",
        "Waers":  "GBP",
        "Kostl":  "0000010000",
        "Saknr":  "0000500000",
        "Sgtxt":  "Client lunch",
        "Status": "SUBMITTED"
      }'

# patch its status once approved
curl -X PATCH http://localhost:8080/api/v1/expenses/1900000099 \
  -H 'content-type: application/json' \
  -d '{"Status": "POSTED"}'
```

## Running the Flutter app

The `app/` directory only contains the cross-platform `lib/` source and
`pubspec.yaml`. Platform folders (`android/`, `ios/`, `web/`, etc.) are
intentionally not committed — generate them locally:

```bash
cd app
flutter create . --platforms=web,android,ios --org com.sapgateway
flutter pub get

# Web
flutter run -d chrome

# Android
flutter run -d <android-device-id>

# iOS (on macOS only)
flutter run -d <ios-device-id>
```

The app defaults to `http://localhost:8080` — change the **Gateway URL** in
the Settings tab to point at a remote server.
