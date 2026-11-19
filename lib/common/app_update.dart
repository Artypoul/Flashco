import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flashco/common/common.dart';
import 'package:flashco/enum/enum.dart';
import 'package:flashco/state.dart';
import 'package:flashco/plugins/app.dart';
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;
import 'package:path/path.dart';

const releaseChecksumsName = 'SHA256SUMS';

sealed class UpdateDownload {
  const UpdateDownload(this.tag);

  final String tag;
}

final class UpdateDownloading extends UpdateDownload {
  const UpdateDownloading(super.tag, {this.received = 0, this.total = 0});

  final int received;

  /// Zero until the server reports a length.
  final int total;
}

final class UpdateReady extends UpdateDownload {
  const UpdateReady(super.tag, this.path);

  final String path;
}

@visibleForTesting
bool Function() resolveStableUpdateEligibility = () => stableUpdateEligible(
  debug: kDebugMode,
  environment: const String.fromEnvironment('APP_ENV', defaultValue: 'pre'),
  android: system.isAndroid,
  packageName: globalState.packageInfo.packageName,
  bundledSubscription: bundledSubscriptionUrl,
  bundledFallback: bundledFallbackConfig,
  firstRun: subscriptionOnFirstRun,
  reality: realitySupportX25519Mlkem768,
  mitm: mitmFeature,
);

bool get isStableUpdateBuild => resolveStableUpdateEligibility();

@visibleForTesting
String? Function() resolveSelfUpdateSuffix = () {
  if (!isStableUpdateBuild) return null;
  return selfUpdateAssetSuffix(
    Abi.current(),
    windowsInstalled: system.isWindows && isInstalledWindowsBuild,
  );
};

bool stableUpdateEligible({
  required bool debug,
  required String environment,
  required bool android,
  required String packageName,
  required String bundledSubscription,
  required String bundledFallback,
  required bool firstRun,
  required bool reality,
  required bool mitm,
}) =>
    !debug &&
    environment == 'stable' &&
    (!android || packageName == 'com.follow.flashco') &&
    !packageName.endsWith('.dev') &&
    bundledSubscription.isEmpty &&
    bundledFallback.isEmpty &&
    !firstRun &&
    !reality &&
    !mitm;

String? get selfUpdateSuffix => resolveSelfUpdateSuffix();

// The names follow the release matrix in .github/workflows/build.yaml.
String? selfUpdateAssetSuffix(Abi abi, {required bool windowsInstalled}) {
  return switch (abi) {
    Abi.androidArm64 || Abi.androidArm || Abi.androidX64 => 'android.apk',
    Abi.windowsX64 when windowsInstalled => 'windows-amd64-setup.exe',
    _ => null,
  };
}

String releaseAssetName(String tag, String suffix) {
  final version = tag.startsWith('v') ? tag.substring(1) : tag;
  return '$appName-$version-$suffix';
}

Uri releaseAssetUri(String tag, String name) {
  return Uri.https('github.com', '/$repository/releases/download/$tag/$name');
}

final _checksumLine = RegExp(r'^([0-9a-fA-F]{64}) [ *](?:\./)?(.+)$');

String? releaseChecksum(String sums, String name) {
  String? found;
  for (final line in const LineSplitter().convert(sums)) {
    final match = _checksumLine.firstMatch(line.trim());
    if (match != null && match[2] == name) {
      if (found != null) return null;
      found = match[1]!.toLowerCase();
    }
  }
  return found;
}

Future<String> fileSha256(String path) {
  return Isolate.run(() async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return digest.toString();
  });
}

// The installer that relaunched the app may still hold its file open.
Future<void> clearUpdateDownloads() async {
  try {
    await app?.clearDownloads();
    await safeDeletePath(await appPath.updateDirPath);
  } on PlatformException catch (error) {
    commonPrint.log(
      'Clearing system downloads failed: ${compactError(error)}',
      logLevel: LogLevel.warning,
    );
  } on FileSystemException catch (error) {
    commonPrint.log(
      'Clearing update downloads failed: ${compactError(error)}',
      logLevel: LogLevel.warning,
    );
  }
}

// Inno Setup writes unins000.exe beside the app; the portable zip has none.
bool get isInstalledWindowsBuild {
  return File(join(appPath.executableDirPath, 'unins000.exe')).existsSync();
}

// inno_setup.iss waits for `updatefrom` to exit, then relaunches the app.
String windowsUpdateArguments(int pid) {
  return '/SILENT /SUPPRESSMSGBOXES /NORESTART /SP- /updatefrom=$pid';
}
