# Validation

## Chords, doubles, profiles and window controls — 2026-09-17

Implemented all **21 side-modified held chords** and exactly **four double-click entries**, with descriptor-based selection, recording, editor, settings and runtime handling. The shared **Input window** defaults to 200 ms and accepts 0–1000 ms; zero disables doubles. Held supersets can replace pending subsets or run additively after they have fired. Doubles are exclusive, require intervening UP and continuously held exact side input, and use a strict first-DOWN to second-DOWN deadline. Expired candidates never pair with a later click. Passthrough primaries also interrupt recognition without changing their native DOWN/UP ownership.

Named profiles have independent saved mappings and in-memory drafts; switching cancels old pending generations, queued work, keyboard holds and drag state while preserving mouse release ownership. The optional cycle shortcut starts unset, changes transactionally, debounces held physical input, and uses stable displayed order with wrap. Hotkey profile changes use nonactivating editor presentation. Legacy settings migrate into Default; new features use versions 3–6 as needed so older builds reject unsupported actions. All settings replacements remain atomic. Invalid configuration stays paused without rewriting the original file.

Move/resize uses a reusable click-through, nonactivating overlay displaying **intended geometry**, independent of a slow target's observed rectangle. Native fixture/mocked tests cover this lag explicitly. White with 60% transparency is the default; the appearance editor includes a [full native color picker](https://learn.microsoft.com/en-us/windows/win32/api/commdlg/ns-commdlg-choosecolorw), transparency percentage/preview, and separate pin outline settings. Always on top is a discrete timed action with persistent window ownership, multiple pins, identity/property-lease validation, and color/thickness/visibility control. Existing external topmost states stay untouched. Profile changes do not unpin; exit attempts restoration only for owned pins. Failed runtime cleanup is retained for retry.

Finite smaller macros finish before queued larger actions. A queued hold/drag no longer discards subsequent finite actions, and Escape stays eligible while a queue remains. Resource cleanup attempts keyboard, drag, pin, hotkey and UI cleanup independently so one failure cannot prevent the others. The existing held-key SendEvent level-1 path and mapper InputLevel-1 guards remain unchanged.

Focused checks passed on AutoHotkey 2.0.26, with no warnings in the reported runs:

| Check | Passed assertions | Evidence |
| --- | ---: | --- |
| Integrated runtime/editor/profile/native-action handlers | 229 | Hidden real controls, deterministic clock, disposable settings, mocked output; includes finite queue, appearance validation and profile transitions |
| All 25 editor/view selections | 382 | Hidden controls; exact list rows, save/reopen/drafts, unsupported both-side doubles rejected |
| Recorder handlers | 314 | Hidden controls; all 21 held sets and four timed doubles, suppression, no configuration writes or output |
| Gesture arbitration | 459 | 32 pure groups; shared deadlines, additive progression, doubles, held-key modes and discrete topmost actions |
| Recorder model | 2,626 | 12 pure groups; order/overlap, strict double boundaries and original suppression regression coverage |
| Mapping and profile settings | 154 + 77 | Legacy migration, 25 descriptors, versions 1–6, independent profiles, delay and appearance fields |
| Held-key ownership and interop sender | 43 + 44 | Mocked shared-key cleanup, event level and restoration; no microphone operations |
| Profile-cycle service | 66 | Mocked registration, rollback, physical press debounce and synthetic-event rejection |
| Drag geometry/lifetime | 122 | Pure geometry plus native move/resize of one hidden process-owned fixture |
| Drag overlay | 40 | Desired preview advances while target lags; hidden native geometry, layering/style and lifecycle checks |
| Owned pins/outlines | 64 | Pure ownership/retry plus hidden native topmost/property/border checks; unchanged focus/geometry/DPI |

**No physical mouse, visible GUI, native global-hook, live shortcut-registration, or visible overlay/outline pass is claimed for this update.** The native fixtures were never shown and did not activate or manipulate user applications. Browser testing cannot verify this native AHK UI. Live mappings, running mapper/microphone utilities, unsaved drafts, PowerToys settings, actual audio and desktop input were not changed. The full legacy exhaustive core/hook matrices were not rerun; `HookTests.ahk` only received the required fixture dependency list update.

