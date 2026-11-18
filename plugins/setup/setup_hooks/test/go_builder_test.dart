import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:setup_hooks/src/build_cache.dart';
import 'package:setup_hooks/src/go_builder.dart';
import 'package:setup_hooks/src/options.dart';
import 'package:setup_hooks/src/target.dart';
import 'package:test/test.dart';

void main() {
  test('rebuilds when the local module source changes', () async {
    final root = Directory.systemTemp.createTempSync('go_builder_module_');
    addTearDown(() => root.deleteSync(recursive: true));
    void write(String path, String content) {
      File(p.join(root.path, path))
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    write(
      'core/go.mod',
      'module fixture\n\ngo 1.23\n\nrequire example.com/local v0.0.0\nreplace example.com/local => ../modules/flashco_core\n',
    );
    write(
      'core/cmd/core/main.go',
      'package main\nimport "example.com/local"\nfunc main() { local.Value() }\n',
    );
    write(
      'modules/flashco_core/go.mod',
      'module example.com/local\n\ngo 1.23\n',
    );
    write(
      'modules/flashco_core/local.go',
      'package local\nfunc Value() int { return 1 }\n',
    );
    final builder = GoBuilder(
      rootDir: root.path,
      config: BuildConfig.load(rootDir: root.path),
      cache: BuildCache(rootDir: root.path),
      notice: BuildNotice(),
    );
    expect((await builder.build(Target.linuxAmd64)).rebuilt, isTrue);
    expect((await builder.build(Target.linuxAmd64)).rebuilt, isFalse);
    write(
      'modules/flashco_core/local.go',
      'package local\nfunc Value() int { return 2 }\n',
    );
    expect((await builder.build(Target.linuxAmd64)).rebuilt, isTrue);
  });
}
