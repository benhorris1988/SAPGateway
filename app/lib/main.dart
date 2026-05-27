import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'logging.dart';
import 'screens/home.dart';
import 'state.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Framework (build/layout/paint) errors.
    FlutterError.onError = (details) {
      appLog.error(
        'Flutter framework error: ${details.exceptionAsString()}',
        error: details.exception,
        stackTrace: details.stack,
      );
      FlutterError.presentError(details);
    };

    // Errors bubbling out of the engine / platform message handlers.
    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      appLog.error('Uncaught platform error',
          error: error, stackTrace: stack);
      return true;
    };

    final state = await AppState.load();
    // Ship error-level client logs to the gateway so they appear in the same
    // log as backend errors.
    appLog.attachShipper(state.api.logClientError);

    runApp(SapGatewayApp(state: state));
  }, (error, stack) {
    // Anything that escapes the widget tree / async callbacks.
    appLog.error('Uncaught error', error: error, stackTrace: stack);
  });
}

class SapGatewayApp extends StatelessWidget {
  const SapGatewayApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        title: 'SAP Gateway',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF1E3A5F),
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF1E3A5F),
          brightness: Brightness.dark,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
