# Recreate this project — single prompt

The text below is a self-contained brief you can paste to a fresh Claude Code
agent (or any capable coding agent) sitting in an empty git repository. It
specifies *what* to build at roughly the right abstraction level — file
layout, surfaces, data shapes, UI structure — without dictating every line.
A capable agent should be able to land within a few hundred lines of the
current branch from this alone.

---

## Prompt

> Build a **mock SAP ECC 6 REST API** with a **Flutter admin app**, a
> **bidirectional integration layer** that mirrors data into an external
> **SurrealDB**, and a **persistent audit log**.
>
> The real target system is **SAP ECC 6**. It is *not* assumed to sit
> behind SAP NetWeaver Gateway — the agreed integration contract is
> **REST APIs, inbound and outbound**, where:
>
> - **inbound** = reading data *from* SAP into the rest of the world
>   (customers, materials, vendors, HR/employees, etc.)
> - **outbound** = writing data *to* SAP (primarily expenses, but the
>   shape should generalise)
>
> The data and field names must look like real ECC 6: services named
> `Z..._SRV`, entity types using SAP DDIC field codes (`KUNNR`, `MATNR`,
> `VBELN`, `LIFNR`, `EBELN`, `PERNR`, `BELNR`, `WRBTR`, `WAERS`,
> `KOSTL`, `SAKNR`, ...), and SAP-style formatting (zero-padded keys
> like `0000001000`, uppercase country codes, stringified decimals,
> ISO datetimes). Schema metadata uses plain JSON type tags —
> `{ type: 'string'|'decimal'|'datetime'|'boolean'|'int', maxLength?,
> precision?, scale?, nullable?, label? }`. **Do not use OData / EDMX /
> Edm.* type names** — the wire format is pure REST/JSON.
>
> ### Repo layout
> ```
> ├── server/   Dart shelf server (Dart SDK ^3.4.0)
> └── app/      Flutter web app, lib/ only (web/ regenerated via `flutter create .`)
> ```
> Target **web only** — no Android, iOS, desktop. The generated `web/`
> folder must NOT be checked in; gitignore it and tell the user to run
> `flutter create . --platforms=web --org com.sapgateway`.
>
> ### Server (Dart, package `shelf` + `shelf_router`, no other deps)
>
> Expose three mounts under a CORS-enabled pipeline with request logging.
> **REST is the only consumer surface — do not implement OData / EDMX /
> `$metadata` / `$filter` / `$top`-style query options.** If a future
> SAP-side consumer needs OData specifically, that's a separate request.
>
> 1. **REST** at `/api/v1/` — *the* contract for both inbound reads and
>    outbound writes:
>    - `GET /` discovery (lists collections, entity types, row counts)
>    - `GET /{collection}` list with `?limit&offset&sort&search` + any
>      other query param treated as an equality filter; response shape
>      `{ data, total, limit, offset }`
>    - `GET/PUT/PATCH/DELETE /{collection}/{id}`, `POST /{collection}`
>    - Collection name = entity-set name lowercased, trailing `Set`
>      stripped, `s` appended (`CustomerSet` → `customers`,
>      `ExpenseSet` → `expenses`). Composite keys joined with commas.
>    - Expose the collection-name → (EntitySet, EntityType) lookup as a
>      public method so other handlers can reuse it.
>
> 2. **Admin JSON API** at `/admin/` for schema + row CRUD that the
>    Flutter app uses to manage services, entity types, properties
>    (including renames that cascade to row keys), entity sets and rows.
>    Plus `POST /admin/reset` to restore the seed.
>
> 3. **Integration layer** at `/api/v1/integration/`:
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
>    `data/integration.json`. Seed default mappings to match the agreed
>    scope: `expenses` bidirectional with push filter `Status=SUBMITTED`,
>    plus read-only inbound (`inbound`) for HR collections —
>    `employees`, `orgunits`, `positions`, `absences`, `timesheets` —
>    and the supporting ECC reads (`customers`/`materials`/`vendors`).
>
>    The SurrealDB client should use `dart:io` `HttpClient` (no http
>    package), send `Surreal-NS`/`NS` and `Surreal-DB`/`DB` headers,
>    Basic auth, and tolerate Surreal's statement envelope
>    (`[{result, status}]`) on both read and write paths.
>
> ### Auth (TBD — leave pluggable)
>
> The auth scheme on the real ECC 6 REST endpoints is **not yet
> agreed**. Don't hard-code one. Build the mock so that:
>
> - The REST + Admin + Integration handlers all pass through a single
>   shelf middleware (`authMiddleware`) that today is a no-op (allow
>   all) but is the one place a future scheme drops in.
> - The Flutter `GatewayApi` builds every request via a single
>   `_authHeaders()` hook that today returns `{}` but is the one place
>   credentials get attached.
> - Settings has stub fields for "Auth mode" with `none` selected by
>   default and `basic` / `oauth2-client-credentials` / `oauth2-saml-bearer`
>   listed but disabled. Make it obvious where to wire them up.
> - SurrealDB-side auth (for the integration layer's external calls) is
>   separate and *is* implemented today (Basic auth + NS/DB headers).
>   Don't conflate the two.
>
> The mock itself should remain runnable with no auth so the demo path
> stays one command.
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
> ### Seed data (ECC 6 DDIC field codes)
>
> The agreed scope is **HR + Expenses inbound/outbound**, so the HR
> services need to be present and convincing — these are what most
> integrations actually pull. Other ECC areas are included as supporting
> context (an HR-only mock looks suspiciously narrow).
>
> Use real ECC 6 DDIC field codes throughout — agents tend to default
> to friendly English names; resist that.
>
> **HR space (priority)** — fields straight from PA/OM tables:
> - `ZHR_EMPLOYEE_SRV` — Employee (PERNR/NACHN/VORNA/GBDAT/BEGDA/ENDDA/
>   WERKS/PERSG/PERSK), Address (PERNR/SUBTY/STRAS/ORT01/PSTLZ/LAND1)
> - `ZHR_ORG_SRV` — OrgUnit (ORGEH/ORGTX/PLVAR/BEGDA/ENDDA),
>   Position (PLANS/PLSTX/ORGEH/STELL/BEGDA/ENDDA),
>   Job (STELL/STLTX/BEGDA/ENDDA)
> - `ZHR_TIME_SRV` — Absence (PERNR/AWART/BEGDA/ENDDA/ABWTG),
>   Timesheet (PERNR/WORKD/STDAZ/LSTAR/KOSTL)
> - `ZHR_PAYROLL_SRV` — PayrollResult (PERNR/SEQNR/FPPER/PAYTY/BETRG/WAERS),
>   WageType (LGART/LGTXT)
>
> **Expenses (priority — outbound write target):**
> - `ZEXPENSE_SRV` — Expense
>   (BELNR/PERNR/BLDAT/WRBTR/WAERS/KOSTL/SAKNR/SGTXT/Status)
>
> **Supporting ECC services:**
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
>
> A few representative rows per set (3–6), with real-looking SAP
> formatting: zero-padded keys (`0000001000`), uppercase country codes,
> stringified decimals (`"12450.00"`), ISO datetimes (`2026-05-10T00:00:00`).
>
> ### Flutter app (web only — Dart SDK ^3.4.0, Flutter ≥3.22.0)
>
> Deps: `flutter`, `http`, `shared_preferences`, `provider`. Nothing
> else. Don't add anything mobile-specific.
>
> - Single `AppState` (ChangeNotifier) owning the gateway base URL via
>   `SharedPreferences` and exposing a `GatewayApi` client
> - Material 3 theme, dark + light, colour seed `#1E3A5F`
> - Responsive shell: `NavigationRail` on width ≥720, `NavigationBar`
>   below (the breakpoint matters on web for narrow browser windows) —
>   three destinations:
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
> `flutter create .` step), the REST shape (collection naming, query
> params, response envelope), the integration endpoints, and a worked
> example for writing an expense back to SAP via REST and via the
> integration push.
>
> ### Definition of done
> - `dart run bin/server.dart` boots without errors and serves the
>   REST, Admin and Integration mounts
> - `curl /api/v1/employees` and `curl /api/v1/expenses` return the seed
>   rows; `POST /api/v1/expenses` creates one; `PATCH
>   /api/v1/expenses/{id}` updates Status — this is the **outbound
>   write-back contract** the rest of the system depends on
> - The auth middleware exists and is wired through every mount as a
>   no-op; swapping it for a real implementation requires editing one
>   file
> - `PUT /api/v1/integration/config/surreal` + `POST /test-connection`
>   round-trips against a real SurrealDB
> - Pull and Push runs against `employees` and `expenses` produce audit
>   events with correct counts; dry-run leaves both stores unchanged
> - `flutter run -d chrome` boots the app, all three tabs render, and
>   the Integration tab can drive a full Pull → Push → Audit cycle
> - All persistence files survive a server restart