To activate: save wanted drafts in every profile, release held inputs, choose **Exit mapper**, then relaunch **Launch Mouse Macro Mapper.cmd**. Closing with X or starting a second copy does not reload the live instance. User-operated verification of the physical mouse, chosen apps, profile shortcut and visible appearance remains necessary before relying on them.

The sections below record earlier stages and do not extend their physical/hook evidence to this update.

## Native mouse-only window actions — 2026-09-17

Added **Action: Move window / Resize window** to each mapping editor. Button 5 + Left and Button 5 + Right can provide mouse-only window control directly, without activating PowerToys. The actions retain inactive macro text and timing/hold settings, use version-2 settings when needed, and preserve existing keyboard-only defaults. Live mappings and the running mapper have not been changed; save wanted drafts, exit, relaunch, then select and save the new actions.

The runtime requires side button(s) before the primary click and targets the active restored window under the pointer. First constituent release ends the drag; Escape, pause, focus change, editing, recording, hiding, and exit cancel it. Original primary-up ownership and side replay rules remain intact. Resize anchors the opposite corner and uses a bounded minimum-size query. Native calls use physical coordinates, preserve focus/z-order, and reject unsupported targets. Scoped Critical sections and session identity checks prevent cancelled work from applying stale geometry; move-only positioning preserves independently changed window size.

Focused checks passed on AutoHotkey 2.0.26:

- **100 hidden runtime/editor assertions:** actual application handlers, disposable settings and mocked output/geometry. Includes native-action draft/options preservation, save/reload, invalid inactive macro retention, restored macro validation, move/resize dispatch, first-side/primary release, duplicate down, primary-first rejection, exact-mask cancellation, and Escape/pause/focus/record/editor cleanup. Existing keyboard and standalone-side checks are included.
- **93 model/settings assertions** and **149 gesture-lifetime assertions:** native action assignment, backward loading, version selection, keyboard option preservation, paired window action lifetime, and existing keyboard behavior.
- **122 drag-engine assertions across 8 groups:** signed move coordinates, nearest-corner resize/minimum size, token lifecycle, target rejection/identity errors, reentrant cancellation and replacement, move-only size preservation, and actual native move/resize of one hidden process-owned fixture. The native check verifies unchanged visibility/foreground, restored DPI context, and `SWP_NOSIZE` behavior; it does not touch user windows.
- **144 existing editor/view assertions** and **24 recorder smoke assertions** passed with hidden controls.

No visible application window or physical mouse/hook test was performed. No input was injected; user windows, live settings/drafts/processes, PowerToys configuration, microphone utility, and audio state were left alone. Browser testing does not exercise this native AHK application; hidden native controls and real handler tests were used instead. Physical-button behavior and compatibility with the user's intended applications remain unverified.

## Standalone modifiers and PowerToys diagnosis — 2026-09-17

Added standalone `key Win` (left Windows key), `Alt`, `Ctrl`/`Control`, `Shift`, and explicit left/right modifier aliases. `Win+Left` retains Windows + Left Arrow semantics; mouse commands remain unsupported. Saved mappings and schema are unchanged. Missing-key feedback now distinguishes keyboard commands from unsupported mouse/raw-Send input.

Focused checks passed: **60 model/settings assertions**, **53 hidden binding runtime/editor assertions**, and **24 recorder assertions**. New runtime coverage verifies one Windows-key DOWN, matching UP on first side release, preserved primary mouse suppression, and complete release cleanup. Existing level-1 held-key interoperability output remains unchanged. No live input was injected, and no live mappings, drafts, mapper process, PowerToys configuration, or microphone/audio state were changed.

