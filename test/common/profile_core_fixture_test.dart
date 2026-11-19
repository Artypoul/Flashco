import 'dart:convert';
import 'dart:io';

import 'package:flashco/common/constant.dart';
import 'package:flashco/common/task.dart';
import 'package:flashco/flashco/profile_fallback.dart';
import 'package:flashco/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

const _publicKey = 'SbVKOEMjK0sIlbwg4akyBg5mL5KZwwB-ed4eEE7YnRc';
const _fallback = FallbackConfig(
  selector: 'PROXY',
  name: 'Flashco fallback',
  url: 'http://127.0.0.1/generate_204',
  interval: 10,
  timeout: 3000,
  lazy: false,
  expectedStatus: '204',
);

Map<String, dynamic> _proxy(String name, {bool? mlkem, String? fingerprint}) =>
    {
      'name': name,
      'type': 'vless',
      'server': '127.0.0.1',
      'port': 443,
      'uuid': '2a70e3a9-b4ce-4f20-908d-e99950a0a611',
      'network': 'tcp',
      'tls': true,
      'client-fingerprint': ?fingerprint,
      'reality-opts': {
        'public-key': _publicKey,
        'short-id': '0123',
        'support-x25519mlkem768': ?mlkem,
      },
    };

Future<String> _build(Map<String, dynamic> rawConfig) async {
  final result = await makeRealProfileTask(
    MakeRealProfileState(
      profilesPath: '/profiles',
      profileId: 1,
      rawConfig: rawConfig,
      realPatchConfig: const PatchClashConfig(),
      appendSystemDns: false,
      proxyGroups: const [],
      rules: const [],
      addedRules: const [],
      defaultUA: 'Flashco-Test',
    ),
  );
  return result.yaml;
}

Future<void> _export(String name, String yaml) async {
  final path = Platform.environment['FLASHCO_CORE_FIXTURE_DIR'];
  if (path == null) return;
  // CI consumes these exact final profiles in the pinned Core, with opt-in on.
  expect(realitySupportX25519Mlkem768, isTrue);
  await Directory(path).create(recursive: true);
  await File('$path/$name').writeAsString(yaml);
}

void main() {
  test(
    '350 valid nodes survive fallback and the final YAML pipeline',
    () async {
      final nodes = List.generate(350, (i) => _proxy('node-${i + 1}'));
      final raw = <String, dynamic>{
        'proxies': nodes,
        'proxy-groups': [
          {
            'name': 'PROXY',
            'type': 'select',
            'proxies': ['node-1', 'DIRECT'],
          },
        ],
        'rules': ['DOMAIN,example.invalid,DIRECT', 'MATCH,PROXY'],
      };
      final original = jsonEncode(raw);
      final fallback = applyProfileFallback(raw, _fallback);
      final yaml = await _build(fallback.config);
      final config = loadYaml(yaml) as YamlMap;
      final proxies = config['proxies'] as YamlList;
      final groups = config['proxy-groups'] as YamlList;
      final group = groups.cast<YamlMap>().singleWhere(
        (value) => value['name'] == _fallback.name,
      );
      expect(proxies, hasLength(350));
      expect(group['type'], 'fallback');
      expect(group['proxies'], nodes.map((proxy) => proxy['name']).toList());
      expect(group['empty-fallback'], 'REJECT');
      expect(group['interval'], 10);
      expect(group['timeout'], 3000);
      expect(group['lazy'], isFalse);
      expect(group['expected-status'], '204');
      expect(config['rules'], raw['rules']);
      for (final proxy in proxies.cast<YamlMap>()) {
        expect(proxy['uuid'], nodes.first['uuid']);
        expect(proxy['reality-opts']['public-key'], _publicKey);
        expect(
          proxy['reality-opts']['support-x25519mlkem768'],
          realitySupportX25519Mlkem768 ? isTrue : isNull,
        );
      }
      expect(jsonEncode(raw), original);
      await _export('fallback-350.yaml', yaml);
    },
  );

  test(
    'an ineligible provider keeps the fallback closed in final YAML',
    () async {
      final raw = <String, dynamic>{
        'proxy-providers': {
          'subscription': {
            'type': 'inline',
            'payload': [
              {'name': 'provider-direct', 'type': 'direct'},
            ],
          },
        },
        'proxy-groups': [
          {
            'name': 'PROXY',
            'type': 'select',
            'proxies': ['DIRECT'],
          },
        ],
        'rules': ['MATCH,PROXY'],
      };
      final yaml = await _build(applyProfileFallback(raw, _fallback).config);
      final config = loadYaml(yaml) as YamlMap;
      final fallback = (config['proxy-groups'] as YamlList)
          .cast<YamlMap>()
          .singleWhere((group) => group['name'] == _fallback.name);
      expect(fallback['use'], ['subscription']);
      expect(fallback.containsKey('proxies'), isFalse);
      expect(fallback['empty-fallback'], 'REJECT');
      await _export('empty-provider.yaml', yaml);
    },
  );

  test(
    'provider refresh fixture contains final ordered REALITY defaults',
    () async {
      final payload = [
        _proxy('missing'),
        _proxy('explicit-false', mlkem: false, fingerprint: 'firefox'),
        _proxy('explicit-true', mlkem: true, fingerprint: 'chrome120'),
      ];
      final raw = <String, dynamic>{
        'proxy-providers': {
          'subscription': {
            'type': 'inline',
            'payload': payload,
            'override': {
              'additional-prefix': 'Saved ',
              'override-expr': ['.udp = true'],
            },
          },
        },
        'proxy-groups': [
          {
            'name': 'PROXY',
            'type': 'select',
            'use': ['subscription'],
          },
        ],
        'rules': ['MATCH,PROXY'],
      };
      final original = jsonEncode(raw);
      final yaml = await _build(raw);
      final config = loadYaml(yaml) as YamlMap;
      final provider = config['proxy-providers']['subscription'] as YamlMap;
      expect(provider['payload'], payload);
      final expressions = provider['override']['override-expr'] as YamlList;
      expect(expressions.first, '.udp = true');
      expect(expressions, hasLength(realitySupportX25519Mlkem768 ? 3 : 1));
      expect(jsonEncode(raw), original);
      await _export('provider-refresh.yaml', yaml);
    },
  );
}
