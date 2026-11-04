import 'dart:convert';

import 'package:flashco/common/common.dart';
import 'package:flashco/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

Map<String, dynamic> pairFixture() => {
  'proxies': [
    for (final network in ['xhttp', 'grpc'])
      {
        'name': 'Node $network',
        'type': 'vless',
        'network': network,
        'server': 'endpoint.example',
        'port': 443,
      },
    {
      'name': 'Other country',
      'type': 'vless',
      'server': 'other.example',
      'port': 443,
    },
  ],
  'proxy-groups': [
    {
      'name': 'My route',
      'type': 'select',
      'proxies': ['Other country', 'Node grpc', 'Node xhttp'],
      'include-all': true,
      'filter': '.*',
      'use': ['remote'],
    },
    {
      'name': 'Other route',
      'type': 'select',
      'proxies': ['DIRECT', 'Other country'],
    },
  ],
};

ProfileNodeFailover pairChoice(Map config) {
  final nodes = profileFailoverNodes(config);
  return ProfileNodeFailover(
    groupName: 'My route',
    primaryKey: nodes[0].key,
    backupKey: nodes[1].key,
    primaryName: nodes[0].name,
    backupName: nodes[1].name,
  );
}

void main() {
  test('an explicit GLOBAL group cannot route outside the saved pair', () {
    for (final type in ['select', 'fallback', 'load-balance']) {
      final config = pairFixture();
      final choice = pairChoice(config);
      (config['proxy-groups'] as List).add({
        'name': 'GLOBAL',
        'type': type,
        'proxies': ['Other country'],
      });
      applyProfileNodeFailover(
        config,
        choice: choice,
        interval: 15,
        testUrl: 'probe',
      );
      final global = (config['proxy-groups'] as List)
          .whereType<Map>()
          .singleWhere((group) => group['name'] == 'GLOBAL');
      expect(global['type'], 'select');
      expect(global['proxies'], ['My route']);
    }
  });

  test('virtual hosts remain distinct and header spelling is normalized', () {
    final proxy = {
      'type': 'vless',
      'server': 'shared.example',
      'port': 443,
      'network': 'ws',
    };
    Map node(String host, [String header = 'Host']) => {
      ...proxy,
      'name': host,
      'ws-opts': {
        'path': '/ws',
        'headers': {header: host},
      },
    };
    final a = node('a.example');
    final b = node('b.example');
    expect(
      profileFailoverNodes({
        'proxies': [a, b],
      }),
      hasLength(2),
    );
    expect(
      profileFailoverNodeKey(a),
      profileFailoverNodeKey(node('A.EXAMPLE', 'host')),
    );
  });

  test('inline promotion reserves group names and builtin names', () {
    final config = pairFixture();
    config['proxies'][0]['name'] = 'My route';
    config['proxies'][1]['name'] = 'DIRECT';
    final choice = pairChoice(config);
    final payload = config.remove('proxies');
    config['proxy-providers'] = {
      'source': {'type': 'inline', 'payload': payload},
    };
    applyProfileNodeFailover(
      config,
      choice: choice,
      interval: 15,
      testUrl: 'probe',
    );
    final members = config['proxy-groups'][0]['proxies'] as List;
    expect(members, ['My route (2)', 'DIRECT (2)']);
    expect(config['proxies'], hasLength(2));
  });

  test('inline provider transformations are not silently discarded', () {
    final config = pairFixture();
    final choice = pairChoice(config);
    final payload = config.remove('proxies');
    config['proxy-providers'] = {
      'source': {
        'type': 'inline',
        'payload': payload,
        'dialer-proxy': 'Required tunnel',
        'override': {'skip-cert-verify': true},
      },
    };
    expect(profileFailoverNodes(config), isEmpty);
    applyProfileNodeFailover(
      config,
      choice: choice,
      interval: 15,
      testUrl: 'probe',
    );
    expect(config['proxy-groups'][0]['proxies'], ['REJECT']);
  });

  test(
    'node identity survives renames but distinguishes transports and paths',
    () {
      final config = pairFixture();
      final nodes = profileFailoverNodes(config);
      expect(nodes[0].key, isNot(nodes[1].key));
      final proxy = config['proxies'][0] as Map;
      expect(
        profileFailoverNodeKey({
          ...proxy,
          'name': 'Renamed',
          'uuid': 'new-user',
        }),
        nodes[0].key,
      );
      expect(
        profileFailoverNodeKey({
          ...proxy,
          'xhttp-opts': {'path': '/a'},
        }),
        isNot(
          profileFailoverNodeKey({
            ...proxy,
            'xhttp-opts': {'path': '/b'},
          }),
        ),
      );
    },
  );

  test(
    'an enabled pair uses only its two nodes in order and no provider expansion',
    () {
      final config = pairFixture();
      final original = jsonEncode(config);
      final choice = pairChoice(config);
      applyProfileNodeFailover(
        config,
        choice: choice,
        interval: 19,
        testUrl: 'https://probe.example',
      );
      final group = config['proxy-groups'][0] as Map;
      expect(group['proxies'], ['Node xhttp', 'Node grpc']);
      expect(group['type'], 'fallback');
      expect(group['fallback-mode'], 'ordered');
      expect(group['interval'], 19);
      expect(group['lazy'], false);
      expect(group['url'], 'https://probe.example');
      expect(group['use'], isNull);
      expect(group['include-all'], isNull);
      expect(group['filter'], isNull);
      expect(config['proxy-groups'][1]['proxies'], ['DIRECT', 'Other country']);
      final disabled = pairFixture();
      applyProfileNodeFailover(
        disabled,
        choice: choice.copyWith(enabled: false),
        interval: 19,
        testUrl: 'unused',
      );
      expect(jsonEncode(disabled), original);
    },
  );

  test(
    'renamed nodes resolve by identity; missing nodes never select another country',
    () {
      final config = pairFixture();
      final choice = pairChoice(config);
      config['proxies'][0]['name'] = 'Renamed primary';
      applyProfileNodeFailover(
        config,
        choice: choice,
        interval: 15,
        testUrl: 'probe',
      );
      expect(config['proxy-groups'][0]['proxies'], [
        'Renamed primary',
        'Node grpc',
      ]);
      (config['proxies'] as List).removeAt(0);
      applyProfileNodeFailover(
        config,
        choice: choice,
        interval: 15,
        testUrl: 'probe',
      );
      expect(config['proxy-groups'][0]['proxies'], ['Node grpc']);
      (config['proxies'] as List).removeAt(0);
      applyProfileNodeFailover(
        config,
        choice: choice,
        interval: 15,
        testUrl: 'probe',
      );
      expect(config['proxy-groups'][0]['proxies'], ['REJECT']);
      final absent = pairFixture();
      absent['proxy-groups'] = [];
      expect(
        () => applyProfileNodeFailover(
          absent,
          choice: choice,
          interval: 15,
          testUrl: 'probe',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'inline provider nodes are materialized without unrelated provider members',
    () {
      final config = pairFixture();
      final choice = pairChoice(config);
      final proxies = config.remove('proxies');
      config['proxy-providers'] = {
        'remote': {'type': 'inline', 'payload': proxies},
      };
      applyProfileNodeFailover(
        config,
        choice: choice,
        interval: 15,
        testUrl: 'probe',
      );
      expect(config['proxies'], hasLength(2));
      expect(config['proxy-groups'][0]['proxies'], ['Node xhttp', 'Node grpc']);
    },
  );

  test(
    'saved profile pair reaches final YAML even with general failover disabled',
    () async {
      final config = pairFixture();
      final original = jsonEncode(config);
      final profile = Profile.normal(url: 'https://example.com/sub').copyWith(
        overrides: ProfileOverrides(
          autoFailover: false,
          reconnectInterval: 23,
          nodeFailover: pairChoice(config),
        ),
      );
      final saved = Profile.fromJson(jsonDecode(jsonEncode(profile)));
      expect(saved.overrides.nodeFailover, profile.overrides.nodeFailover);
      final result = await makeRealProfileTask(
        MakeRealProfileState(
          profilesPath: '/profiles',
          profileId: 1,
          rawConfig: config,
          testUrl: 'https://probe.example',
          realPatchConfig: const PatchClashConfig(autoFailover: false),
          overrides: saved.overrides,
          appendSystemDns: false,
          proxyGroups: const [],
          rules: const [],
          addedRules: const [],
          defaultUA: 'test',
        ),
      );
      final group = (loadYaml(result.yaml) as Map)['proxy-groups'][0];
      expect(group['proxies'], ['Node xhttp', 'Node grpc']);
      expect(group['type'], 'fallback');
      expect(group['interval'], 23);
      expect(jsonEncode(config), original);
    },
  );
}
