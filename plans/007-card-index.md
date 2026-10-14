# Add the planned quick card index to native decks

Planned at `9423e08` on 2026-10-13. Status: RELEASED for independent Athkar work on 2026-10-14; the user superseded the full-settlement hold.
Executor: Claude Opus 5.5 xhigh on Mars. Independent final reviewer: task 010, from the other model family.
Dependencies: 010 testing target; design packet review by task 005.

## Current state

NATIVE_APP_PLAN.md section 3.3 lists Quick card index for 1.0. DeckView.navigation currently renders deck.position as a Text; it has previous/next only. The existing DeckModel.show method supports selecting any card.

## Goal

The position control opens an Arabic RTL list of this deck's cards. A reader can see every card and select one reachable through the existing previous/next rules, without changing its count or target. The list tracks actual long-order deck ordering and original item numbers. Normal forward-lock and auto-advance behavior remains intact after selection.

## Scope

ios/Athkar/Deck/DeckView.swift; new ios/Athkar/Deck/DeckIndexView.swift if useful; new ios/AthkarUITests/DeckIndexUITests.swift; DeckModel.swift reachability predicate and portable regressions; DeckCardView.swift rendering seam only; UITestSupport.swift position-button lookup only.

Do not edit religious text, content pack versions, PWA behavior, golden fixtures, Apple identity/authentication, or features gated after Slice 4. This task fixes existing implementation or its approved deck workflow. No App Store Connect, TestFlight, bundle ID reservation, authentication migration or new fleet credentials.

## Steps

Design contract: spec/sessions/deck-definition.md §4 is authoritative. Turn the existing centered position into a 44-point button with a VoiceOver hint. Present a native sheet with navigation title `فهرس الورد` for adhkar or `فهرس الرقية`, a Close button, and rows with original number, existing opening text or surah/range, current-row marker and completion status. Reuse palette and fonts. No search/favorites/new content. Cancel any pending advance before selection. Keep unreachable forward cards visible but disabled: a later index is selectable only when canMoveForward holds for every intervening position. Earlier/current rows remain selectable; manual completion unlocks the adhkar deck and ruqyah retains free navigation. Cancel advance when opening the sheet, navigate by selected card ID after dismissal, and recheck reachability/day rollover before selection. Update deck.position tests to find the new button; reuse the existing Quran rendering through a narrow visibility seam. Ask task 005 for read-only design conformance review before implementation, then verify against this contract.

Before editing, read AGENTS.md, NATIVE_APP_PLAN.md and the relevant existing tests. Compare the scoped files against the planned commit. If scope must expand, report the exact reason to the coordinator before editing overlapping files. Use the smallest necessary seams; avoid broad refactors and dependencies.

## Verification

Run portable production-source reachability XCTest on Linux and compile the real UI against the existing iOS SDK. AthkarUITests/DeckIndexUITests requires an authorized iOS runtime result and stays open when unrun. Cover morning/evening/ruqyah, changed long-order, manual completion, selecting during pending advance, RTL accessibility, reduced motion, long titles, disabled locked rows, rollover while the sheet is open, largest text sizes and dark mode. Existing Deck regression tests and a screenshot for UI review also require an iOS runtime result. List the required unrun cases individually.

Run `git diff --check`. Content checks are `node tools/content-validate.mjs` and `node tools/content-export-pwa.mjs --check --ruqyah /home/t1nk33r/Projects/ruqyah-al-qareen/content.js` on Luna. Workers lacking the sibling checkout must state that and let the coordinator run the check. All new Swift/XCTest/SDK checks run on Linux under the coordinator queue, with /tmp/hikaya-build-suite.lock then /tmp/athkar-build-suite.lock acquired nonblocking and at most two jobs on Luna. Remote workers return source bundles. SDK compilation, executed portable tests and iOS runtime results are separate evidence; required unrun device cases remain open.

## Delivery

Use the assigned isolated worktree and branch. Commit source and tests after verification. Return a git bundle plus structured result with commit SHA, changed files, exact checks/results, skipped checks, owned processes and released locks. Do not push/merge, change main, remove worktrees or settle your own thread. The coordinator integrates serially after independent review. Do not update PROJECT_MAP.md or other tasks' plan files; coordinator owns those.

Stop and report if the selected model differs from the assigned family/effort, the predecessor gate is not released, a needed lane is busy, an out-of-scope product decision is required, or a shared resource has another owner. Never kill processes by name, stop shared daemons, shut down all simulators or remove another owner's lock. Preserve Eris on CPA and do not launch workers there or on Terra. Only stop PIDs/process groups started for this task.

## Done criteria

The stated goal is covered by meaningful regressions; relevant existing tests pass; no unintended product/content changes; all source committed in the assigned worktree; verification evidence matches the commit; no owned tests/dev servers/lane locks remain running. Final completion additionally requires the opposite-family review and serial merge by the coordinator.
