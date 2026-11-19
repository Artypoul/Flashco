import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../tool/release_cli.dart';

void main() {
  test(
    'accepts only the verified CA change at the recorded submodule head',
    () async {
      final temp = await Directory.systemTemp.createTemp('checkout-integrity-');
      addTearDown(() => temp.delete(recursive: true));
      final ca = File('${temp.path}/ca.crt')
        ..writeAsStringSync('verified bundle');
      final digest = sha256.convert(utf8.encode('verified bundle')).toString();
      const head = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      var rootStatus = ' M core/Clash.Meta\n';
      var nestedStatus = ' M component/ca/ca-certificates.crt\n';
      var actualSubmodule = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      Future<ReleaseCommandResult> runner(
        String executable,
        List<String> args, {
        Map<String, String>? environment,
      }) async {
        final output = switch (args.join(' ')) {
          'rev-parse HEAD' => head,
          'status --porcelain --untracked-files=no' => rootStatus,
          'rev-parse HEAD:core/Clash.Meta' =>
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          '-C core/Clash.Meta rev-parse HEAD' => actualSubmodule,
          '-C core/Clash.Meta status --porcelain --untracked-files=no' =>
            nestedStatus,
          _ => throw StateError('unexpected command $args'),
        };
        return ReleaseCommandResult(0, output);
      }

      Future<bool> valid({String expected = head, String hash = ''}) =>
          verifySourceCheckout(
            runner: runner,
            sourceSha: expected,
            requireCa: true,
            caFile: ca,
            expectedCaDigest: hash.isEmpty ? digest : hash,
          );
      expect(await valid(), isTrue);
      expect(await valid(hash: '0' * 64), isFalse);
      nestedStatus += ' M another-file\n';
      expect(await valid(), isFalse);
      nestedStatus = ' M component/ca/ca-certificates.crt\n';
      actualSubmodule = 'cccccccccccccccccccccccccccccccccccccccc';
      expect(await valid(), isFalse);
      actualSubmodule = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      rootStatus += ' M pubspec.lock\n';
      expect(await valid(), isFalse);
      rootStatus = ' M pubspec.lock\n';
      expect(await valid(), isFalse);
      rootStatus = ' M core/Clash.Meta\n';
      expect(await valid(expected: 'd' * 40), isFalse);
    },
  );
}
