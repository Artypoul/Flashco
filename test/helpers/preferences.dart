import 'dart:async';

import 'package:flashco/common/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Backs [preferences] with a fresh in-memory store holding [values].
Future<void> mockPreferences([Map<String, Object> values = const {}]) async {
  await preferences.sharedPreferencesCompleter.future;
  SharedPreferences.setMockInitialValues(values);
  preferences.sharedPreferencesCompleter = Completer()
    ..complete(await SharedPreferences.getInstance());
}
