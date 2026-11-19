import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../tool/release_cli.dart';

void main() {
  test(
    'Flutter registrants stay clean after LF regeneration on CRLF hosts',
    () async {
      final temp = await Directory.systemTemp.createTemp('registrant-git-');
      addTearDown(() => temp.delete(recursive: true));
      Future<String> git(List<String> args) async {
        final result = await Process.run(
          'git',
          args,
          workingDirectory: temp.path,
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        return result.stdout.toString();
      }

      const paths = [
        'linux/flutter/generated_plugin_registrant.cc',
        'linux/flutter/generated_plugin_registrant.h',
        'linux/flutter/generated_plugins.cmake',
        'macos/Flutter/GeneratedPluginRegistrant.swift',
        'windows/flutter/generated_plugin_registrant.cc',
        'windows/flutter/generated_plugin_registrant.h',
        'windows/flutter/generated_plugins.cmake',
      ];
      final generated = <String, String>{};
      await File('.gitattributes').copy('${temp.path}/.gitattributes');
      for (final path in paths) {
        final content = File(path).readAsStringSync().replaceAll('\r\n', '\n');
        generated[path] = content;
        File('${temp.path}/$path')
          ..createSync(recursive: true)
          ..writeAsStringSync(content);
      }
      await git(['init', '-q']);
      await git(['config', 'core.autocrlf', 'true']);
      await git(['add', '.']);
      await git([
        '-c',
        'user.name=Fixture',
        '-c',
        'user.email=fixture@example.invalid',
        'commit',
        '-qm',
        'fixture',
      ]);
      for (final path in paths) {
        File('${temp.path}/$path').deleteSync();
      }
      await git(['checkout', '--', ...paths]);
      for (final path in paths) {
        final file = File('${temp.path}/$path');
        expect(file.readAsStringSync(), generated[path]);
        file.writeAsStringSync(generated[path]!);
      }
      expect(
        await git(['status', '--porcelain', '--untracked-files=no']),
        isEmpty,
      );
      File(
        '${temp.path}/${paths.first}',
      ).writeAsStringSync('${generated[paths.first]}\n// actual edit\n');
      expect(
        await git(['status', '--porcelain', '--untracked-files=no']),
        contains(' M ${paths.first}'),
      );
      expect(
        await git(['diff', '--no-ext-diff', '--no-color']),
        contains('+// actual edit'),
      );
    },
  );

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
      final diagnostics = <String>[];
      expect(
        await verifySourceCheckout(
          runner: runner,
          sourceSha: head,
          requireCa: true,
          caFile: ca,
          expectedCaDigest: digest,
          onFailure: diagnostics.add,
        ),
        isFalse,
      );
      expect(diagnostics.single, contains(' M pubspec.lock'));
      expect(diagnostics.single, contains('Unexpected root git status'));
      rootStatus = ' M pubspec.lock\n';
      expect(await valid(), isFalse);
      rootStatus = ' M core/Clash.Meta\n';
      expect(await valid(expected: 'd' * 40), isFalse);
    },
  );
}
