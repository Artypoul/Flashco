import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flashco/common/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('selfUpdateAssetSuffix', () {
    test('names the APK built for the running ABI', () {
      expect(
        selfUpdateAssetSuffix(Abi.androidArm64, windowsInstalled: false),
        'android.apk',
      );
      expect(
        selfUpdateAssetSuffix(Abi.androidArm, windowsInstalled: false),
        'android.apk',
      );
      expect(
        selfUpdateAssetSuffix(Abi.androidX64, windowsInstalled: false),
        'android.apk',
      );
    });

    test('names the Windows installer only for an installed build', () {
      expect(
        selfUpdateAssetSuffix(Abi.windowsX64, windowsInstalled: true),
        'windows-amd64-setup.exe',
      );
      expect(
        selfUpdateAssetSuffix(Abi.windowsArm64, windowsInstalled: true),
        isNull,
      );
      expect(
        selfUpdateAssetSuffix(Abi.windowsX64, windowsInstalled: false),
        isNull,
      );
    });

    test('leaves macOS and Linux to the release page', () {
      for (final abi in [
        Abi.macosArm64,
        Abi.macosX64,
        Abi.linuxX64,
        Abi.linuxArm64,
      ]) {
        expect(selfUpdateAssetSuffix(abi, windowsInstalled: true), isNull);
      }
    });
  });

  test('stable updates exclude personal, debug and feature variants', () {
    bool eligible({
      bool debug = false,
      String environment = 'stable',
      bool android = true,
      String packageName = 'com.follow.flashco',
      String bundledSubscription = '',
      String bundledFallback = '',
      bool firstRun = false,
      bool reality = false,
      bool mitm = false,
    }) => stableUpdateEligible(
      debug: debug,
      environment: environment,
      android: android,
      packageName: packageName,
      bundledSubscription: bundledSubscription,
      bundledFallback: bundledFallback,
      firstRun: firstRun,
      reality: reality,
      mitm: mitm,
    );
    expect(eligible(), isTrue);
    expect(eligible(debug: true), isFalse);
    expect(eligible(environment: 'pre'), isFalse);
    expect(eligible(packageName: 'com.follow.flashco.dev'), isFalse);
    expect(eligible(bundledSubscription: 'personal'), isFalse);
    expect(eligible(bundledFallback: 'personal'), isFalse);
    expect(eligible(firstRun: true), isFalse);
    expect(eligible(reality: true), isFalse);
    expect(eligible(mitm: true), isFalse);
  });

  test('releaseAssetName drops the tag prefix', () {
    expect(
      releaseAssetName('v0.9.3', 'android.apk'),
      'Flashco-0.9.3-android.apk',
    );
  });

  group('releaseChecksum', () {
    const digest =
        'ff6a953c0f5c12e6bdc97b49428b565b64c4a62d85e50081823ba297407529b1';

    test('reads the entry sha256sum wrote for a file', () {
      final sums =
          '$digest  ./FlClash-0.9.2-android.apk\n'
          '${'0' * 64}  ./FlClash-0.9.2-windows-amd64-setup.exe\n';

      expect(releaseChecksum(sums, 'FlClash-0.9.2-android.apk'), digest);
    });

    test('accepts the binary marker, upper case and CRLF', () {
      final sums = '${digest.toUpperCase()} *FlClash.apk\r\n';

      expect(releaseChecksum(sums, 'FlClash.apk'), digest);
    });

    test('rejects duplicate entries', () {
      expect(
        releaseChecksum(
          '$digest  FlClash.apk\n$digest  FlClash.apk',
          'FlClash.apk',
        ),
        isNull,
      );
    });

    test('answers null for a file the listing does not name', () {
      expect(releaseChecksum('$digest  ./other.apk\n', 'FlClash.apk'), isNull);
      expect(releaseChecksum('not a listing', 'FlClash.apk'), isNull);
    });
  });

  test('fileSha256 hashes the file on disk', () async {
    final directory = await Directory.systemTemp.createTemp('app_update');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/package');
    await file.writeAsString('package');

    expect(
      await fileSha256(file.path),
      sha256.convert(utf8.encode('package')).toString(),
    );
  });

  test('windowsUpdateArguments installs silently on behalf of a pid', () {
    final arguments = windowsUpdateArguments(4242).split(' ');

    expect(arguments, containsAll(['/SILENT', '/SUPPRESSMSGBOXES']));
    expect(arguments, contains('/updatefrom=4242'));
  });
}