---

## Notes on how to use this prompt

- **Run it on a fresh repo.** The brief assumes empty starting state.
  If you point an agent at the existing repo it'll get confused about
  what to overwrite — better to branch from `main` and let it build
  fresh against the spec.
- **Expect minor drift.** Field-by-field reproduction isn't the goal;
  surface-by-surface reproduction is.
- **Iterate, don't one-shot.** A sensible order:
  1. Build the mock ECC 6 REST API + Flutter admin (HR + Expenses
     services, plus supporting ECC reads).
  2. Add the no-op auth middleware + Flutter auth-mode stub. Keep the
     real scheme TBD; this is purely the seam.
  3. Add the SurrealDB integration with audit, plus the Integration tab.

  Splitting the prompt the same way often produces better results
  than handing the agent the whole thing at once.

- **REST only — not OData.** The real ECC 6 system exposes REST APIs
  for both inbound reads and outbound writes. Do not build
  `/sap/opu/odata/sap/`, `$metadata`, EDMX, `$filter`, or any other
  OData artefact. Schema metadata is plain JSON (`type: 'string'`,
  not `Edm.String`).

- **Auth will change.** Treat the current no-op middleware and empty
  `_authHeaders()` as the contract; a future iteration will fill them
  in with whatever the real system requires (likely Basic, OAuth2
  client-credentials, or SAML bearer — to be confirmed).
