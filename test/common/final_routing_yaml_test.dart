import 'package:flashco/common/default_rules.dart';
import 'package:flashco/common/task.dart';
import 'package:flashco/common/profile_fallback.dart';
import 'package:flashco/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'profile_fallback_test.dart' show settings, source;

void main() {
  test(
    'personal fallback keeps the effective edited rules and uses native groups',
    () async {
      final input = applyProfileFallback(source(), settings).config;
      const edited = ['GEOIP,RU,DIRECT', 'DOMAIN-SUFFIX,example.ru,REJECT'];
      final result = await makeRealProfileTask(
        MakeRealProfileState(
          profilesPath: '/profiles',
          profileId: 1,
          rawConfig: input,
          realPatchConfig: const PatchClashConfig(),
          appendSystemDns: false,
          proxyGroups: const [],
          rules: const [],
          addedRules: [for (final rule in edited) Rule.parse(rule)],
          defaultUA: 'Flashco-Test',
        ),
      );
      final config = loadYaml(result.yaml) as YamlMap;
      expect(config['rules'], [...edited, 'MATCH,PROXY']);
      expect(config['rules'], isNot(contains('DOMAIN-SUFFIX,ru,DIRECT')));
      final groups = (config['proxy-groups'] as YamlList).cast<YamlMap>();
      expect(groups.last['type'], 'fallback');
      expect(groups.last['proxies'], ['first', 'second']);
      expect(groups.last['interval'], 10);
      expect(groups.last['timeout'], 3000);
      expect(groups.first['proxies'].first, 'Fallback');
    },
  );

  test(
    'generated subscription YAML keeps Russian direct rules before MATCH',
    () async {
      final result = await makeRealProfileTask(
        MakeRealProfileState(
          profilesPath: '/profiles',
          profileId: 1,
          rawConfig: {
            'rules': ['MATCH,PROXY'],
          },
          realPatchConfig: const PatchClashConfig(),
          appendSystemDns: false,
          proxyGroups: const [],
          rules: const [],
          addedRules: [
            for (final raw in russianServiceDirectRules) Rule.parse(raw),
          ],
          defaultUA: 'Flashco-Test',
        ),
      );
      final config = loadYaml(result.yaml) as YamlMap;
      final rules = (config['rules'] as YamlList).cast<String>();

      expect(
        rules.take(russianServiceDirectRules.length),
        russianServiceDirectRules,
      );
      expect(
        rules.indexOf('DOMAIN-SUFFIX,yandex.ru,DIRECT'),
        lessThan(rules.indexOf('MATCH,PROXY')),
      );
      expect(rules.last, 'MATCH,PROXY');
    },
  );
}
