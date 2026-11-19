import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory temporary;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('coverage-check-');
  });
  tearDown(() => temporary.deleteSync(recursive: true));

  Future<ProcessResult> check({
    required int iconHits,
    bool includeIcons = true,
    bool includeCore = true,
    bool includeUnknown = false,
  }) async {
    final entries = <(String, int, int)>[
      if (includeCore) ('lib/core/controller.dart', 100, 100),
      for (final group in [
        'database',
        'widgets',
        'features',
        'models',
        'providers',
        'common',
        'flashco',
        'manager',
        'views',
        'enum',
        'pages',
        'plugins',
      ])
        ('lib/$group/example.dart', 100, 100),
      ('lib/application.dart', 100, 100),
      ('lib/ui/scaffold.dart', 900, 900),
      if (includeIcons) ('lib/ui/icons/app_glyphs.dart', 100, iconHits),
      if (includeUnknown) ('lib/unknown/example.dart', 100, 100),
    ];
    final report = File('${temporary.path}/lcov.info');
    await report.writeAsString(
      [
        for (final (source, found, hit) in entries)
          'SF:$source\nLF:$found\nLH:$hit\nend_of_record\n',
      ].join(),
    );
    return Process.run('dart', ['tool/check_coverage.dart', report.path, '0']);
  }

  test(
    'icon coverage below 90 fails even with a healthy UI aggregate',
    () async {
      final result = await check(iconHits: 89);
      expect(result.exitCode, isNot(0));
      expect(result.stdout, contains('98.9%'));
      expect(result.stderr, contains('ui/icons 89.00%'));
    },
  );

  test('90 percent icons pass and total counts each line once', () async {
    final result = await check(iconHits: 90);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(
      result.stdout,
      contains('TOTAL (generated code excluded): 2390/2400'),
    );
  });

  test('missing icon measurements fail', () async {
    final result = await check(iconHits: 0, includeIcons: false);
    expect(result.exitCode, isNot(0));
    expect(
      result.stderr,
      contains('ui/icons has a floor but no measured lines'),
    );
  });

  test('missing root coverage and unguarded groups fail', () async {
    final result = await check(
      iconHits: 100,
      includeCore: false,
      includeUnknown: true,
    );
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('core has a floor but no measured lines'));
    expect(result.stderr, contains('unknown is measured but has no floor'));
  });
}
