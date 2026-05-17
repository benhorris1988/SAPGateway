import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home.dart';
import 'state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.load();
  runApp(SapGatewayApp(state: state));
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
