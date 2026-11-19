import 'package:flashco/enum/enum.dart';
import 'package:flashco/models/models.dart';
import 'package:prism_ui/theme_data.dart';

bool shouldApplyPersonalDefaults({
  required String subscriptionUrl,
  required bool enabled,
  required bool isNewInstallation,
  required bool subscriptionOnFirstRun,
}) {
  final uri = Uri.tryParse(subscriptionUrl.trim());
  return isNewInstallation &&
      enabled &&
      (subscriptionOnFirstRun ||
          (uri != null &&
              uri.host.isNotEmpty &&
              const ['https', 'http'].contains(uri.scheme)));
}

Config applyPersonalDefaults(Config config) {
  return config.copyWith(
    appSettingProps: config.appSettingProps.copyWith(
      autoLaunch: true,
      autoRun: true,
      locale: 'ru',
    ),
    networkProps: config.networkProps.copyWith(
      systemProxy: false,
      bypassPrivateRoute: true,
    ),
    vpnProps: config.vpnProps.copyWith(systemProxy: false, allowBypass: false),
    themeProps: config.themeProps.copyWith(
      themeMode: ThemeMode.light,
      fontFamily: null,
    ),
    patchClashConfig: config.patchClashConfig.copyWith(
      mode: Mode.rule,
      tun: config.patchClashConfig.tun.copyWith(
        enable: true,
        autoRoute: true,
        stack: TunStack.mips,
        strictRoute: true,
      ),
      tunOverride: config.patchClashConfig.tunOverride.copyWith(
        strictRoute: true,
      ),
      tunOverrideKeys: {
        ...config.patchClashConfig.tunOverrideKeys,
        TunOverrideKey.strictRoute,
      },
    ),
  );
}
