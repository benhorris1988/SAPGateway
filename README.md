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

OData root:                `http://localhost:8080/sap/opu/odata/sap/`
Per-service metadata:      `http://localhost:8080/sap/opu/odata/sap/ZSALES_SRV/$metadata`
EntitySet (JSON):          `http://localhost:8080/sap/opu/odata/sap/ZSALES_SRV/CustomerSet?$format=json&$top=5`
Admin (JSON):              `http://localhost:8080/admin/services`

Supported OData v2 query options: `$top`, `$skip`, `$orderby`, `$select`,
`$inlinecount=allpages`, `$format=json|xml`, and a `$filter` subset
(`eq`, `ne`, `gt`, `ge`, `lt`, `le`, `and`, `or`, parens, `substringof`,
`startswith`, `endswith`).

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
