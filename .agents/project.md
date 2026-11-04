# Project Context

Flashco is a multi-platform proxy client based on ClashMeta (mihomo), built with Flutter. It supports Android, Windows, macOS, and Linux, using a Material You design with Surfboard-like UI.

## Current Baseline — 2026-11-04

- Repository: `Artypoul/Flashco`, base branch `main`, donor base v0.9.0. The latest verified application change is
  [`9338711d`](https://github.com/Artypoul/Flashco/commit/9338711d4a1eb7428c74027361f94d1027424e38).
  Later documentation commits do not change which application revision an artifact contains.
- Database schema: 22 (`lib/database/database.dart`); application settings migration: 2 (`lib/common/migration.dart`).
  These are separate version counters.
- Shared settings support editable REALITY ML-KEM defaults, automatic reconnect/failover and a persistent profile-level
  primary/backup pair. Subscription refresh defaults to ten minutes and uses each profile's saved interval.
  Product behavior and provider limitations are defined in [PRODUCT.md](../PRODUCT.md).
- Personal workflows: `personal-windows.yaml` produces EXE/ZIP and `personal-android.yaml` produces a universal APK.
  Both take the required `subscription_url` input without committing its value. The local Safe update runs 19 Flutter suites and the
  ordered pair recovery test in the Go core before packaging.
- The Windows [41806428363](https://github.com/Artypoul/Flashco/actions/runs/41806428363) and Android
  [41806445081](https://github.com/Artypoul/Flashco/actions/runs/41806445081) runs succeeded for `9338711d`.
  Artifact provenance and validation limits are recorded in [history.md](../history.md); current handoff state is in
  [память.md](../память.md).
- Known verification limit: the full local suite still reports the pre-existing `test/lint/typography_test.dart`
  failure against the donor `AppTextStyle` architecture. The local Safe full run passed 4324 tests, skipped 6 and
  failed only that known lint test; 216 targeted checks and analyzer passed. The earlier personal builds validate
  `9338711d` only. Do not describe the full suite as green.
- Local work over `369f6ebd` moves primary/backup selection into the additional Safe proxy tab, with immediate profile persistence, ordinary-mode restoration and shared Windows/Android configuration. It is not included in the published artifacts above. See [PRODUCT.md](../PRODUCT.md) and current memory for verification status.
- Maintain these documents using [documentation.md](documentation.md).

## Version Notes

- Build, release and personal CI currently pin Flutter 3.47.6 and Go 1.27.1; Android uses NDK r28c.
  Workflow definitions are the source of truth for these pins. The editor in `plugins/code_forge` came from `code_forge` 10.14.0, which
  needs Dart 3.13.2, so the CI pin cannot go below Flutter 3.47.2.
- Before moving the pin, walk `flutter-upgrade.md`: it lists the workarounds tied to
  the current SDK, such as Impeller disabled on the Intel macOS release build.
- The Dart SDK lower bound in `pubspec.yaml` sets the package language
  version. `flutter analyze` excludes `lib/**/generated/**`, so a raise is
  proven by `flutter test`, which parses the generated code, not by analyze.

## Forked Dependencies

Two `pubspec.yaml` dependencies are pinned by commit SHA to donor-maintained forks under `chen08209`.
They are separate from the current `Artypoul/Flashco` repository; do not assume write access to them.
The Core submodule points to `Artypoul/Clash.Meta` (see `.gitmodules`). The upstream fixes needed to remove
the remaining dependency pins are recorded below.

Each entry records what the fork changes and what has to be true before it can go
back to the published package, so a future upgrade does not have to rediscover it.
Re-verify a fork by diffing its pub cache checkout against the published version
of the same number:

```bash
diff -ru ~/.pub-cache/hosted/pub.dev/<name>-<version> ~/.pub-cache/git/<name>-<sha>
```

The `window_manager` fork (`chen08209/window_manager`, tag `v0.5.1-flclash.3`)
was replaced by the in-repo `plugins/window` package; the behaviors it carried
(work-area maximize with a hidden title bar on Windows, geometry restore on
re-map on Linux, corner preference, terminate and activate events) live there
now, see the window plugin section of `architecture.md`.

`launch_at_startup` — `chen08209/launch_at_startup`, version 0.5.1.

- Migrates `win32_registry` from `^2.0.0` to `^3.0.3`, which is a breaking rename
  across the whole Windows implementation (`Registry.openPath` → `CURRENT_USER.open`,
  `createValue` → `setValue`, `getStringValue` → `getString`).
- This one is not optional while it lasts: Flashco depends on `win32_registry: ^3.0.3`
  directly, and upstream's `^2.0.0` constraint cannot co-resolve with it.
- Drop the fork when upstream publishes a release that accepts `win32_registry` 3.x.

`yaml_writer` — `chen08209/yaml_writer`, version 2.1.0.

- Adds `StringNode.quoteKey()` and applies it to map keys in `lib/src/node.dart`.
  Upstream quotes values but emits keys verbatim, so a profile key needing quotes
  is written as invalid YAML.
- Drop the fork once upstream quotes map keys by the same
  `isValidUnquotedString` rule it already applies to values.

The `code_forge` fork (`chen08209/code_forge`) is frozen: its Dart code now lives
in the in-repo `plugins/code_forge` package and its Rust code in the `editor/`
module of `plugins/rust_api`, both trimmed to what Flashco uses.
`plugins/code_forge/README.md` records what was kept and what was removed;
upstream's MIT notice stays in `plugins/code_forge/LICENSE`.

## Dependency Ceilings

`flutter pub outdated` lists only upstream-held entries, so treat them as
resolved-until-the-ceiling-moves rather than as debt:

- `intl` is intentionally unbounded (`any`) and `material_color_utilities` is
  resolved by the Flutter SDK; neither is a bound this repository sets.

`freezed`, the `riverpod` set, `build_runner`, `drift_dev`, `intl_utils` and
`test` all resolve against the analyzer the pinned SDK ships; none of them is
held back. When an upgrade fails version solving, record the blocker here with
what has to change upstream before the pin can move, so the next
`flutter pub outdated` run does not rediscover it.

`_initDynamicColor` in `lib/bootstrap.dart` reads the `dynamic_color` method
channel directly and decodes the palette list into a `TonalPalette`, instead of
going through `DynamicColorPlugin.getCorePalette()` and its deprecated
`CorePalette` return type. Everything downstream sees `DynamicColorSeeds`, so a
non-deprecated plugin accessor changes only that one function.

## Build Dependencies

Linux:

```bash
sudo apt-get install libayatana-appindicator3-dev
```

Windows:

- GCC and Inno Setup.

macOS:

```bash
npm install -g appdmg
```
