import 'package:flashco/common/preferences.dart';
import 'package:flashco/flashco/personal_defaults.dart';
import 'package:flashco/models/models.dart';

Future<Config> initializePersonalDefaults(
  Config config, {
  required String subscriptionUrl,
  required bool enabled,
  required bool isNewInstallation,
  bool subscriptionOnFirstRun = false,
}) async {
  if (!shouldApplyPersonalDefaults(
        subscriptionUrl: subscriptionUrl,
        enabled: enabled,
        isNewInstallation: isNewInstallation,
        subscriptionOnFirstRun: subscriptionOnFirstRun,
      ) ||
      !await preferences.isInit ||
      await preferences.werePersonalDefaultsApplied()) {
    return config;
  }
  final updated = applyPersonalDefaults(config);
  if (!await preferences.saveConfig(updated)) {
    throw StateError('Failed to save personal startup defaults');
  }
  await preferences.markPersonalDefaultsApplied();
  return updated;
}
