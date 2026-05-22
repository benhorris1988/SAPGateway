# Recreate this project — single prompt

The text below is a self-contained brief you can paste to a fresh Claude Code
agent (or any capable coding agent) sitting in an empty git repository. It
specifies *what* to build at roughly the right abstraction level — file
layout, surfaces, data shapes, UI structure — without dictating every line.
A capable agent should be able to land within a few hundred lines of the
current branch from this alone.

---

## Prompt

> Build a **mock SAP NetWeaver Gateway** with a **Flutter admin app**, a
> **REST integration layer** that mirrors data into an external
> **SurrealDB**, and a **persistent audit log**. The shape of the SAP data
> should look like a real SAP ECC/S/4HANA system: services named
> `Z..._SRV`, EntityTypes with SAP field codes (`KUNNR`, `MATNR`, `VBELN`,
> `LIFNR`, `EBELN`, `PERNR`, `BELNR`, `WRBTR`, `WAERS`, `KOSTL`, `SAKNR`
> etc.), EDM types (`Edm.String`, `Edm.Decimal`, `Edm.DateTime`, ...).
>
> ### Repo layout
> ```
> ├── server/   Dart shelf server (Dart SDK ^3.4.0)
> └── app/      Flutter app, lib/ only (platforms regenerated via `flutter create .`)
> ```
> The app's platform folders (`android/`, `ios/`, `web/`, ...) must NOT be
> checked in — gitignore them and tell the user to run
> `flutter create . --platforms=web,android,ios --org com.sapgateway`.
>
> ### Server (Dart, package `shelf` + `shelf_router`, no other deps)
>
> Expose four mounts under a CORS-enabled pipeline with request logging:
>
> 1. **OData v2** at `/sap/opu/odata/sap/` — service catalog, per-service
>    document, `$metadata` (EDMX), and EntitySet collections.
>    Implement query options: `$top`, `$skip`, `$orderby`, `$select`,
>    `$inlinecount=allpages`, `$format=json|xml`, and a `$filter` subset
>    (`eq`/`ne`/`gt`/`ge`/`lt`/`le`, `and`/`or`, parens, `substringof`,
>    `startswith`, `endswith`). Wrap rows in `{ d: { results: [...] } }`
>    with a `__metadata` block per row.
>    GET/POST/PUT/PATCH/MERGE/DELETE on EntitySets and keyed items
>    (`Set('key')` and `Set(Field1='a',Field2='b')`).
>
> 2. **Clean REST** at `/api/v1/` over the same data:
>    - `GET /` discovery
>    - `GET /{collection}` list with `?limit&offset&sort&search` + any
>      other query param as equality filter; response shape
>      `{ data, total, limit, offset }`
>    - `GET/PUT/PATCH/DELETE /{collection}/{id}`, `POST /{collection}`
>    - Collection name = EntitySet name lowercased, trailing `Set`
>      stripped, `s` appended (`CustomerSet` → `customers`,
>      `ExpenseSet` → `expenses`). Composite keys joined with commas.
>    - Expose the collection-name → (EntitySet, EntityType) lookup as a
>      public method so other handlers can reuse it.
>
> 3. **Admin JSON API** at `/admin/` for schema + row CRUD that the
>    Flutter app uses to manage services, entity types, properties
>    (including renames that cascade to row keys), entity sets and rows.
>    Plus `POST /admin/reset` to restore the seed.
>
> 4. **Integration layer** at `/api/v1/integration/`:
>    - `GET /config` returns SurrealDB connection (password redacted as
>      a boolean `passwordSet`) plus all mappings
>    - `PUT /config/surreal` updates connection (endpoint, namespace,
>      database, username, password)
>    - `PUT/DELETE /config/mappings/{collection}` upsert/remove a
>      mapping. A **mapping** binds one REST collection to one
>      SurrealDB table with a direction (`inbound`/`outbound`/`both`),
>      an optional rename map `{ sapField: surrealField }`, and an
>      optional `pushFilter` (equality predicate gating push)
>    - `POST /test-connection` probes SurrealDB `/version`
>    - `POST /pull/{collection}?dryRun=` SAP → Surreal (upsert via
>      `PUT /key/{table}/{id}` with Basic auth + `NS`/`DB` headers)
>    - `POST /push/{collection}?dryRun=` Surreal → SAP (read via
>      `GET /key/{table}`, upsert into the in-process gateway store,
>      apply rename map inverted, honour `pushFilter`, backfill the
>      single-key field from the Surreal record id if missing)
>    - `GET /audit?limit=&action=&collection=` and `DELETE /audit`
>
>    Every run, config change and connection test appends an
>    **AuditEvent** to a persistent log (`data/audit.json`) with
>    timestamp, action, collection, status (`success`/`error`/`dry-run`),
>    `dryRun` flag, rowsScanned/Created/Updated/Skipped/Failed,
>    durationMs and (truncated) error excerpt. Cap retained events at
>    ~5000 with FIFO trim. Persist connection + mappings to
>    `data/integration.json`. Seed default mappings: `expenses` (both
>    ways, push filter `Status=SUBMITTED`), and read-only inbound for
>    `customers`/`materials`/`vendors`.
>
>    The SurrealDB client should use `dart:io` `HttpClient` (no http
>    package), send `Surreal-NS`/`NS` and `Surreal-DB`/`DB` headers,
>    Basic auth, and tolerate Surreal's statement envelope
>    (`[{result, status}]`) on both read and write paths.
>
> ### Persistence
> - Gateway state → `server/data/runtime.json`
> - Integration config → `server/data/integration.json`
> - Audit log → `server/data/audit.json`
>
> All three gitignored. The server boots the seed if `runtime.json` is
> absent. A `--data` CLI flag overrides the path; the integration and
> audit files live in the same directory.
>
> ### Seed data (SAP-style)
> Eight services. Use real SAP field codes throughout — agents tend to
> default to friendly English names; resist that.
> - `ZSALES_SRV` — Customer (KUNNR/NAME1/LAND1/KTOKD/ERDAT),
>   SalesOrder (VBELN/KUNNR/AUDAT/NETWR/WAERK), SalesOrderItem
>   (VBELN/POSNR/MATNR/KWMENG/VRKME — composite key)
> - `ZMATERIAL_SRV` — Material (MATNR/MAKTX/MATKL/MEINS/MTART)
> - `ZVENDOR_SRV` — Vendor (LIFNR/NAME1/LAND1/STCD1)
> - `ZPURCH_SRV` — PurchaseOrder (EBELN/LIFNR/BEDAT/WAERS)
> - `ZPRICE_SRV` — PricingCondition (KNUMH/KSCHL/DATAB/DATBI/KBETR)
> - `ZSTOCK_SRV` — Stock (MATNR/WERKS/LABST/MEINS — composite key)
> - `ZFIN_SRV` — GLAccount (SAKNR/TXT50/MWSKZ), CostCenter
>   (KOSTL/KTEXT/BUKRS)
> - `ZEXPENSE_SRV` — Expense
>   (BELNR/PERNR/BLDAT/WRBTR/WAERS/KOSTL/SAKNR/SGTXT/Status)
>
> A few representative rows per set (3–6), with real-looking SAP
> formatting: zero-padded keys (`0000001000`), uppercase country codes,
> stringified decimals (`"12450.00"`), ISO datetimes (`2026-05-10T00:00:00`).
>
> ### Flutter app (Dart SDK ^3.4.0, Flutter ≥3.22.0)
>
> Deps: `flutter`, `http`, `shared_preferences`, `provider`. Nothing else.
>
> - Single `AppState` (ChangeNotifier) owning the gateway base URL via
>   `SharedPreferences` and exposing a `GatewayApi` client
> - Material 3 theme, dark + light, colour seed `#1E3A5F`
> - Responsive shell: `NavigationRail` on width ≥720, `NavigationBar`
>   below — three destinations:
>   - **Services** — list/create/edit/delete services and their entity
>     types/properties/sets; row browser per set with add/edit/delete;
>     property rename must cascade through existing rows
>   - **Integration** — three sub-tabs:
>     - *Connection*: edit endpoint/ns/db/user/password, Save + Test
>       (Test shows a coloured banner with the version or error)
>     - *Mappings*: card per mapping with a direction chip
>       (Pull-only / Push-only / Bidirectional), per-card buttons for
>       Pull, Dry-run pull, Push, Dry-run push, a live run summary
>       (scanned/created/updated/skipped/failed/durationMs and error
>       excerpts), add/edit/delete via dialog
>     - *Audit*: timeline of events with action-icon, status colour,
>       row stats and error detail; Clear button with confirm
>   - **Settings** — base URL + Reset-to-seed (with confirm dialog)
> - One `GatewayException(statusCode, message)` class; the API client
>   parses `{ error: "..." }` bodies and surfaces a single banner per
>   screen
> - Passwords are write-only end-to-end: never returned by `GET
>   /config`; the UI shows "A password is already stored" when the
>   server reports `passwordSet: true`
>
> ### Things to keep tidy
> - No comments unless the *why* is non-obvious. No docstrings on
>   every method.
> - No extra dependencies beyond what's listed above.
> - Don't carry forward "// removed" comments or backwards-compat
>   shims while building greenfield.
> - When mounting routes, put the more specific prefix first
>   (`/api/v1/integration/` before `/api/v1/`).
> - All persistence helpers should `mkdir -p` the parent directory
>   before writing.
>
> ### README
> Cover: running the server, running the Flutter app (incl. the
> `flutter create .` step), the OData query subset, the REST shape,
> the integration endpoints, and a worked example for writing an
> expense back to SAP via REST and via the integration push.
>
> ### Definition of done
> - `dart run bin/server.dart` boots without errors and serves all four
>   surfaces
> - `curl /api/v1/expenses` returns the seed rows; `POST` creates one;
>   `PATCH /api/v1/expenses/{id}` updates status
> - `PUT /api/v1/integration/config/surreal` + `POST /test-connection`
>   round-trips against a real SurrealDB (HTTP API)
> - Pull and Push runs against `expenses` produce audit events with
>   correct counts; dry-run leaves both stores unchanged
> - Flutter app boots on web, all three tabs render, and the
>   Integration tab can drive a full Pull → Push → Audit cycle
> - All persistence files survive a server restart

---

## Notes on how to use this prompt

- **Run it on a fresh repo.** The brief assumes empty starting state.
  If you point an agent at the existing repo it'll get confused about
  what to overwrite — better to branch from `main` and let it build
  fresh against the spec.
- **Expect minor drift.** Field-by-field reproduction isn't the goal;
  surface-by-surface reproduction is.
- **Iterate, don't one-shot.** This particular project landed across
  three turns:
  1. Build the mock OData gateway + Flutter admin
  2. Add the REST API and the expenses write-back
  3. Add the SurrealDB integration with audit and integration UI

  Splitting the prompt the same way often produces better results
  than handing the agent the whole thing at once.
