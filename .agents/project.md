# Project Context

## Audited baseline and donor update plan — 2026-11-18

Published Flashco `main` is `871a89e4d7da3fe4a484c193b2fbeccc57129c5b` after merged PR #14:
application 0.9.0, Core `8380d0e7462f061a964323e9bf3129a236fcc5d5`, SQLite 21, preferences version 2.
The [donor update plan](../docs/upstream/2026-11-18-v0.9.3-update-plan.md) targets stable FlClash v0.9.3
at `be84736605527034689c95bf27828ff27d912c5e`, Mihomo 1.19.33 at `024245dc72bc92f48237f865119afe0cd53ac9e6`,
and Prism UI at `63450c0ac0e8e1b2c0f3ed4ad7926dc94e083185`. This documentation change does not update those dependencies.
Existing Flutter/Go/NDK pins already match this stable target.

An unpublished local implementation checkpoint `60925e7` exists separately; at inspection the remote donor branch
still pointed to the baseline. Reconcile current refs and concurrent work before resuming it. The plan records
SQLite version collisions, preferences compatibility, profile-base preservation, module CI coverage and packaging gates.
Earlier results below are historical and do not validate the donor implementation.

Flashco is a multi-platform proxy client based on ClashMeta (mihomo), built with Flutter. It supports Android, Windows, macOS, and Linux, using a Material You design with Surfboard-like UI.

## Optional Android first-run subscription — 2026-11-18

- Based on `main` at `cd0bb943016b1fb717eb50742ba1947551bb01f0` (merged PR #13). The additional `personal-android-first-run.yaml` builds the same universal APK with `BOOTSTRAP_SUBSCRIPTION_ON_FIRST_RUN=true` and no embedded URL; original personal workflows and SDK pins are unchanged.
- `setup.dart` includes the existing fallback configuration in this mode. Fresh Android installations retain existing personal defaults; existing installations, desktop builds, safe mode and degraded starts do not enter the new prompt.
- The `subscriptionOnboarding` preference progresses from `initializing` to `pending` to `complete`. An interrupted fresh initialization resumes rules/defaults; a cancelled or failed import remains pending. Completion follows durable profile persistence, before VPN activation. The opt-in importer preserves a profile created or selected during download.
- Database schema and migration versions are unchanged. Use the existing generated provider definitions; regenerate after changing the provider source, never edit generated output manually.
- Validation evidence and remaining limitations are recorded in [history.md](../history.md) and [память.md](../память.md).

### REALITY ML-KEM default for this build

- `personal-android-first-run.yaml` enables `REALITY_SUPPORT_X25519MLKEM768=true` by default. `setup.dart` forwards the opt-in define through `env.json`; other workflows and builds remain unchanged.
- Final YAML generation applies `lib/common/reality_defaults.dart` after scripts and custom provider injection. Root REALITY nodes receive absent ML-KEM/fingerprint defaults; provider defaults use the pinned Core's ordered `override-expr` support, including provider refreshes. Explicit values and source payloads are preserved. The Core gitlink, database schema and models are unchanged.
- The workflow tests both disabled and enabled Dart defines, then checks the actually emitted provider expressions with `TestRealityMlkemProviderDefaults`. That Go contract test uses `REALITY_MLKEM_FIXTURE_PATH` and skips outside the workflow when no Flutter-generated fixture is supplied. The enabled build artifact is named `flashco-personal-android-first-run-mlkem-<run_number>`.
- Independent XHTTP download REALITY settings and preserved classical fingerprints are outside this default. See [PRODUCT.md](../PRODUCT.md) for behavior and [history.md](../history.md) for verified results.

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

## Personal fallback configuration — 2026-11-05

- Commit `5b52ffcd` embeds `config/personal_fallback.json` through the shared `setup.dart` path used by both personal workflows. The change is published in [PR #13](https://github.com/Artypoul/Flashco/pull/13), targeting `main`. No manual workflow dispatch or new package is implied.
- A nullable `ProfileOverrides.fallback` is stored in the existing overrides JSON; schema 21 is unchanged. Pending defaults are staged only from the captured fresh-install decision, survive a failed initial download, and attach only to a newly created bundled profile.
- Standard setup overlays one native ordered fallback group while retaining DB-added rules and later manual selections. Provider-owned checks receive the same test parameters without changing subscription refresh intervals. The source subscription file is not rewritten.
- This is native ordered fallback with return to priority, not restoration of the removed Safe/custom failover. Core, native platform code, DNS and TUN are unchanged. Results and limits are recorded in history.md and память.md.

## Local settings and installer work — 2026-11-05

- Settings commit `d6a45807` and installer commit `ee85b68d` are published on `codex/preserve-personal-settings-installer` in [PR #13](https://github.com/Artypoul/Flashco/pull/13), based on documentation merge `46bbe44f` (PR #12).
  Personal defaults now require the fresh-install decision captured before settings migration; existing preferences without the personal marker are preserved.
- Windows packaging detects the current Flashco AppId across machine registry views and the current user. Same-scope/mode replacement reuses its registered path; downgrade needs confirmation (silent: `/ALLOWDOWNGRADE=1`). Conflicting or unknown registrations stop replacement.
- Helper cleanup holds a service handle across ownership checks and SCM commands, then closes it before bounded deletion/process polling. It does not require the installed Helper binary.
- `personal-windows.yaml` runs the compiled Inno behavioral harness from [commands.md](commands.md). The saved pre-rollback installer stash remains intact; selected changes were copied into this work rather than consuming it.
- Current validation and remaining runtime limits are recorded in [history.md](../history.md) and [память.md](../память.md). No new application package or installation is implied by the local harness.

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