Read-only file-version inspection found installed PowerToys **0.100.2.0**. Its matching official source rejects injected keyboard events in [KeyboardProc](https://github.com/microsoft/PowerToys/blob/v0.100.2/src/modules/GrabAndMove/GrabAndMove/main.cpp#L710-L718) and injected mouse events in [MouseProc](https://github.com/microsoft/PowerToys/blob/v0.100.2/src/modules/GrabAndMove/GrabAndMove/main.cpp#L930-L938). Consequently, adding simulated Win-plus-mouse output would not activate Grab And Move in that version. No forwarding feature was retained, and no PowerToys runtime compatibility is claimed. The native move/resize alternative remains a separate user choice. The standalone-modifier addition requires saving drafts, exiting the mapper and relaunching it.

## Earlier validation — 2026-09-14

## Per-mapping press/release timing and held keys

Implemented backward-compatible per-mapping `Timing=Press|Release` and `Hold=0|1`. Completion can occur on either a primary or side DOWN. Release actions and holds end on the first constituent UP. Exact-mask latches prevent release fallback; an added side cancels the previous pending release/hold and evaluates the new exact mask. Mouse interception ownership remains in ChordState. Held keyboard output uses canonical keys with reference counts, physical-key checks, reverse release order, and retryable failed-UP cleanup. Hold accepts one key/shortcut command and retains the disabled timing choice; invalid bodies are rejected.

Focused checks passed on AutoHotkey 2.0.26:

- **50 runtime/editor assertions**, exit 0: actual application handlers with hidden native controls, isolated configuration and mocked output. Covers press and release completion in either order, first-side and first-primary release, duplicate downs, original native mouse-UP ownership, exact-mask cancellation, no smaller release fallback, overlapping shared-key holds, reverse key release, one-shot/hold exclusion, Escape and pending-release cancellation, pause/resume, focus cancellation, editor entry, recording guards, failed-UP retry, exit cleanup, standalone side replay, and option/draft/save validation. Report: `tests/artifacts/binding-runtime-latest.log`.
- **Mapping model/config:** 40 focused assertions passed, including old defaults, new settings roundtrip and invalid Hold rejection.
- **Binding lifetime model:** 8 groups / 96 focused assertions passed.
- **Held-key ownership:** 7 groups / 43 focused mocked assertions passed, including sharing, physical conflicts and failed-output cleanup.
- **Existing modified paths:** 144 hidden editor/view assertions passed. Recorder smoke passed 24 assertions; the suppression-only regression group passed 21 assertions.

No live mouse/keyboard injection or coordinated desktop pass was performed for these new behaviors. Physical key/driver behavior and actual Windows hook interception remain unverified; earlier hook results below do not validate this update. Existing live configuration, unsaved drafts, running mapper and microphone utility were not modified. To load the update, save wanted drafts, exit the running mapper, then relaunch the existing launcher.

Explicit limits: holds support a single key/shortcut, excluding punctuation/symbol keys; one-shot macros are skipped while any hold is active, and starting a hold cancels a running one-shot. The destination may autorepeat a held key. Already-fired press output cannot be recalled when an extra side changes the combination. Failed key-up delivery is retried while running; shutdown performs best-effort release, and forced process termination or OS/input failures cannot guarantee cleanup.

## Focused recorder suppression correction

Reproduced `Arming swallows every fresh primary down` using only the existing suppression group (`tests/RecordModelTests.ahk --suppression-only`): exit 1, failure at assertion 6. This was a production defect, not a stale expectation. The saved model allowed fresh no-side clicks through during Arming and Listening, contrary to the documented recorder behavior. Removed that extra condition. The runtime still exempts a plain left click on its own Cancel control, and already-held presses retain their original release ownership.

After correction, the focused model group passed **21 assertions**, and the existing hidden recorder smoke passed **24 assertions**, both exit 0. Two smoke assertions specifically check fresh no-side click suppression in Listening and Arming, including passthrough ownership of the already-held launch click. No broad suite, physical input, or desktop test was run. Current mappings/configuration, drafts, running processes, desktop input, microphones, and the separate microphone utility were not accessed or changed. The running mapper needs a user-controlled save/exit/relaunch to load this correction.

## Record combination update — lighter verification

**22 smoke assertions passed** with AutoHotkey 2.0.26, exit 0. The updated application parsed and constructed its real native controls in hidden test mode. The small test called actual recorder/input/editor handlers using isolated settings and output spies, with no input or focus hooks, global synthetic input, or visible windows. It checked the Record button in both views, both-side Middle while paused with an assigned macro, deferred editor opening until all releases, retained draft, unchanged settings file, stopped macro, no macro dispatch/side replay, Escape cancellation while held, release cleanup, restored ordinary-click eligibility, existing launch-click ownership, 15-second timeout, and hide cancellation. Report: `tests/artifacts/record-smoke-latest.log`.

Per the user's request to finish sooner, the recorder did **not** receive a broad regression rerun, exhaustive integration matrix, physical-mouse test, or desktop GUI/input-hook pass. Real button hit testing and hook suppression for this new feature remain unverified at the OS/physical-input level. A preliminary independent pure-model run occurred before the final suppression change; it is not claimed as validation of the completed integration. Existing saved mappings, the user's running mapper, and live editor drafts were not accessed or changed during this update. Loading the feature requires the user to save wanted drafts, exit the old mapper, and relaunch it.

Everything below describes the **earlier build before Record combination**. Those test results and process/settings snapshots are historical and are not claims about the current running instance or current settings.

Tested with installed AutoHotkey **2.0.26 (64-bit)** on Windows. Existing `date-time.ahk` and `MonitorWindowSwapper.ahk` processes were left running and unchanged.

## Programmatic checks

- **Core:** 15 groups, **20,656 assertions**, exit 0, no warnings. Gesture masks, release ownership and cancellation, 90 event orderings, parser limits, all nine persisted slots, Unicode and maximum-length settings, malformed settings, failed writes, old configuration compatibility, and saved view/selection. See `tests/CoreTests-report.md`.
- **Native editor handlers:** **144 assertions**, exit 0. The real `MouseMapper` and GDI+ diagram are instantiated with hidden windows, isolated configuration, and no hotkeys, input/focus hooks, or synthetic input. Tests cover all nine diagram selections, precise hit regions, both views, shared selection, an open unsaved draft across view changes, draft recovery across combination changes, save/reopen, invalid edits, cancel, clear, accessible checkbox equivalents, and persisted pause/preservation. Run `MouseMacroMapper.ahk --ui-test`; report: `tests/artifacts/ui-latest.log`.
- **Drawing resources:** all five region centers and empty space checked; 90 selection redraws kept GDI resource counts stable. Disposal released the owned resources.

## Actual Windows hook checks (simulated input)

The integration harness launched an isolated copy of the application and its own disposable receiver windows, then injected Win32 mouse events and AHK keyboard events. It observed the real messages arriving at the receiver; it did not merely call gesture handlers.

**12 groups and 256 assertions passed**, including all nine production mappings across **36** side press/release/early-release cases. Normal clicks, native mouse-capture dragging, wheel input, repeated triggers, exact unassigned-mask behavior, preservation toggle persistence, pause/resume with a held side, and delayed focus/Escape/pause cancellation passed. Report: `tests/artifacts/hook-report-26576-72690968.log`.

**Seven XButton2 standalone/paused receiver checks remain unavailable.** Before the mapper was launched, XButton2 events failed to reach the receiver with both AHK SendEvent and explicit Win32 mouse_event injection. XButton1 and ordinary buttons reached it. This indicates an environment/input-path limitation; the specific outside component was not identified or changed. All mapped combinations using XButton2 did pass. This result does not establish button 5's standalone replay compatibility on this PC.

This hook run preceded the visual redesign. The gesture and macro execution paths were retained; the redesign was checked using the native handler tests above to avoid repeating global input while the user was using the desktop.

## Computer Use checks

The actual native GUI was exercised during development: edit/validate/save, settings after restart, preservation toggle, resume, Ctrl+Alt+F12 pause, exit, all five mouse graphic regions, side deselection/reselection, three button-4 combinations, three button-5 combinations, and both-side Left/Right selections. The correct editor titles and corresponding graphical highlights were observed.

The final coordinated seven-action Computer Use pass also **passed**: the both-side Middle region opened its exact editor; a comment-only draft survived Mouse -> List -> Mouse with the same selection; Save and reopen retained the draft; Cancel closed the editor. This completes manual selection coverage for all nine combinations. No macro or additional global input-injection suite was run during this pass.

The observed final UI was saved locally in `screenshots/mouse-view.jpg`. This capture includes unrelated desktop/voice UI and is excluded from the repository.

After capture, task-owned mapper PID 58268 was stopped. No test helpers or pending Computer Use calls remained. Only the exact disposable test comment was removed from settings after shutdown; all nine mappings are empty, preservation is enabled, and `Paused=1` is retained. The unrelated AutoHotkey scripts remain running and unchanged. No task-owned desktop input is continuing.

## Limits

No physical mouse hardware verification is claimed. App-handler assertions, injected OS input tests, and actual GUI interactions are distinct evidence. Games, elevated/protected applications, vendor remapping, and unusually fast focus/recipient races remain application-specific compatibility limits. Keyboard input is global synthetic input with focus checks, not delivery atomically bound to a window. No startup entry or network service was added.
