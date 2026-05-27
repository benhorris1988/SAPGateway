import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Single source of truth for the active gateway URL. The actual data fetching
/// lives on the screens — keeping AppState lean avoids stale caches.
class AppState extends ChangeNotifier {
  AppState._(this._prefs, this._url);

  static const _kBaseUrl = 'gatewayBaseUrl';
  static const _defaultBaseUrl = 'http://localhost:8080';

  final SharedPreferences _prefs;
  String _url;

  String get baseUrl => _url;

  late final GatewayApi api = GatewayApi(_url);

  static Future<AppState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kBaseUrl) ?? _defaultBaseUrl;
    return AppState._(prefs, saved);
  }

  Future<void> setBaseUrl(String url) async {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (clean == _url) return;
    _url = clean;
    api.baseUrl = clean;
    await _prefs.setString(_kBaseUrl, clean);
    notifyListeners();
  }
}
