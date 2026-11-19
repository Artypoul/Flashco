import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flashco/common/boot_record.dart';
import 'package:flashco/common/constant.dart';
import 'package:flashco/common/exception.dart';
import 'package:flashco/enum/enum.dart';
import 'package:flashco/plugins/app.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('$packageName/app');

  setUp(() {
    App().clearPackageIconCache();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    App().clearPackageIconCache();
  });

  test('requests every package icon from Android only once', () async {
    var iconCallCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          iconCallCount++;
          return '/icons/${call.arguments['packageName']}.png';
        });

    final app = App();
    final results = await Future.wait([
      app.getPackageIcon('com.a'),
      app.getPackageIcon('com.a'),
    ]);
    final cached = await app.getPackageIcon('com.a');

    expect(iconCallCount, 1);
    expect(results.first, isNotNull);
    expect(cached, same(results.first));
    expect(app.hasPackageIcon('com.a'), isTrue);
    expect(app.getCachedPackageIcon('com.a'), same(results.first));

    await app.getPackageIcon('com.b');

    expect(iconCallCount, 2);
  });

  test(
    'falls back to the default activity icon for unknown packages',
    () async {
      final requested = <String?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final packageName = call.arguments['packageName'] as String?;
            requested.add(packageName);
            return packageName == '' ? '/icons/default_icon.webp' : null;
          });

      final app = App();

      final fallback = await app.getPackageIcon('com.a');
      final defaultIcon = await app.getPackageIcon('');

      expect(fallback, isNotNull);
      expect(fallback, same(defaultIcon));
      expect(requested, ['com.a', '']);

      expect(await app.getPackageIcon('com.b'), same(defaultIcon));
      expect(requested, ['com.a', '', 'com.b']);
    },
  );

  test(
    'asks Android for a bounded number of package icons at a time',
    () async {
      var inFlight = 0;
      var peak = 0;
      final release = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            inFlight++;
            peak = max(peak, inFlight);
            await release.future;
            inFlight--;
            return '/icons/${call.arguments['packageName']}.png';
          });

      final app = App();
      final icons = Future.wait([
        for (var i = 0; i < maxConcurrentIconLoads * 2; i++)
          app.getPackageIcon('com.$i'),
      ]);
      await pumpEventQueue();

      expect(inFlight, maxConcurrentIconLoads);

      release.complete();

      expect(await icons, everyElement(isNotNull));
      expect(peak, maxConcurrentIconLoads);
    },
  );

  test('caches a failed package icon lookup', () async {
    var iconCallCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          iconCallCount++;
          throw PlatformException(code: 'unavailable');
        });

    final app = App();

    expect(await app.getPackageIcon('com.a'), isNull);
    expect(await app.getPackageIcon('com.a'), isNull);
    expect(await app.getPackageIcon(''), isNull);
    expect(iconCallCount, 2);
    expect(app.hasPackageIcon('com.a'), isTrue);
    expect(app.hasPackageIcon(''), isTrue);
  });

  test('reads the last process exit info from Android', () async {
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return <String, Object?>{
            'reason': 10,
            'timestamp': 1234,
            'description': 'user requested',
          };
        });

    final info = await App().getLastExitInfo();

    expect(receivedCall?.method, 'getLastExitInfo');
    expect(info?.reason, AppExitReason.userRequested);
    expect(info?.timestamp, 1234);
    expect(info?.description, 'user requested');
  });

  test('uses no exit info when Android cannot report one', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);

    expect(await App().getLastExitInfo(), isNull);
  });

  test('uses no exit info when the platform call fails', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'unavailable');
        });

    expect(await App().getLastExitInfo(), isNull);
  });

  test('forwards package change notices from Android', () async {
    var changes = 0;
    final app = App();
    app.onPackagesChanged = () => changes++;
    addTearDown(() => app.onPackagesChanged = null);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(const MethodCall('packagesChanged')),
          (_) {},
        );

    expect(changes, 1);
  });

  test('reports the installed apps permission Android answers with', () async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methods.add(call.method);
          return false;
        });

    expect(await App().isInstalledAppsPermissionGranted(), isFalse);
    expect(await App().requestInstalledAppsPermission(), isFalse);
    expect(methods, [
      'isInstalledAppsPermissionGranted',
      'requestInstalledAppsPermission',
    ]);
  });

  test(
    'treats a missing installed apps permission answer as granted',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);

      expect(await App().isInstalledAppsPermissionGranted(), isTrue);
      expect(await App().requestInstalledAppsPermission(), isFalse);
    },
  );

  test('reports download progress and completes only on success', () async {
    final calls = <MethodCall>[];
    final progress = <(int, int)>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'enqueueDownload') return 42;
          if (call.method == 'queryDownload') {
            final count = calls
                .where((c) => c.method == 'queryDownload')
                .length;
            return {
              'status': count == 1 ? 2 : 8,
              'received': count * 5,
              'total': 10,
            };
          }
          fail('Unexpected call: ${call.method}');
        });

    await App().downloadFile(
      Uri.parse('https://example.com/update.apk'),
      '/downloads/update.apk',
      title: 'Update',
      onReceiveProgress: (received, total) => progress.add((received, total)),
      cancelToken: CancelToken(),
    );

    expect(calls.map((c) => c.method), [
      'enqueueDownload',
      'queryDownload',
      'queryDownload',
    ]);
    expect(
      calls.first.arguments,
      containsPair('url', 'https://example.com/update.apk'),
    );
    expect(
      calls.first.arguments,
      containsPair('path', '/downloads/update.apk'),
    );
    expect(calls.first.arguments, containsPair('title', 'Update'));
    expect(calls.skip(1).map((c) => c.arguments), everyElement({'id': 42}));
    expect(progress, [(5, 10), (10, 10)]);
  });

  test('propagates system download failure and its reason', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => switch (call.method) {
            'enqueueDownload' => 7,
            'queryDownload' => {
              'status': 16,
              'received': 3,
              'total': 10,
              'reason': 1006,
            },
            _ => fail('Unexpected call: ${call.method}'),
          },
        );
    final progress = <(int, int)>[];

    await expectLater(
      App().downloadFile(
        Uri.parse('https://example.com/a'),
        '/a',
        title: 'Update',
        onReceiveProgress: (r, t) => progress.add((r, t)),
        cancelToken: CancelToken(),
      ),
      throwsA(
        isA<SystemDownloadException>().having((e) => e.reason, 'reason', 1006),
      ),
    );
    expect(progress, [(3, 10)]);
  });

  test(
    'cancellation stops polling before a download status is requested',
    () async {
      final enqueued = Completer<void>();
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'enqueueDownload') {
              enqueued.complete();
              return 9;
            }
            fail('Unexpected call: ${call.method}');
          });
      final token = CancelToken();
      final download = App().downloadFile(
        Uri.parse('https://example.com/a'),
        '/a',
        title: 'Update',
        onReceiveProgress: (_, _) => fail('Unexpected progress'),
        cancelToken: token,
      );
      await enqueued.future;
      token.cancel('cancelled by user');

      await expectLater(
        download,
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
      expect(calls, ['enqueueDownload']);
    },
  );

  test(
    'certificate operations preserve DER bytes and map platform outcomes',
    () async {
      final calls = <MethodCall>[];
      var rootResult = 'installed';
      var installResult = 'prompted';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'locateCaCertificate' => {'user': true, 'system': false},
              'installCaCertificateWithRoot' => rootResult,
              'installCaCertificate' => installResult,
              'removeCaCertificateWithRoot' => true,
              _ => fail('Unexpected call: ${call.method}'),
            };
          });
      const der = [0, 127, 255];
      expect(await App().locateCaCertificate(der), (
        user: true,
        system: false,
        root: false,
      ));
      expect(
        await App().installCaCertificateWithRoot(der),
        MitmInstallOutcome.installed,
      );
      rootResult = 'untilReboot';
      expect(
        await App().installCaCertificateWithRoot(der),
        MitmInstallOutcome.untilReboot,
      );
      rootResult = 'denied';
      expect(await App().installCaCertificateWithRoot(der), isNull);
      expect(
        await App().installCaCertificate(der, name: 'CA', fileName: 'ca.crt'),
        MitmInstallOutcome.prompted,
      );
      installResult = 'saved';
      expect(
        await App().installCaCertificate(der, name: 'CA', fileName: 'ca.crt'),
        MitmInstallOutcome.saved,
      );
      installResult = 'unavailable';
      expect(
        await App().installCaCertificate(der, name: 'CA', fileName: 'ca.crt'),
        isNull,
      );
      expect(await App().removeCaCertificateWithRoot(der), isTrue);
      for (final call in calls) {
        expect(call.arguments['der'], isA<Uint8List>());
        expect(call.arguments['der'], orderedEquals(der));
      }
      expect(
        calls.where((c) => c.method == 'installCaCertificate').first.arguments,
        containsPair('fileName', 'ca.crt'),
      );
    },
  );
}
