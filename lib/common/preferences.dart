import 'dart:async';
import 'dart:convert';

import 'package:flashco/common/boot_record.dart';
import 'package:flashco/common/common.dart';
import 'package:flashco/common/system_dns.dart';
import 'package:flashco/enum/enum.dart';
import 'package:flashco/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Preferences {
  static Preferences? _instance;
  Completer<SharedPreferences?> sharedPreferencesCompleter = Completer();

  Future<bool> get isInit async =>
      await sharedPreferencesCompleter.future != null;

  Future<bool> get isNewInstallation async {
    final store = await sharedPreferencesCompleter.future;
    return store != null && store.getKeys().isEmpty;
  }

  Preferences._internal() {
    SharedPreferences.getInstance()
        .then((value) => sharedPreferencesCompleter.complete(value))
        .onError((_, _) => sharedPreferencesCompleter.complete(null));
  }

  factory Preferences() {
    _instance ??= Preferences._internal();
    return _instance!;
  }

  Future<int> getVersion() async {
    final preferences = await sharedPreferencesCompleter.future;
    return preferences?.getInt('version') ?? 0;
  }

  Future<void> setVersion(int version) async {
    final preferences = await sharedPreferencesCompleter.future;
    await preferences?.setInt('version', version);
  }

  Future<String?> getAppliedConfigMd5() async {
    final store = await sharedPreferencesCompleter.future;
    return store?.getString(appliedConfigMd5Key);
  }

  Future<void> saveAppliedConfigMd5(String? value) async {
    final store = await sharedPreferencesCompleter.future;
    if (store == null) return;
    final saved = value == null
        ? await store.remove(appliedConfigMd5Key)
        : await store.setString(appliedConfigMd5Key, value);
    if (!saved) {
      throw StateError('Failed to save applied config digest');
    }
  }

  Future<bool> wasBundledSubscriptionImported(String url) async {
    final store = await sharedPreferencesCompleter.future;
    return store?.getBool('bundledSubscription.${url.toMd5()}') ?? false;
  }

  Future<void> markBundledSubscriptionImported(String url) async {
    final store = await sharedPreferencesCompleter.future;
    if (await store?.setBool('bundledSubscription.${url.toMd5()}', true) !=
        true) {
      throw StateError('Failed to save bundled subscription status');
    }
  }

  Future<bool> werePersonalDefaultsApplied() async {
    final store = await sharedPreferencesCompleter.future;
    return store?.getBool('personalDefaults.v1') ?? false;
  }

  Future<void> beginPersonalDefaultsInitialization({
    required bool enabled,
    required bool isNewInstallation,
  }) async {
    if (!enabled || !isNewInstallation) return;
    final store = await sharedPreferencesCompleter.future;
    if (store == null || store.containsKey('personalDefaults.initializing')) {
      return;
    }
    if (!await store.setBool('personalDefaults.initializing', true)) {
      throw StateError('Failed to save personal defaults initialization');
    }
  }

  Future<bool> get isPersonalDefaultsInitializing async {
    final store = await sharedPreferencesCompleter.future;
    return store?.getBool('personalDefaults.initializing') ?? false;
  }

  Future<void> finishPersonalDefaultsInitialization() async {
    final store = await sharedPreferencesCompleter.future;
    if (store?.containsKey('personalDefaults.initializing') != true) return;
    if (!await store!.remove('personalDefaults.initializing')) {
      throw StateError('Failed to finish personal defaults initialization');
    }
  }

  Future<void> initializeSubscriptionOnboarding({
    required bool enabled,
    required bool isNewInstallation,
  }) async {
    if (!enabled || !isNewInstallation) return;
    final store = await sharedPreferencesCompleter.future;
    if (store == null || store.containsKey('subscriptionOnboarding')) {
      return;
    }
    if (!await store.setString('subscriptionOnboarding', 'initializing')) {
      throw StateError('Failed to save pending subscription setup');
    }
  }

  Future<bool> get isSubscriptionOnboardingInitializing async {
    final store = await sharedPreferencesCompleter.future;
    return store?.getString('subscriptionOnboarding') == 'initializing';
  }

  Future<void> finishSubscriptionOnboardingInitialization() async {
    if (!await isSubscriptionOnboardingInitializing) return;
    final store = await sharedPreferencesCompleter.future;
    if (await store?.setString('subscriptionOnboarding', 'pending') != true) {
      throw StateError('Failed to prepare subscription input');
    }
  }

  Future<bool> get isSubscriptionOnboardingPending async {
    final store = await sharedPreferencesCompleter.future;
    return store?.getString('subscriptionOnboarding') == 'pending';
  }

  Future<void> completeSubscriptionOnboarding() async {
    final store = await sharedPreferencesCompleter.future;
    if (await store?.setString('subscriptionOnboarding', 'complete') != true) {
      throw StateError('Failed to complete subscription setup');
    }
  }

  Future<void> stageBundledFallback(
    String url,
    String config, {
    required bool isNewInstallation,
    required bool enabled,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (!enabled ||
        !isNewInstallation ||
        config.trim().isEmpty ||
        uri == null ||
        uri.host.isEmpty ||
        !const ['http', 'https'].contains(uri.scheme)) {
      return;
    }
    final settings = FallbackConfig.fromJson(
      jsonDecode(config) as Map<String, dynamic>,
    ).validated();
    final store = await sharedPreferencesCompleter.future;
    if (store == null) return;
    final key = 'bundledFallback.${url.trim().toMd5()}';
    if (store.getString(key) != null) return;
    if (!await store.setString(key, jsonEncode(settings.toJson()))) {
      throw StateError('Failed to save pending fallback defaults');
    }
  }

  Future<FallbackConfig?> pendingBundledFallback(String url) async {
    final store = await sharedPreferencesCompleter.future;
    final value = store?.getString('bundledFallback.${url.trim().toMd5()}');
    if (value == null) return null;
    return FallbackConfig.fromJson(
      jsonDecode(value) as Map<String, dynamic>,
    ).validated();
  }

  Future<void> completeBundledFallback(String url) async {
    final store = await sharedPreferencesCompleter.future;
    final key = 'bundledFallback.${url.trim().toMd5()}';
    if (store?.getString(key) == null) return;
    if (!await store!.remove(key)) {
      throw StateError('Failed to complete pending fallback defaults');
    }
  }

  Future<void> markPersonalDefaultsApplied() async {
    final store = await sharedPreferencesCompleter.future;
    if (await store?.setBool('personalDefaults.v1', true) != true) {
      throw StateError('Failed to save personal startup defaults status');
    }
  }

  Future<void> saveShareState(
    SharedState shareState, {
    bool preserveSetupBase = true,
  }) async {
    final preferences = await sharedPreferencesCompleter.future;
    final params = shareState.setupParams;
    if (preserveSetupBase && params != null) {
      final raw = preferences?.getString('sharedState');
      if (raw != null) {
        try {
          final previous = json.decode(raw) as Map<String, dynamic>;
          final setup = previous['setupParams'] as Map<String, dynamic>?;
          final base = setup?['base'] as Map<String, dynamic>?;
          shareState = shareState.copyWith(
            setupParams: params.copyWith(
              base: base == null ? null : SetupBase.fromJson(base),
            ),
          );
        } on FormatException {
          // A corrupt legacy state must not prevent a fresh state from saving.
        } on TypeError {
          // Legacy state can contain fields in an older shape.
        }
      }
    }
    await preferences?.setString('sharedState', json.encode(shareState));
  }

  Future<Map<String, Object?>?> getConfigMap() async {
    try {
      final preferences = await sharedPreferencesCompleter.future;
      final configString = preferences?.getString(configKey);
      if (configString == null) return null;
      final Map<String, Object?>? configMap = json.decode(configString);
      return configMap;
    } catch (e) {
      commonPrint.log(
        'getConfigMap error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  Future<Map<String, Object?>?> getClashConfigMap() async {
    try {
      final preferences = await sharedPreferencesCompleter.future;
      final clashConfigString = preferences?.getString(clashConfigKey);
      if (clashConfigString == null) return null;
      return json.decode(clashConfigString);
    } catch (e) {
      commonPrint.log(
        'getClashConfigMap error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  Future<void> clearClashConfig() async {
    try {
      final preferences = await sharedPreferencesCompleter.future;
      await preferences?.remove(clashConfigKey);
      return;
    } catch (e) {
      commonPrint.log(
        'clearClashConfig error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return;
    }
  }

  Future<Config?> getConfig() async {
    final configMap = await getConfigMap();
    if (configMap == null) {
      return null;
    }
    return Config.fromJson(configMap);
  }

  Future<bool> saveConfig(Config config) async {
    final preferences = await sharedPreferencesCompleter.future;
    return preferences?.setString(configKey, json.encode(config)) ?? false;
  }

  Future<SystemDnsRecord?> getSystemDnsRecord() async {
    try {
      final sharedPreferencesIns = await sharedPreferencesCompleter.future;
      final raw = sharedPreferencesIns?.getString(systemDnsRecordKey);
      if (raw == null) {
        return null;
      }
      return SystemDnsRecord.fromJson(json.decode(raw));
    } catch (e) {
      commonPrint.log(
        'getSystemDnsRecord error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  Future<void> saveSystemDnsRecord(SystemDnsRecord record) async {
    final sharedPreferencesIns = await sharedPreferencesCompleter.future;
    await sharedPreferencesIns?.setString(
      systemDnsRecordKey,
      json.encode(record),
    );
  }

  Future<void> clearSystemDnsRecord() async {
    final sharedPreferencesIns = await sharedPreferencesCompleter.future;
    await sharedPreferencesIns?.remove(systemDnsRecordKey);
  }

  Future<BootRecord?> getBootRecord() async {
    try {
      final sharedPreferencesIns = await sharedPreferencesCompleter.future;
      final raw = sharedPreferencesIns?.getString(bootRecordKey);
      if (raw == null) {
        return null;
      }
      return BootRecord.fromJson(json.decode(raw));
    } catch (e) {
      commonPrint.log(
        'getBootRecord error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  Future<void> saveBootRecord(BootRecord record) async {
    final sharedPreferencesIns = await sharedPreferencesCompleter.future;
    await sharedPreferencesIns?.setString(bootRecordKey, json.encode(record));
  }

  Future<void> clearPreferences() async {
    final sharedPreferencesIns = await sharedPreferencesCompleter.future;
    await sharedPreferencesIns?.clear();
  }
}

final preferences = Preferences();
