# SAP Gateway (mock)

A configurable mock of an SAP ECC 6 / NetWeaver Gateway, exposed through every
connection shape you're likely to encounter on a real system — plus SQL Server
and SurrealDB layered over the same data so non-SAP clients can integrate too.

Field codes (KUNNR / MATNR / VBELN / EBELN / LIFNR / KOSTL / …) come from the
`ConnectorExpenses` operator-console mock-ups, but here the endpoints are real
and queryable.

```
sapgateway/
├── server/   Dart shelf server — every connection surface in one process
└── app/      Flutter front-end (web, Android, iOS) to manage and inspect it
```

## Connection surfaces

All endpoints below read from the same in-memory store, persisted to
`data/runtime.json`. Editing a row through OData v2 is immediately visible from
SQL Server, SurrealDB, IDoc batches, BAPI calls, and everywhere else.

| Protocol            | Root                              | Notes                                                                  |
|---------------------|-----------------------------------|------------------------------------------------------------------------|
| OData v2            | `/sap/opu/odata/sap/`             | NetWeaver Gateway style. XML metadata, JSON / XML payloads, `$filter`. |
| OData v4            | `/sap/opu/odata4/sap/`            | OASIS v4 / S/4HANA style. `@odata.context`, `$count=true`, EDMX 4.0.    |
| SAP REST            | `/sap/rest/`                      | Plain JSON. `where`, `limit`, `offset`, `orderBy`, `fields`.            |
| SOAP / BAPI / RFC   | `/sap/bc/srt/`                    | `BAPI_*_GETLIST`, `RFC_READ_TABLE`. Accepts SOAP XML or JSON-RFC.       |
| IDoc (ALE / EDI)    | `/sap/idoc/`                      | DEBMAS06, CREMAS05, MATMAS05, ORDERS05, COND_A05, …                    |
| SQL Server 2017     | `/sqlserver/2017/`                | `@@VERSION` 14.x, compat level 140, 50k row cap.                       |
| SQL Server 2022     | `/sqlserver/2022/`                | `@@VERSION` 16.x, compat level 160, ledger / PSPO advertised.          |
| SurrealDB           | `/surrealdb/`                     | v1.x HTTP API: `/sql`, `/key/<table>[/<id>]`, `/version`.              |
| Admin (CRUD)        | `/admin/services`                 | Used by the Flutter app. `/admin/connections` lists everything above.   |

### OData query options

`$top`, `$skip`, `$orderby`, `$select`, `$format=json|xml`, `$count=true`
(v4) / `$inlinecount=allpages` (v2), and `$filter` (`eq`, `ne`, `gt`, `ge`,
`lt`, `le`, `and`, `or`, parens, plus `substringof`, `contains`, `startswith`,
`endswith`, `tolower`, `toupper`, `length`, `indexof`, `trim`).

### SOAP / BAPI

Pre-wired functions: `BAPI_CUSTOMER_GETLIST`, `BAPI_MATERIAL_GETLIST`,
`BAPI_VENDOR_GETLIST`, `BAPI_PO_GETITEMS`, `BAPI_SALESORDER_GETLIST`,
`BAPI_SALESORDER_GETITEMS`, `BAPI_GL_ACC_GETLIST`, `BAPI_COSTCENTER_GETLIST`,
`BAPI_MATERIAL_STOCK_REQ_LIST`, `BAPI_PRICES_CONDITIONS`. Generic
`RFC_READ_TABLE` and `RFC_GET_TABLE_ENTRIES` read any configured EntitySet.

Each function accepts either a real SOAP envelope (`Content-Type: text/xml`)
or a JSON body with `QUERY_TABLE`, `OPTIONS`, `FIELDS`, `ROWCOUNT`, `ROWSKIPS`.

### IDoc

`GET /sap/idoc/<TYPE>` returns a full inbound IDoc batch (XML by default,
`?format=json` for JSON). `POST /sap/idoc/<TYPE>` simulates an inbound feed and
returns the `IDOC_NUMBER` your system would have generated.

### SQL Server

Both versions accept a `POST /sqlserver/<v>/query` body of the form
`{"sql": "SELECT ..."}` or raw text. The SELECT engine supports `TOP`,
`DISTINCT`, `WHERE` (SQL or OData operators), `ORDER BY`, `OFFSET / FETCH NEXT`,
and `LIMIT / OFFSET`. Tables can be referenced bare (`CustomerSet`), qualified
by service (`ZSALES_SRV.CustomerSet`), or schema-qualified (`dbo.CustomerSet`).

### SurrealDB

`POST /surrealdb/sql` accepts a SurrealQL / SQL-ish body and returns the
canonical SurrealDB array-of-objects shape `[{"time":"…","status":"OK","result":[…]}]`.
Records carry SurrealDB-style ids: `customerset:0000001000`.

## Running the server

```bash
cd server
dart pub get
dart run bin/server.dart        # listens on :8080
```

The startup log prints the root URL for every connection surface:

```
SAP Gateway mock listening on http://0.0.0.0:8080
  OData v2:        http://0.0.0.0:8080/sap/opu/odata/sap/
  OData v4:        http://0.0.0.0:8080/sap/opu/odata4/sap/
  SAP REST:        http://0.0.0.0:8080/sap/rest/
  SOAP / BAPI:     http://0.0.0.0:8080/sap/bc/srt/
  IDoc:            http://0.0.0.0:8080/sap/idoc/
  SQL Server 2017: http://0.0.0.0:8080/sqlserver/2017/
  SQL Server 2022: http://0.0.0.0:8080/sqlserver/2022/
  SurrealDB:       http://0.0.0.0:8080/surrealdb/
  Admin API:       http://0.0.0.0:8080/admin/services
```

## Sample requests

```bash
# OData v2
curl 'http://localhost:8080/sap/opu/odata/sap/ZSALES_SRV/CustomerSet?$format=json&$top=5'

# OData v4 with count
curl 'http://localhost:8080/sap/opu/odata4/sap/ZSALES_SRV/CustomerSet?$count=true&$top=3'

# Plain REST
curl 'http://localhost:8080/sap/rest/ZMATERIAL_SRV/MaterialSet?where=Matkl%20eq%20%270010%27&limit=10'

# BAPI / RFC over JSON
curl -X POST 'http://localhost:8080/sap/bc/srt/BAPI_MATERIAL_GETLIST' \
  -H 'Content-Type: application/json' \
  -d '{"OPTIONS":["Matkl eq '\''0010'\''"],"FIELDS":["Matnr","Maktx"]}'

# Outbound IDoc batch
curl 'http://localhost:8080/sap/idoc/ORDERS05'

# SQL Server 2022
curl -X POST 'http://localhost:8080/sqlserver/2022/query' \
  -H 'Content-Type: application/json' \
  -d '{"sql":"SELECT TOP 5 * FROM ZSALES_SRV.CustomerSet WHERE Land1 = '\''US'\''"}'

# SurrealDB
curl -X POST 'http://localhost:8080/surrealdb/sql' \
  -H 'Content-Type: text/plain' \
  -d 'SELECT * FROM CustomerSet WHERE Land1 = "US" LIMIT 5;'
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

The app has three tabs:

* **Services** — manage SAP services, entity types, sets, and rows.
* **Connections** — every connection surface exposed by the gateway, with
  root URLs, sample requests, and a copy-to-clipboard button.
* **Settings** — point the app at a different gateway and reset to seed.

It defaults to `http://localhost:8080`.
