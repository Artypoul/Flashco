import 'dart:convert';

import 'package:flashco/common/automatic_failover.dart';
import 'package:flashco/common/task.dart';
import 'package:flashco/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

Map<String, dynamic> fixture() => {
  'proxies': [
    for (final name in ['A', 'B'])
      {'name': name, 'type': 'vless', 'server': '$name.example', 'port': 443},
  ],
  'proxy-groups': [
    {
      'name': 'User choice',
      'type': 'select',
      'proxies': ['Fast', 'A', 'B'],
    },
    {
      'name': 'Fast',
      'type': 'url-test',
      'proxies': ['A', 'B'],
    },
    {
      'name': 'Bypass policy',
      'type': 'select',
      'proxies': ['DIRECT', 'A'],
    },
  ],
};

void main() {
  test(
    'automatic groups keep names and members and check nodes in the background',
    () {
      final raw = fixture();
      final original = jsonEncode(raw);
      applyAutomaticFailover(
        raw,
        enabled: true,
        interval: 7,
        testUrl: 'https://probe.example/check',
      );
      final group = raw['proxy-groups'][0];
      expect(group['name'], 'User choice');
      expect(group['proxies'], ['Fast', 'A', 'B']);
      expect(group['type'], 'fallback');
      expect(group['lazy'], false);
      expect(group['interval'], 7);
      expect(group['url'], 'https://probe.example/check');
      expect(group['empty-fallback'], 'REJECT');
      expect(raw['proxy-groups'][1]['type'], 'url-test');
      expect(raw['proxy-groups'][2]['type'], 'select');
      final disabled = fixture();
      applyAutomaticFailover(
        disabled,
        enabled: false,
        interval: 7,
        testUrl: 'unused',
      );
      expect(jsonEncode(disabled), original);
    },
  );

  test(
    'saved profile settings override defaults in the final runtime config',
    () async {
      final saved = ProfileOverrides.fromJson(
        jsonDecode(
          jsonEncode(
            const ProfileOverrides(
              autoReconnect: false,
              autoFailover: false,
              reconnectInterval: 23,
            ),
          ),
        ),
      );
      expect(saved.autoReconnect, false);
      expect(saved.reconnectInterval, 23);
      for (final enabled in [false, true]) {
        final result = await makeRealProfileTask(
          MakeRealProfileState(
            profilesPath: '/profiles',
            profileId: 1,
            rawConfig: fixture(),
            testUrl: 'https://probe.example/check',
            realPatchConfig: const PatchClashConfig(autoFailover: false),
            overrides: saved.copyWith(autoFailover: enabled),
            appendSystemDns: false,
            proxyGroups: const [],
            rules: const [],
            addedRules: const [],
            defaultUA: 'test',
          ),
        );
        final yaml = loadYaml(result.yaml) as Map;
        expect(
          yaml['proxy-groups'][0]['type'],
          enabled ? 'fallback' : 'select',
        );
        if (enabled) expect(yaml['proxy-groups'][0]['interval'], 23);
      }
    },
  );
}
