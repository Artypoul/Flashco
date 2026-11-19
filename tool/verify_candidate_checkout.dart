import 'dart:io';

import 'release_cli.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1 || !RegExp(r'^[0-9a-f]{40}$').hasMatch(args.single)) {
    stderr.writeln('Expected one full source SHA.');
    exitCode = 1;
    return;
  }
  final valid = await verifySourceCheckout(
    runner: (executable, arguments, {environment}) async {
      final result = await Process.run(
        executable,
        arguments,
        environment: environment,
      );
      return ReleaseCommandResult(
        result.exitCode,
        result.stdout.toString(),
        result.stderr.toString(),
      );
    },
    sourceSha: args.single,
    requireCa: true,
  );
  if (!valid) {
    stderr.writeln(
      'Candidate checkout does not match its source SHA and verified CA.',
    );
    exitCode = 1;
  }
}
