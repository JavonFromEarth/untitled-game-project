# Repository Guidelines

## Project Structure & Module Organization

Liberal Crime Squad: New Age is a Flutter/Dart game targeting browsers and desktop platforms. `lib/main.dart` is the entry point; gameplay modules live under `lib/`, including `basemode/`, `sitemode/`, `creature/`, and `politics/`. Shared engine code is in `lib/engine/`, game state in `lib/gamestate/`, and persistence in `lib/saveload/`.

`assets/` contains XML definitions, maps, flags, artwork, and the changelog; `fonts/` contains the console font. Tests live in `test/`, with historical saves in `test/saves/`. Platform wrappers are in `web/`, `windows/`, `linux/`, and `macos/`; build utilities are in `tool/`.

## Build, Test, and Development Commands

Run from the repository root:

- `flutter pub get`: install dependencies (Dart SDK requirement: `>=3.8.0 <4.0.0`).
- `dart run build_runner build`: generate JSON serialization code; rerun after save-model changes.
- `flutter run -d chrome`: launch locally; use `-d windows` with the Windows toolchain installed.
- `flutter analyze`: run configured static analysis and lint rules.
- `dart format lib test tool`: format Dart sources.
- `flutter test`: run the test suite.
- `flutter build web --source-maps --base-href /lcs-new-age/`: build for web hosting; adjust the base path as needed.
- `dart run tool/inject_service_worker.dart`: prepare the custom offline cache manifest after building web.
- `flutter build windows`: create a Windows release.

Gameplay does not fully support hot reload; restart when validating gameplay changes.

## Coding Style & Naming Conventions

Use two-space Dart indentation, `snake_case.dart` filenames, `UpperCamelCase` types, and `lowerCamelCase` members. Follow `analysis_options.yaml`, which extends Flutter lints and requires package imports, explicit return types, and typed public APIs. Generate rather than hand-edit `*.g.dart` files; these and build outputs are ignored by Git.

## Testing Guidelines

Use `flutter_test` and name tests `*_test.dart`. Game-data tests should await `ensureGameDataLoaded` from `test/test_support.dart` in `setUpAll`. Preserve historical save fixtures and cover serialization round trips when changing persistence. No numeric coverage threshold is configured.

For offline changes, install dependencies and Chromium in `tool/offline_test/` using `npm install` and `npx playwright install chromium`, then run `node test_offline.mjs` against the prepared web build.

## Commit & Pull Request Guidelines

Recent commits use short, imperative subjects such as “Log leadership succession events.” Follow that style. PRs should describe behavior changes, link relevant issues, and report validation performed. Include screenshots for visual changes and explain save compatibility implications for persistence changes.

## Campaign History Architecture

Campaign History is the authoritative factual record of events that actually
occurred during a campaign.

Use this conceptual pipeline:

Event -> Observation / Record -> Interpretation -> Memory / Reputation / History
-> Future Consequence

The factual event layer must not contain later interpretation, publicity,
reputation, or narrative framing. Those belong to downstream systems such as
news, chronicles, biographies, memories, reputation, statistics, and endings.

Log an event at the narrowest semantic point where the outcome becomes factually
true. Do not infer historical meaning from generic state mutations.

Important overloaded mechanisms that must not be used as generic history hooks:

- `Creature.die()` — sometimes represents literal death, but is also used for
  non-death departures such as renunciation or psychological abandonment.
- `pool.add()` / `pool.remove()` — can represent recruitment, kidnapping,
  burial, UI reordering, departure, corpse cleanup, and other unrelated actions.
- `sleeperAgent` — changes for voluntary activation, exposure, arrest, and other
  distinct outcomes.
- `hireId` — represents recruitment hierarchy, promotion, succession, and
  bookkeeping changes to dead leaders.

Prefer semantic call sites and resolvers over setters and helpers.

Preserve distinctions such as:

- capture vs conviction
- imprisonment vs disappearance
- hiding vs lost contact
- departure vs death
- renunciation vs death
- sleeper reporting in vs involuntary sleeper deactivation
- founder identity vs current leadership

Event type should describe the meaningful state transition. Typed event context
should describe the route, cause, or method.

## Development Approach

This repository is also a programming-learning project. Explain architecture and
reasoning before making significant changes. Prefer small, testable changes over
large autonomous rewrites.

Treat design claims as hypotheses until tested.

When modifying Campaign History:

- preserve compatibility with existing saved histories and stable wire names
- add or update tests for serialized event names and save round trips
- run `dart format` and `flutter test`
- avoid touching unrelated working-tree changes
- stage explicit paths; do not use `git add .`
- do not overwrite or restore unrelated local changes in
  `analysis_options.yaml` or `pubspec.lock`
