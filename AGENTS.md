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

## Agent Operating Protocol

At the start of a new session or substantial task:

1. Read this `AGENTS.md` completely.
2. Inspect the current branch, HEAD, recent commits, and `git status`.
3. Treat the local working tree as authoritative for uncommitted work.
4. Use Git history to understand prior intent before redesigning an existing subsystem.
5. Inspect relevant call sites before proposing a semantic hook.
6. Explain the architectural reasoning before making a significant change.

Do not assume the repository is in the same state as a previous conversation or
agent session. Verify current state from the repository.

When local files differ from GitHub, local files are authoritative for ongoing
work. Do not overwrite local work merely because the remote branch differs.

Known long-lived unrelated local modifications may exist in:

- `analysis_options.yaml`
- `pubspec.lock`

Always confirm current `git status`; preserve unrelated changes unless explicitly
asked to address them.

## Agent Autonomy & Learning Mode

This repository is being used to learn programming through a real project.

The preferred workflow is:

Understand -> Explain -> Make a small change -> Inspect -> Test -> Review

For meaningful architectural or semantic changes:

- explain what the relevant code currently does
- identify the exact semantic boundary being changed
- explain why the proposed hook or model belongs there
- keep the implementation small enough to review
- let the user see important diffs and test results
- prefer one coherent change over broad cleanup

Do not perform broad refactors, dependency changes, architecture rewrites, or
unrelated cleanup as side effects of a focused task.

Do not commit, push, restore, reset, rebase, delete branches, or rewrite history
unless explicitly requested or clearly authorized for the current task.

Never hide implementation work behind unexplained automation when the same task
can serve as a useful programming lesson.

## Campaign History Event Design Checklist

Before adding or changing a Campaign History event, determine:

- What factual state transition occurred?
- At what exact statement or branch does it become true?
- Is that point semantic, or merely a low-level mutation?
- Can the same mutation mean something different elsewhere?
- Does the event need its own type, or is the difference better represented as
  typed context such as cause, route, method, or reason?
- Could the referenced creature later leave `pool` or otherwise become
  unreachable?
- What minimum snapshot is required for the historical record to remain
  intelligible afterward?
- Can this event later be reversed?
- If reversible, what distinct reverse transition should exist?
- Does this event describe fact, interpretation, publicity, reputation, or
  presentation? Only factual state transitions belong in Campaign History.

Do not use player-facing text alone as evidence that an event occurred. Confirm
the actual state transition.

Prefer stable entity IDs plus enough snapshot data for later presentation.
Names are useful historical snapshots because live objects may later disappear
or change.

## Personnel Lifecycle Model

Treat a person's state as several independent dimensions rather than one status:

- identity
- affiliation
- operational role
- contact
- custody
- command relationship
- leadership office
- life status

Examples:

A founder can be dead and no longer be the current leader while remaining the
historical founder.

A sleeper can be an LCS member without being an active operative.

A person in hiding can remain affiliated with the LCS while temporarily losing
operational contact.

A person who permanently loses contact is different from a person who
voluntarily abandons the LCS.

A captured person is not necessarily convicted or imprisoned.

Do not derive permanent historical facts such as founder identity from mutable
organizational fields such as `hireId`.

## Implementation Inconsistencies

Existing gameplay may temporarily create contradictory mechanical state.

When implementation behavior conflicts with the semantic outcome presented by
the responsible gameplay branch:

- identify the inconsistency explicitly
- determine what outcome the game actually resolved
- record Campaign History at the semantic resolver
- do not log contradictory events merely because lower-level mutations occurred
- do not fix the underlying gameplay bug unless that fix is separately scoped

Campaign History should record the resolved semantic outcome of gameplay, not
every transient implementation artifact.

## Persistence & Compatibility

Campaign History is persisted game data.

Stable event wire names are part of the save format.

When evolving event types:

- preserve deserialization of previously written event names
- do not rename or remove an existing wire name casually
- legacy event types may remain solely for compatibility
- new gameplay may migrate to a newer generalized event type while old saves
  continue to deserialize the legacy type
- add wire-name tests for new event types
- retain or add JSON/save round-trip coverage when persistence behavior changes

Avoid changing generated serialization files by hand.

## Change Validation Protocol

For a focused Campaign History change:

1. Format only the files intentionally touched when practical.
2. Run the relevant focused test if one exists.
3. Run the full `flutter test` suite before treating the slice as complete.
4. Inspect `git status --short`.
5. Inspect the exact diff.
6. Stage explicit intended paths only.
7. Run `git diff --cached --check`.
8. Inspect the staged diff before committing.

