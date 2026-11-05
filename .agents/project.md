# Project Context

Flashco is a multi-platform proxy client based on ClashMeta (mihomo), built with Flutter. It supports Android, Windows, macOS, and Linux, using a Material You design with Surfboard-like UI.

## Current Baseline — 2026-11-05 rollback

- Repository: `Artypoul/Flashco`, base branch `main`, donor base v0.9.0. The user selected restoration of application code to
  `da07f58a94ea417ff3fe2d77317754dafa377d6f` (2026-11-01), before the new fallback, ML-KEM settings, recovery and Safe changes.
  Rollback [PR #11](https://github.com/Artypoul/Flashco/pull/11) is merged into `main` at `017b10cfc28b49ad7dd64258e7fb37777143fff2`; application code commit `54d4a82bb42dfc0366e3e7d959509736f6598cac` and Core match the selected target.
- Database schema: 21 (`lib/database/database.dart`); application settings migration: 2 (`lib/common/migration.dart`).
  These are separate version counters.
- The new fallback, editable ML-KEM overrides, automatic reconnect/failover, Safe and ten-minute subscription defaults are removed.
  Existing installed data is not rewritten by this source rollback. Product behavior is defined in [PRODUCT.md](../PRODUCT.md).
- Personal workflows: `personal-windows.yaml` produces EXE/ZIP and `personal-android.yaml` produces a universal APK.
  Both take the required `subscription_url` input without committing its value. Each restores its original four Flutter suites.
- The Windows [41848512761](https://github.com/Artypoul/Flashco/actions/runs/41848512761) and Android
  [41848533942](https://github.com/Artypoul/Flashco/actions/runs/41848533942) runs succeeded for `04c56386` and include Safe.
  Those artifacts contain the newer Safe code and do not validate the rollback. Provenance and validation limits are in [history.md](../history.md); current state is in
  [память.md](../память.md).
- Dependency resolution and analyzer passed for the exact restored application tree. The first test attempt was blocked by a full C: drive;
  after recovered disk space, all 240 targeted tests passed. Formatting checked 872 files with no changes; comment-density and independent code review passed. Runtime/device testing is unconfirmed.
- All nine PR validation jobs passed in [build 41974675631](https://github.com/Artypoul/Flashco/actions/runs/41974675631). The separate merge-commit [build 41976324395](https://github.com/Artypoul/Flashco/actions/runs/41976324395) also completed successfully: all nine validation jobs passed, including full Dart tests, coverage, changelog verification and Windows/macOS/Linux debug builds. Packaging/upload were skipped by workflow conditions.
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
The Core submodule returns to `chen08209/Clash.Meta` at `8380d0e7462f061a964323e9bf3129a236fcc5d5` (see `.gitmodules`). The upstream fixes needed to remove
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
