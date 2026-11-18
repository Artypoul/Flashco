import 'dart:convert';
import 'dart:io';

import 'package:flashco/common/constant.dart';
import 'package:flashco/common/reality_defaults.dart';
import 'package:flashco/common/task.dart';
import 'package:flashco/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

const _proxy = {
  'name': 'reality',
  'type': 'vless',
  'server': 'example.invalid',
  'port': 443,
  'tls': true,
  'reality-opts': {'public-key': 'test-public-key', 'short-id': '000123'},
};
const _provider = {
  'type': 'inline',
  'payload': [_proxy],
  'override': {
    'additional-prefix': 'Saved ',
    'override-expr': ['.udp = true'],
  },
};

void main() {
  test('disabled defaults leave the input untouched', () {
    const input = {
      'proxies': [_proxy],
      'proxy-providers': {'subscription': _provider},
    };
    expect(applyRealityDefaults(input, enabled: false), same(input));
  });

  test('REALITY defaults preserve keys, routing and immutable input', () {
    const input = {
      'proxies': [_proxy],
      'rules': ['MATCH,PROXY'],
      'proxy-groups': [
        {
          'name': 'PROXY',
          'type': 'select',
          'proxies': ['reality'],
        },
      ],
    };
    final result = applyRealityDefaults(input, enabled: true);
    expect(result['proxies'], [
      {
        ..._proxy,
        'client-fingerprint': 'chrome',
        'reality-opts': {
          ..._proxy['reality-opts'] as Map,
          'support-x25519mlkem768': true,
        },
      },
    ]);
    expect(result['rules'], input['rules']);
    expect(result['proxy-groups'], input['proxy-groups']);
    expect(input['proxies'], [_proxy]);
  });

  for (final value in [true, false, null]) {
    test('preserves an explicitly present ML-KEM value: $value', () {
      final proxy = {
        ..._proxy,
        'client-fingerprint': 'firefox',
        'reality-opts': {
          ..._proxy['reality-opts'] as Map,
          'support-x25519mlkem768': value,
        },
      };
      final input = {
        'proxies': [proxy],
      };
      expect(applyRealityDefaults(input, enabled: true), input);
    });
  }

  for (final value in ['chrome120', 'firefox', 'none', '', null]) {
    test('preserves an explicitly present fingerprint: $value', () {
      final result = applyRealityDefaults({
        'proxies': [
          {..._proxy, 'client-fingerprint': value},
        ],
      }, enabled: true);
      final proxy = (result['proxies'] as List).single as Map;
      expect(proxy['client-fingerprint'], value);
      expect(proxy['reality-opts']['support-x25519mlkem768'], isTrue);
    });
  }

  test('unrelated proxies and malformed REALITY options remain unchanged', () {
    const input = {
      'proxies': [
        null,
        {'type': 'ss', 'name': 'plain'},
        {'reality-opts': null},
        {'reality-opts': 'invalid'},
        {'reality-opts': <String, dynamic>{}},
        {
          'reality-opts': {'public-key': ''},
        },
        {
          'reality-opts': {'public-key': 123},
        },
      ],
    };
    expect(applyRealityDefaults(input, enabled: true), input);
  });

  for (final type in ['http', 'file', 'inline']) {
    test('$type provider keeps ordered overrides and its original payload', () {
      final provider = {
        ..._provider,
        'type': type,
        'interval': 86400,
        'filter': 'edge',
      };
      final input = {
        'proxy-providers': {'subscription': provider},
      };
      final result = applyRealityDefaults(input, enabled: true);
      final patched = result['proxy-providers']['subscription'] as Map;
      expect(patched['type'], type);
      expect(patched['interval'], 86400);
      expect(patched['filter'], 'edge');
      expect(patched['payload'], [_proxy]);
      expect(patched['override']['additional-prefix'], 'Saved ');
      final expressions = patched['override']['override-expr'] as List;
      expect(expressions, hasLength(3));
      expect(expressions.first, '.udp = true');
      expect(provider['override'], _provider['override']);
      expect(applyRealityDefaults(result, enabled: true), result);
    });
  }

  test('malformed provider overrides remain Core validation errors', () {
    const input = {
      'proxy-providers': {
        'invalid': 'invalid',
        'override': {'type': 'inline', 'override': 'invalid'},
        'expressions': {
          'type': 'inline',
          'override': {'override-expr': 123},
        },
      },
    };
    expect(applyRealityDefaults(input, enabled: true), input);
  });

  test('a refreshed subscription receives defaults without rewriting it', () {
    for (final name in ['original', 'refreshed']) {
      final input = {
        'proxies': [
          {..._proxy, 'name': name},
        ],
      };
      final before = jsonEncode(input);
      final result = applyRealityDefaults(input, enabled: true);
      final proxy = (result['proxies'] as List).single as Map;
      expect(proxy['name'], name);
      expect(proxy['reality-opts']['support-x25519mlkem768'], isTrue);
      expect(jsonEncode(input), before);
      expect(applyRealityDefaults(result, enabled: true), result);
    }
  });

  test('defaults follow existing expressions even after earlier defaults', () {
    final generated = applyRealityDefaults({
      'proxy-providers': {
        'subscription': {'type': 'inline'},
      },
    }, enabled: true);
    final defaults = List<String>.from(
      generated['proxy-providers']['subscription']['override']['override-expr'],
    );
    final existing = [
      ...defaults,
      'del(.reality-opts.support-x25519mlkem768)',
      'del(.client-fingerprint)',
    ];
    final result = applyRealityDefaults({
      'proxy-providers': {
        'subscription': {
          'type': 'inline',
          'override': {'override-expr': existing},
        },
      },
    }, enabled: true);
    expect(
      result['proxy-providers']['subscription']['override']['override-expr'],
      [...existing, ...defaults],
    );
    expect(applyRealityDefaults(result, enabled: true), result);
  });

  test('compiled flag reaches final YAML and injected providers', () async {
    final result = await makeRealProfileTask(
      const MakeRealProfileState(
        profilesPath: '/profiles',
        profileId: 1,
        rawConfig: {
          'proxies': [_proxy],
          'proxy-providers': {'subscription': _provider},
          'rules': ['MATCH,DIRECT'],
        },
        injectedProxyProviders: {'injected': _provider},
        realPatchConfig: PatchClashConfig(),
        appendSystemDns: false,
        proxyGroups: [],
        rules: [],
        addedRules: [],
        defaultUA: 'Flashco-Test',
      ),
    );
    final config = loadYaml(result.yaml) as YamlMap;
    final proxy = (config['proxies'] as YamlList).single as YamlMap;
    final providers = config['proxy-providers'] as YamlMap;
    if (realitySupportX25519Mlkem768) {
      expect(proxy['reality-opts']['support-x25519mlkem768'], isTrue);
      expect(proxy['client-fingerprint'], 'chrome');
      for (final name in ['subscription', 'injected']) {
        expect(providers[name]['override']['override-expr'], hasLength(3));
        expect(providers[name]['payload'], [_proxy]);
      }
    } else {
      expect(proxy, _proxy);
      for (final name in ['subscription', 'injected']) {
        expect(providers[name]['override'], _provider['override']);
      }
    }
    expect(config['rules'], ['MATCH,DIRECT']);
    final fixturePath = Platform.environment['REALITY_MLKEM_FIXTURE_PATH'];
    if (fixturePath != null) {
      expect(realitySupportX25519Mlkem768, isTrue);
      await File(fixturePath).writeAsString(
        jsonEncode(providers['subscription']['override']['override-expr']),
      );
    }
  });
}
