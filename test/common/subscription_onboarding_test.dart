import 'dart:async';

import 'package:flashco/common/preferences.dart';
import 'package:flashco/common/subscription_onboarding.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _url = 'https://example.invalid/subscription';

Future<void> _initialize({bool enabled = true, bool isNew = true}) async {
  await preferences.initializeSubscriptionOnboarding(
    enabled: enabled,
    isNewInstallation: isNew,
  );
  if (enabled) {
    await preferences.finishSubscriptionOnboardingInitialization();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUp(() async {
    final store = await SharedPreferences.getInstance();
    await store.clear();
  });

  test('only an opted-in fresh installation stages the prompt', () async {
    await _initialize(enabled: false);
    await _initialize(isNew: false);
    expect(await preferences.isSubscriptionOnboardingPending, isFalse);

    await _initialize();
    expect(await preferences.isSubscriptionOnboardingPending, isTrue);
    await _initialize(isNew: false);
    expect(await preferences.isSubscriptionOnboardingPending, isTrue);
  });

  test(
    'interrupted initialization retains the fresh-install decision',
    () async {
      final isNewInstallation = await preferences.isNewInstallation;
      await preferences.initializeSubscriptionOnboarding(
        enabled: true,
        isNewInstallation: isNewInstallation,
      );

      expect(await preferences.isNewInstallation, isFalse);
      expect(await preferences.isSubscriptionOnboardingInitializing, isTrue);
      expect(await preferences.isSubscriptionOnboardingPending, isFalse);
      final resumedFreshInstallation =
          await preferences.isNewInstallation ||
          await preferences.isSubscriptionOnboardingInitializing;
      expect(resumedFreshInstallation, isTrue);

      await preferences.initializeSubscriptionOnboarding(
        enabled: true,
        isNewInstallation: resumedFreshInstallation,
      );
      await preferences.finishSubscriptionOnboardingInitialization();

      expect(await preferences.isSubscriptionOnboardingInitializing, isFalse);
      expect(await preferences.isSubscriptionOnboardingPending, isTrue);
      await preferences.completeSubscriptionOnboarding();
      await _initialize();
      expect(await preferences.isSubscriptionOnboardingPending, isFalse);
    },
  );

  test('unavailable preferences cannot stage or complete onboarding', () async {
    final previous = preferences.sharedPreferencesCompleter;
    preferences.sharedPreferencesCompleter = Completer()..complete(null);
    try {
      await _initialize();
      expect(await preferences.isSubscriptionOnboardingPending, isFalse);
      await expectLater(
        preferences.completeSubscriptionOnboarding(),
        throwsStateError,
      );
    } finally {
      preferences.sharedPreferencesCompleter = previous;
    }
  });

  test('subscription input accepts only complete HTTP(S) URLs', () {
    for (final url in [
      _url,
      ' http://example.invalid/sub?key=token ',
      'https://example.invalid/a%20b',
    ]) {
      expect(isSubscriptionUrl(url), isTrue, reason: url);
    }
    for (final url in [
      '',
      '  ',
      'https://',
      'ftp://example.invalid/sub',
      'file:///subscription',
      'example.invalid/sub',
      'https://example.invalid/a b',
      'https://example.invalid/a\nb',
      'https://example.invalid/a\x00b',
    ]) {
      expect(isSubscriptionUrl(url), isFalse, reason: url);
    }
  });

  test('cancel keeps the prompt pending across a later launch', () async {
    await _initialize();
    var prompts = 0;
    Future<void> launch() => requestFirstRunSubscription(
      requestUrl: (_) async {
        prompts++;
        return null;
      },
      hasProfiles: () async => false,
      importSubscription: (_) async => fail('Cancellation must not import'),
    );

    await launch();
    await _initialize(isNew: false);
    await launch();

    expect(prompts, 2);
    expect(await preferences.isSubscriptionOnboardingPending, isTrue);
  });

  test(
    'a saved subscription completes setup without a connection marker',
    () async {
      await _initialize();
      var hasSavedProfile = false;
      final imports = <String>[];

      await requestFirstRunSubscription(
        requestUrl: (_) async => '  $_url  ',
        hasProfiles: () async => hasSavedProfile,
        importSubscription: (url) async {
          imports.add(url);
          hasSavedProfile = true;
        },
      );

      expect(imports, [_url]);
      expect(await preferences.wasBundledSubscriptionImported(_url), isFalse);
      expect(await preferences.isSubscriptionOnboardingPending, isFalse);

      hasSavedProfile = false;
      await _initialize(isNew: false);
      await requestFirstRunSubscription(
        requestUrl: (_) async => fail('Completed setup must not prompt again'),
        hasProfiles: () async => hasSavedProfile,
        importSubscription: (_) async => fail('Deleted profiles stay deleted'),
      );
      expect(imports, [_url]);
    },
  );

  test('an unsuccessful import offers the entered URL for retry', () async {
    await _initialize();
    var hasSavedProfile = false;
    var attempts = 0;
    final values = <String>[];

    await requestFirstRunSubscription(
      requestUrl: (value) async {
        values.add(value);
        return _url;
      },
      hasProfiles: () async => hasSavedProfile,
      importSubscription: (_) async {
        attempts++;
        hasSavedProfile = attempts == 2;
      },
    );

    expect(values, ['', _url]);
    expect(attempts, 2);
    expect(await preferences.isSubscriptionOnboardingPending, isFalse);
  });

  test(
    'an import exception leaves setup pending for the next launch',
    () async {
      await _initialize();

      await expectLater(
        requestFirstRunSubscription(
          requestUrl: (_) async => _url,
          hasProfiles: () async => false,
          importSubscription: (_) async => throw StateError('Download failed'),
        ),
        throwsStateError,
      );

      expect(await preferences.isSubscriptionOnboardingPending, isTrue);
    },
  );

  test('invalid input does not import or complete the prompt', () async {
    await _initialize();
    final values = ['ftp://example.invalid/sub', null].iterator;

    await requestFirstRunSubscription(
      requestUrl: (_) async {
        values.moveNext();
        return values.current;
      },
      hasProfiles: () async => false,
      importSubscription: (_) async => fail('Invalid input must not import'),
    );

    expect(await preferences.isSubscriptionOnboardingPending, isTrue);
  });

  test(
    'a previously saved profile completes pending setup without a prompt',
    () async {
      await _initialize();

      await requestFirstRunSubscription(
        requestUrl: (_) async => fail('An existing profile must be preserved'),
        hasProfiles: () async => true,
        importSubscription: (_) async =>
            fail('An existing profile must not duplicate'),
      );

      expect(await preferences.isSubscriptionOnboardingPending, isFalse);
    },
  );

  test('a profile saved while the dialog is open is not replaced', () async {
    await _initialize();
    final input = Completer<String?>();
    final requested = Completer<void>();
    var hasSavedProfile = false;
    final pending = requestFirstRunSubscription(
      requestUrl: (_) {
        requested.complete();
        return input.future;
      },
      hasProfiles: () async => hasSavedProfile,
      importSubscription: (_) async => fail('A concurrent profile must win'),
    );
    await requested.future;
    hasSavedProfile = true;
    input.complete(_url);
    await pending;

    expect(await preferences.isSubscriptionOnboardingPending, isFalse);
  });
}
