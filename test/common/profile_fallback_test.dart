import 'dart:convert';

import 'package:flashco/common/profile_fallback.dart';
import 'package:flashco/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

const settings = FallbackConfig(
  selector: 'PROXY',
  name: 'Fallback',
  url: 'https://probe.example.invalid/check',
  interval: 10,
  timeout: 3000,
  lazy: false,
  expectedStatus: '204',
);

Map<String, dynamic> source() => {
  'proxies': [
    {'name': 'first', 'type': 'ss'},
    {'name': 'second', 'type': 'ss'},
  ],
  'proxy-groups': [
    {
      'name': 'PROXY',
      'type': 'select',
      'proxies': ['Fastest', 'first', 'second'],
    },
    {
      'name': 'Fastest',
      'type': 'url-test',
      'proxies': ['first', 'second'],
    },
  ],
  'rules': ['MATCH,PROXY'],
  'dns': {'enable': true},
  'tun': {'enable': true},
};

void main() {
  test('adds ordered native fallback without changing its input or rules', () {
    final input = source();
    final before = jsonEncode(input);
    final result = applyProfileFallback(input, settings);
    final groups = (result.config['proxy-groups'] as List).cast<Map>();
    final fallback = groups.singleWhere(
      (group) => group['name'] == result.name,
    );

    expect(fallback['type'], 'fallback');
    expect(fallback['empty-fallback'], 'REJECT');
    expect(fallback['proxies'], ['first', 'second']);
    expect(fallback['interval'], 10);
    expect(fallback['timeout'], 3000);
    expect(fallback['lazy'], isFalse);
    expect(fallback['expected-status'], '204');
    expect(groups.first['proxies'], ['Fallback', 'Fastest', 'first', 'second']);
    expect(result.config['rules'], input['rules']);
    expect(result.config['dns'], input['dns']);
    expect(result.config['tun'], input['tun']);
    expect(jsonEncode(input), before);
    expect(applyProfileFallback(result.config, settings).config, result.config);
  });

  test('configures provider-owned checks without losing provider options', () {
    final input = source()
      ..['proxy-providers'] = {
        'subscription': {
          'type': 'http',
          'url': 'https://subscription.example.invalid/nodes',
          'interval': 86400,
          'health-check': {'enable': false, 'interval': 300},
        },
      };
    final before = jsonEncode(input);
    final result = applyProfileFallback(input, settings);
    final provider = (result.config['proxy-providers'] as Map)['subscription'];
    final groups = (result.config['proxy-groups'] as List).cast<Map>();

    expect(groups.last['use'], ['subscription']);
    expect(provider['interval'], 86400);
    expect(provider['health-check'], {
      'enable': true,
      'url': settings.url,
      'interval': 10,
      'timeout': 3000,
      'lazy': false,
      'expected-status': '204',
    });
    expect(jsonEncode(input), before);
  });

  test('keeps an unrelated group when the configured name is occupied', () {
    final input = source();
    (input['proxy-groups'] as List).add({
      'name': 'Fallback',
      'type': 'select',
      'proxies': ['first'],
    });
    final result = applyProfileFallback(input, settings);
    expect(result.name, 'Fallback (1)');
    expect((result.config['proxy-groups'] as List)[2], {
      'name': 'Fallback',
      'type': 'select',
      'proxies': ['first'],
    });
  });

  test('reserves names of proxies excluded from fallback membership', () {
    final input = source();
    (input['proxies'] as List).add({'name': 'Fallback', 'type': 'direct'});
    final result = applyProfileFallback(input, settings);
    expect(result.name, 'Fallback (1)');
    expect((result.config['proxy-groups'] as List).last['proxies'], [
      'first',
      'second',
    ]);
  });

  test(
    'does not insert an empty group or silently replace an unknown target',
    () {
      expect(
        () => applyProfileFallback(source()..['proxies'] = [], settings),
        throwsFormatException,
      );
      expect(
        () => applyProfileFallback(
          source(),
          settings.copyWith(selector: 'missing'),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'saved profile settings round-trip and old profiles remain opted out',
    () {
      const original = ProfileOverrides(fallback: settings);
      final restored = ProfileOverrides.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(restored.fallback, settings);
      expect(ProfileOverrides.fromJson({}).fallback, isNull);
    },
  );
}
