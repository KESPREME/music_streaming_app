# Contributing to Mine Music

Thank you for contributing. These guidelines exist to keep the app fast, legible, and honest — the same bar the codebase already holds itself to.

## Proposing contributions

- Substantial features, refactors, or UI redesigns should normally be discussed before implementation. Open an issue to outline the proposal — what changes, what stays, how it will be verified.
- Straightforward bug fixes, small documentation improvements, or minor corrections can be submitted directly as a pull request.

## Branch and pull request workflow

Check the repository for the current active branch before starting work. At present development lives on `refactor/liquid-glass` (see `CONTEXT.md`); `main`/`master` is the release branch.

When contributing:

- Fork the repository and create a descriptive branch (e.g. `fix/equalizer-compare-overflow`, `feat/pure-black-toggle`).
- Keep pull requests focused on a single change or bug fix. Do not mix unrelated refactors, cosmetic tweaks, or mass reformatting with functional changes.
- Keep the branch reasonably synchronised with the target base branch.
- Provide a clear PR description: what changed, why, and how it was validated.
- Include testing and validation details (analyzer output, relevant `flutter test` results, any device traces). Do not claim “tests pass” without running them.
- Address review feedback promptly and keep discussion on technical merits.

## Development setup

- **Flutter** 3.47.1 / **Dart** 3.13.1
- **Android SDK** · `compileSdk = 36`, `targetSdk = 36`, `minSdk = 24`
- **JDK** 17 (Eclipse Temurin recommended)
- **C/C++ NDK & CMake** if you touch native audio code

## Build and test commands

```bash
flutter pub get

# Static analysis — must be 0 errors. Today the baseline is 179 infos
# (budget 190 in CI). A rise means new code, not “the file grew”.
dart analyze

# Unit + widget tests
flutter test

# Debug APK
flutter build apk --debug

# Release APK (needs android/key.properties or CI secrets; see docs/RELEASING.md)
flutter build apk --release --build-name 1.1.0 --build-number 101
```

## Code quality

- Follow idiomatic Dart/Flutter conventions and the existing architecture (providers, services, presentation, design tokens, widgets).
- Keep diffs focused and minimal. Do not add a dependency because it is fashionable.
- Write or update tests for new logic and bug fixes. New failures are not acceptable; document any *pre-existing* failures you discover.
- Respect project invariants described in `CONTEXT.md` and `docs/PLAN-*.md` (e.g. no global cross-shelf dedupe, no artwork-based rejection, no `Random()` in ranking, no `gl` override, no `dart format` on `innertube_service.dart` / `home_screen.dart`).
- Do not commit running-computed files: `.dart_tool/`, `build/`, `android/build/`, `android/app/{debug,profile,release}/`, `.flutter-plugins*`, `*.log`, signing keys.

## Audio changes and telemetry

For audio or performance changes: telemetry is not proof of hardware behavior. Distinguish source metadata, decoder format, internal DSP format, `AudioTrack` output, HAL state, and the physical endpoint. If you did not measure on the device, say so.

## Review process

All pull requests require maintainer review before merging. Review checks for correctness, architecture fit, performance, and maintainability.

## Dependencies and licensing

Mine Music is licensed under the **GNU General Public License v3.0 (GPLv3)** — see `LICENSE`.

All contributed code and new dependencies must be compatible with GPLv3. Keep new dependencies lean and justified: smaller binary, fewer native surfaces, fewer permissions.
