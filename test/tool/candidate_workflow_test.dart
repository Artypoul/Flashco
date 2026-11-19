import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test(
    'candidate builds exact source without publishing or personal inputs',
    () {
      final workflow =
          loadYaml(File('.github/workflows/build.yaml').readAsStringSync())
              as YamlMap;
      final candidate = (workflow['jobs'] as YamlMap)['candidate'] as YamlMap;
      final condition = candidate['if'] as String;
      expect(condition, contains("github.repository == 'Artypoul/Flashco'"));
      final matrix =
          ((candidate['strategy'] as YamlMap)['matrix'] as YamlMap)['include']
              as YamlList;
      final rows = matrix.cast<YamlMap>();
      expect(rows, hasLength(3));
      final variants = {
        for (final row in rows) '${row['platform']}/${row['variant']}': row,
      };
      expect(variants.keys.toSet(), {
        'android/first-run-reality',
        'android/embedded-test',
        'windows/embedded-test',
      });
      final firstRun = variants['android/first-run-reality']!;
      expect(firstRun['subscription_url'], isEmpty);
      expect(firstRun['first_run'], 'true');
      expect(firstRun['reality'], 'true');
      for (final key in ['android/embedded-test', 'windows/embedded-test']) {
        final row = variants[key]!;
        expect(
          row['subscription_url'],
          'https://example.invalid/flashco-subscription.yaml',
        );
        expect(row['first_run'], 'false');
        expect(row['reality'], 'false');
      }
      for (final row in rows) {
        expect(
          row['first_run'] == 'true' && '${row['subscription_url']}'.isNotEmpty,
          isFalse,
        );
      }
      final steps = (candidate['steps'] as YamlList).cast<YamlMap>();
      for (final name in [
        'Build universal test APK',
        'Build test Windows EXE and ZIP',
      ]) {
        final env =
            steps.singleWhere((step) => step['name'] == name)['env'] as YamlMap;
        expect(
          env['BOOTSTRAP_SUBSCRIPTION_URL'],
          r'${{ matrix.subscription_url }}',
        );
        expect(
          env['BOOTSTRAP_SUBSCRIPTION_ON_FIRST_RUN'],
          r'${{ matrix.first_run }}',
        );
        expect(env['REALITY_SUPPORT_X25519MLKEM768'], r'${{ matrix.reality }}');
      }
      final checkout = steps.singleWhere(
        (step) => step['uses'] == 'actions/checkout@v4',
      );
      expect((checkout['with'] as YamlMap)['ref'], r'${{ github.sha }}');
      expect((checkout['with'] as YamlMap)['submodules'], 'recursive');
      final commands = steps.map((step) => '${step['run']}').join('\n');
      expect(
        commands,
        contains('android --env pre --targets apk --universal-apk'),
      );
      expect(commands, contains('windows --env pre --targets exe,zip'));
      expect(commands, contains('com.follow.flashco.dev'));
      expect(commands, contains('candidate-checksums.sh'));
      expect(commands, contains('SOURCE_SHA'));
      expect(commands, contains('candidate-metadata.json'));
      expect(commands, contains('build-defines.json'));
      expect(commands, contains('verify_windows_app_version.ps1'));
      expect(commands, contains('windows-app-version.json'));
      final installerVersion = steps.indexWhere(
        (step) =>
            '${step['run']}'.contains('verify_windows_installer_version.ps1'),
      );
      expect(
        installerVersion,
        greaterThan(
          steps.indexWhere(
            (step) => step['name'] == 'Build test Windows EXE and ZIP',
          ),
        ),
      );
      expect(
        installerVersion,
        lessThan(
          steps.indexWhere(
            (step) => '${step['uses']}'.startsWith('actions/upload-artifact@'),
          ),
        ),
      );
      expect(commands, contains('subscription_url_is_synthetic'));
      expect(commands, contains('flutter pub get --enforce-lockfile'));
      final checks = steps
          .where(
            (step) =>
                '${step['run']}'.contains('verify_candidate_checkout.dart'),
          )
          .toList();
      expect(checks.length, 2);
      expect(
        steps.indexOf(checks.first),
        lessThan(
          steps.indexWhere(
            (step) => step['name'] == 'Build universal test APK',
          ),
        ),
      );
      expect(
        steps.indexOf(checks.last),
        greaterThan(
          steps.indexWhere(
            (step) => step['name'] == 'Build test Windows EXE and ZIP',
          ),
        ),
      );
      expect(commands, contains('candidate-checksums.sh'));
      expect(commands, isNot(contains('BOOTSTRAP_SUBSCRIPTION_URL')));
      expect(
        steps.any((step) => '${step['uses']}'.contains('action-gh-release')),
        isFalse,
      );
      final upload = steps.singleWhere(
        (step) => '${step['uses']}'.startsWith('actions/upload-artifact@'),
      );
      final artifactName = (upload['with'] as YamlMap)['name'] as String;
      expect(artifactName, contains(r'${{ matrix.platform }}'));
      expect(artifactName, contains(r'${{ matrix.variant }}'));
      expect(artifactName, contains(r'${{ github.sha }}'));
    },
  );
  test('checksums verify alongside extracted candidate files', () async {
    final temp = await Directory.systemTemp.createTemp('candidate-checksums-');
    addTearDown(() => temp.delete(recursive: true));
    final package = File('${temp.path}/Flashco-android.apk')
      ..writeAsStringSync('test package');
    final script = File('.github/scripts/candidate-checksums.sh').absolute.path;
    final generated = await Process.run('bash', [
      script,
      temp.path,
      package.path,
    ]);
    expect(generated.exitCode, 0, reason: generated.stderr.toString());
    final sums = File('${temp.path}/SHA256SUMS').readAsStringSync();
    expect(sums, contains('  Flashco-android.apk'));
    expect(sums, isNot(contains(temp.path)));
    final check = await Process.run('sha256sum', [
      '-c',
      'SHA256SUMS',
    ], workingDirectory: temp.path);
    expect(check.exitCode, 0, reason: check.stderr.toString());
    await package.writeAsString('tampered');
    final mismatch = await Process.run('sha256sum', [
      '-c',
      'SHA256SUMS',
    ], workingDirectory: temp.path);
    expect(mismatch.exitCode, isNot(0));
  });
}