Do not use `git add .`.

A passing test suite establishes regression confidence; it does not by itself
prove the semantic hook is correct. Review the relevant gameplay path as well.

## Campaign History Project Direction

The current Campaign History work is a bounded graduation project for learning
and architecture development.

The intended progression is:

Gameplay factual events
-> persistent Campaign History
-> queryable history
-> player-facing Chronicle
-> later systems such as biography, memory, reputation, statistics, endings,
   and world history

Do not build all downstream systems while the factual event layer is still being
established.

Prefer finishing one coherent personnel lifecycle slice before expanding the
system horizontally.

The purpose is not to make the entire LCS codebase elegant. The purpose is to
build one reliable, understandable subsystem inside an existing complex game.

## Collaboration & Decision Authority

The user is the final authority on game design, architecture direction, scope, and
creative intent.

The agent should actively analyze, challenge, and red-team proposals when useful,
especially when a change introduces:

- ambiguous semantics
- unnecessary complexity
- duplicated concepts
- false distinctions
- dominant or fragile architecture
- save compatibility risk
- scope growth beyond the current slice

When disagreeing with a proposed direction, explain the evidence and tradeoff
clearly. Do not silently substitute a different design.

Distinguish:

- observed repository behavior
- inferred intent
- proposed interpretation
- recommended change

Do not present an inference as established repository fact.

## Task Modes & Modification Boundaries

Determine the requested mode before acting.

### Analysis mode

When asked to inspect, trace, explain, compare, review, investigate, or return
analysis only:

- read freely within the repository
- use Git history and search as needed
- do not modify files
- do not generate artifacts or notes unless explicitly requested
- do not stage, commit, or push

### Implementation mode

When explicitly asked to implement or edit:

- make the smallest coherent change that satisfies the task
- avoid opportunistic cleanup
- preserve unrelated working-tree changes
- explain important decisions
- inspect the resulting diff
- test the affected behavior

Implementation permission does not automatically grant permission to commit or
push.

### Git mode

Stage, commit, push, reset, restore, rebase, or otherwise alter repository
history only when the user explicitly requests or clearly authorizes that Git
operation.

## Evidence & Uncertainty

Source code and executed behavior take precedence over assumptions.

When determining what a gameplay path means:

1. inspect the semantic resolver or controlling branch
2. inspect important callers and downstream mutations
3. inspect tests where relevant
4. inspect Git history when it helps explain intent

If evidence is ambiguous, say so and identify what would resolve the ambiguity.

Do not invent a clean conceptual model merely because the implementation is
messy. First describe the implementation accurately, then propose a cleaner
model separately.

When terminology in code is misleading, preserve the distinction between the
code's name and the behavior it actually implements.

## Regression & Failure Handling

When a test, analyzer, build, or runtime check fails after a change:

- determine whether the failure was introduced by the current change
- do not modify unrelated code merely to make the suite green
- report pre-existing failures separately from introduced regressions
- inspect the relevant failure before attempting broad fixes
- prefer correcting the semantic or implementation error over weakening a test

Do not treat compilation or passing tests as proof that domain semantics are
correct.

## Bounded Slice Completion

A Campaign History implementation slice is complete when:

- the factual transition has a clearly identified semantic hook
- the event type and context model the intended distinction
- required historical identity/snapshot data survives later object mutation or
  removal
- stable wire-name behavior is covered when a new event type is introduced
- relevant serialization or persistence behavior remains compatible
- formatting succeeds
- relevant tests pass
- the full test suite passes unless a documented pre-existing failure exists
- the final diff contains only intended changes
- unrelated working-tree modifications remain untouched

Stop after the bounded slice is complete. Do not automatically proceed into the
next lifecycle event or downstream system.

## Repository Knowledge vs Durable Guidance

Keep this file focused on durable rules, architecture principles, and working
protocol.

Do not add transient information such as:

- the current HEAD SHA
- current test count
- temporary branch state
- the current list of implemented Campaign History events
- temporary debugging discoveries
- short-lived workarounds

Discover changing implementation state from source code and Git history at the
start of each session.

## Governance File

Treat `AGENTS.md` as user-maintained repository governance.

Do not modify, rewrite, reorganize, or automatically update this file unless the
user explicitly asks for changes to it. Do not include changes to `AGENTS.md` in
an unrelated implementation commit.

When a task is materially ambiguous and different reasonable interpretations
would produce meaningfully different architecture, semantics, destructive
actions, or scope, explain the ambiguity and ask before editing.

Routine implementation details that can be resolved safely from repository
evidence do not require unnecessary clarification.
