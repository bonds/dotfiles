---
name: osaurus-build
description: "Build and test bonds/osaurus under Xcode 26.3 / Swift 6.2.4: Debug-only test builds, the vmlx region-isolation patch, type-checker traps, and the sandboxed test command. Use when working in ~/src/bonds/osaurus."
---

The repo's own AGENTS.md has repo-local proof rules; read it first.

## Osaurus repo (bonds/osaurus)

Local working copy: `~/src/bonds/osaurus` (a fork of OsaurusAI; origin is
`github.com/bonds/osaurus`). Work-in-progress goes on feature branches off
`main` (e.g. `scott/chat-window-clamp`), pushed to origin for PRs. The repo's
own `AGENTS.md` has repo-local proof/proof-reporting rules — read it first.

### Build & test reality (Xcode 26.3 / Swift 6.2.4)

The repo's last clean build under the current toolchain was July 2026; Swift
6.2.4 then surfaced a chain of strict-concurrency and type-checker failures
that blocked the whole package. All fixed on `scott/chat-window-clamp`, but
keep these in mind for any future work:

- **Run `swift test` in Debug, never `-c release`.** Test-only hooks
  (`makeContextForTesting`, `_setItemsForTesting`, `executeForTesting`,
  `forceChatEngineRouteForTests`, …) are `#if DEBUG`-gated; a Release test
  build strips them and fails the whole test target with "has no member".
- **vmlx `MLXLMCommon` still over-reports region-isolation on 6.2.4.** Its
  manifest forces `.v6` language mode when `compiler(>=6.2)` (it assumes 6.2
  fixed the over-report; it did not), producing `#SendingRisksDataRace` errors
  in `BatchEngine.swift`. Workaround: patch the vmlx checkout to `.v5` (the
  manifest's own 6.0/6.1 fallback). Scratch-checkout-only; must be re-applied
  after a clean checkout, or upstreamed as a pin bump / manifest change.
- **Type-checker timeouts ("unable to type-check this expression in reasonable
  time")** hit long chained string-concat and multi-source `Set(...)`/`flatMap`
  expressions (fixed in `AgentToolLoop.announcedToolCallNotice` and
  `MemoryContextAssembler`). Keep those expressions broken into small locals.
- **Don't send non-Sendable `self` across isolation.** `KnowledgeManager.init`
  loads the registry off-main via `Task.detached`; the pattern that satisfies
  6.2.4 is a nested `Task.detached` for the load + a MainActor hop with only
  the finished snapshot.
- Window-frame persistence note (the original fix): `setFrameUsingName`
  restores autosaved frames verbatim, so a frame saved on a large display can
  land partly off a smaller screen. `ChatWindowManager.constrainedFrame(_:to:)`
  clamps the restored frame into the visible frame; regression tests in
  `Packages/OsaurusCore/Tests/Chat/ChatWindowFrameClampingTests.swift`.

### Running tests in this sandboxed agent environment

SwiftPM's own `sandbox-exec` can't nest and clang's module-cache dir is
read-only in the sandbox, so the plain `make test` lane needs three flags:

```bash
cd ~/src/bonds/osaurus
OSAURUS_DISABLE_KEYCHAIN_FOR_TESTS=1 \
OSAURUS_TEST_ROOT=/tmp/osaurus-test \
OSU_MODELS_DIR=/tmp/osaurus-test-models \
swift test --package-path Packages/OsaurusCore --disable-sandbox \
  --scratch-path /tmp/osaurus-swiftpm \
  -Xcc -fmodules-cache-path=/tmp/osaurus-modcache \
  --filter ChatWindowFrameClampingTests
```

(Single-target filters like `--filter ChatWindowFrameClampingTests` keep the
run tractable; a bare full-suite run recompiles ~1140 test files.)
