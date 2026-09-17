# Mouse Macro Mapper

A native Windows utility with **25 mappings per profile**: 21 held-button combinations and four double-click combinations. Assign keyboard macros, held keys/shortcuts, window move/resize, or Always on top. Requires **AutoHotkey v2** and works independently of PowerToys.

## Run and reload

Double-click **Launch Mouse Macro Mapper.cmd**. It uses AutoHotkey v2 from `C:\Program Files\AutoHotkey\v2`. Alternatively, run `MouseMacroMapper.ahk` with your installed v2 interpreter; v1 is incompatible.

```powershell
& "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe" '.\MouseMacroMapper.ahk'
```

Keep `lib` and `tests` beside the script. A second launch from the same folder leaves the existing mapper running; other AutoHotkey scripts are not replaced.

**To load an update:** save every draft you want to keep, choose **Exit mapper**, then launch again. The main window's **X** and **Hide to tray** keep the old instance running. Launching another copy does not reload it. Release held mouse buttons and keyboard keys before restarting.

New settings start paused, with one **Default** profile, empty mappings, preservation enabled, and a **200 ms Input window**. The profile-cycle shortcut starts unset.

## Choose, record, and edit a mapping

1. In **Mouse View**, select **Button 4**, **Button 5**, or both, then use the click dropdown. The drawing also selects side modifiers and opens its single-click regions. Its wheel region means **Middle click**, not scrolling. In **List View**, select a row and choose **Edit mapping...**, or double-click the row.
2. Give the mapping an optional label and choose **Action**: **Keyboard macro**, **Move window**, **Resize window**, or **Always on top**.
3. Enter keyboard commands when using a macro. Choose its timing/hold options, then **Validate** and **Save mapping**. The mouse drawing only edits mappings; it never executes them.
4. Set **Preserve unused side-button actions** and, if needed, **Input window (ms)** followed by **Apply wait**.
5. Click **Resume mappings**, focus the destination app, and put the pointer over it. For window dragging and double-click mappings, hold the side button(s) first.

| Side button(s) | Supported held primary sets | Double-click entries |
| --- | --- | --- |
| Button 4 (`XButton1`) | Left; Right; Middle; Left + Right; Left + Middle; Right + Middle; Left + Right + Middle | Double Left; Double Right |
| Button 5 (`XButton2`) | The same seven held sets | Double Left; Double Right |
| Buttons 4 + 5 | The same seven held sets | None |

The multi-primary sets require the primary buttons to **overlap while held**, in either press order. They are not sequential clicks. Bare primary combinations and side-only triggers are not included. Keyboard mappings can also complete when a side is pressed last; a primary down that already passed through keeps its normal native up.

**Record combination** is available in both views. Click it, release the launch click, hold the intended side button(s), then press and hold the primary set. To record a double, keep exactly one side held and click the same Left or Right button twice within the Input window. Release **all** buttons to open the matching editor. Recording captures only the trigger; choose its action or enter the macro yourself.

Recording works while paused and preserves that setting. It cancels pending output and suppresses fresh mouse clicks, except a plain left click on **Cancel recording**. Existing presses keep their original release ownership. **Esc**, timeout after 15 seconds, a foreground change, or hiding the mapper cancels recording; intercepted releases continue to be cleaned up. Keep the mapper focused during capture.

Drafts retain their label, action, source, timing, and Hold choice when switching views, combinations, or profiles. **Save mapping** saves only the current mapping. The editor's **Cancel**, X, or Esc discards its current draft. Other drafts remain in memory until saved, cancelled, their profile is removed, or the mapper exits. Main-view previews show saved mappings.

## Input window, timing, and overlapping combinations

**Input window (ms)** is a global integer from **0 to 1000**, default **200**. It controls both waiting for a configured larger held combination and recognizing doubles. **0** starts smaller held combinations immediately and disables double-click recognition without deleting their saved mappings.

For keyboard macros:

- **Press** runs once when the combination completes, subject to the larger-combination/double-click wait below.
- **Release** arms when every required button is held, then runs once on the **first release of any required button**, including a side. It does not wait for all releases.
- **Hold bound key / shortcut** sends key down when the binding starts and key up on the first required release. It requires exactly one `key` command, such as `key F8` or `key Ctrl+Shift+C`. Comments are allowed; text, delays, multiple commands, empty bodies, and punctuation/symbol holds are rejected. Hold disables Press/Release while retaining the stored choice.

For held-combination growth, a smaller combination waits only when a **larger configured combination with the same exact side set** contains it. Completing the larger combination during that wait replaces the pending smaller one. This works in stages: with 4 + Left, 4 + Left + Right, and 4 + Left + Right + Middle configured, adding Right can replace pending Left; adding Middle during the next wait can replace pending Left + Right.

Once the smaller action has started, adding another required primary can still trigger the larger mapping. Output already delivered is not undone. A finite smaller macro finishes before the larger action queued behind it. Queued holds or window drags start only if their buttons are still held. A started smaller keyboard Hold can coexist with a larger keyboard Hold; other larger action types end the smaller Hold. Shared held keys/modifiers stay down until the last owning Hold ends. Unrelated one-shot requests during a running macro or active Hold are skipped.

A quick release before a held-combination wait expires still delivers a pending **Press** action. A pending keyboard **Hold** delivers a balanced down/up pair. A pending **Move/Resize** gesture that has already been released is discarded, so a window does not begin moving afterward. An eligible double-click candidate is the exception: its first primary release continues waiting for the second click.

**Doubles are exclusive with their corresponding single click.** Only 4 + Double Left/Right and 5 + Double Left/Right are supported. Keep that one side continuously held, release the first primary click, then press the same primary again **strictly before** the Input window expires, measured from the **first down to the second down**. The deadline is not extended by the first up. Another primary or a changed/released side ends double eligibility. A recognized double runs its double mapping, not the pending single. If the deadline expires first, that first click resolves as a single; a later click cannot retroactively turn it into a double.

Releasing buttons never starts a smaller subset mapping. A fresh down is needed to complete another combination. A changed exact side set cancels pending work for the old set and evaluates the new one. Duplicate down notifications do not retrigger actions. An already-fired Press cannot be undone.

## Profiles

Use **Active profile** to select the mapping set. **New** creates an empty profile; **Duplicate** copies the active profile's **saved mappings only**, not unsaved drafts. Both select the new profile. **Rename** preserves its identity/order. **Remove** deletes the selected profile and its drafts after confirmation; the last profile cannot be removed. Names are trimmed, must contain 1–80 characters, and must be unique without regard to capitalization.

Each profile has its own 25 saved mappings and in-memory drafts. Switching profiles cancels current macros, waits, recording, holds, and dragging before the next profile becomes usable. Release held buttons before starting a new gesture. Pause, preservation, Input window, appearance, view, and the cycle shortcut are global.

To cycle profiles, type a keyboard shortcut such as **Ctrl+Alt+F10** in **Cycle shortcut** and choose **Apply shortcut**. This is typed text, not a key recorder. An empty field disables it. One physical press advances once through the stable profile order and wraps to the first; key autorepeat and mapper-generated input do not repeatedly cycle it. Escape and Ctrl+Alt+F12 are reserved. Renaming does not change the order. The active profile is saved and shown in the mapper title/tray tooltip.

## Native window actions and appearance

For an example, assign **Button 5 + Left → Move window** and **Button 5 + Right → Resize window**. Resume mappings, focus the target window, restore it if maximized, and hold **Button 5 first**, then the primary button while dragging inside that active window. Multi-primary window bindings require all their primary presses to be intercepted too. Release any required button to stop.

Move/resize acts directly through Windows; no Windows-key macro or PowerToys installation is needed. Resize uses the nearest starting corner, holds the opposite corner fixed, and respects the target's reported minimum size. Only one window drag runs at a time. Starting it ends keyboard playback/holds. Escape, pause, profile changes, focus changes, editing, recording, hiding, or exit stop it at the last requested position. Macro source and keyboard options remain stored but disabled for these actions.

The tinted drag overlay follows the **intended geometry immediately**, even if the target application takes longer to process the asynchronous move/resize. Its black label shows that preview's X/Y and W/H near the pointer. Both overlay windows are click-through and do not activate. The preview disappears when dragging ends or is cancelled.

**Always on top** is a discrete toggle: choose **Press** or **Release**, trigger once to pin the active target, then trigger again to unpin it. Keyboard text and Hold are retained but ignored for this action. Pins created by this mapper remain across profile switches and input cancellation. Normal **Exit mapper** restores the windows it pinned and removes their outlines. A window already topmost before the mapper claims it is left unchanged.

Choose **Window appearance** to change global presentation:

- **Tint: #...** opens the full Windows color picker. The transparency slider or percentage field accepts **0–100%**: 0 is opaque, 100 makes the tint invisible. The default white tint at **60% transparency** has **40% opacity**. Geometry text stays opaque and legible.
- **Outline windows pinned with Always on top** enables/disables persistent pin outlines. **Outline: #...** opens its color picker; **Thickness (px)** accepts **1–12**. Defaults are enabled, blue `#0078D4`, and 3 pixels.
- Choose **Save appearance** to apply and persist, or **Cancel** to discard changes. Hiding an outline does not unpin its window.

The target must be the active window under the pointer. Mapper windows, desktop/taskbar, hidden windows, and unsupported overlays are excluded. Move/resize requires a restored window; resizing also requires a resizable target. Elevated/protected applications can reject window-control calls.

## Keyboard commands and integration

```text
; Copy, wait, and paste
key Ctrl+C
delay 150
key Ctrl+V
```

```text
text Hello from my mouse!
key Enter
```

- `key F8` is one tap; `key Ctrl+Shift+S` is one shortcut. Prefix modifiers are `Ctrl`/`Control`, `Alt`, `Shift`, and `Win`.
- `key Win`, `key Alt`, `key Ctrl`, and `key Shift` are standalone left modifier keys. Explicit `LWin`/`RWin`, `LAlt`/`RAlt`, `LControl`/`RControl` (`LCtrl`/`RCtrl`), and `LShift`/`RShift` are supported. Enable Hold for a real held key/shortcut. `Left` and `Right` are **keyboard arrows**, never mouse buttons.
- Letters, digits, F1–F24, navigation/editing keys, numpad keys, and named media/volume/browser keys are supported. Examples: `Tab`, `PgUp`, `NumpadEnter`, `Volume_Up`, `Media_Play_Pause`, `Browser_Back`.
- One-shot punctuation uses names: `Plus`, `Minus`, `Equal`, `Comma`, `Period`, `Slash`, `Backslash`, `Semicolon`, `Quote`, `LeftBracket`, `RightBracket`, `Backtick`. For example, `key Ctrl+Plus`. Punctuation/symbol Holds are unsupported.
- Names/commands ignore capitalization. `key A` does not implicitly add Shift; use `key Shift+A` or `text A`.
- `delay 150` waits approximately 150 ms. Each delay is 0–60,000 ms, with at most five minutes total explicit delay. Windows scheduling affects timing.
- `text Hello` sends literal Unicode text. Braces and modifier symbols are literal; line-edge whitespace is trimmed. Use `key Enter`, `key Tab`, or `key Space` where needed.
- Blank lines and lines beginning with `;` are ignored; inline comments are unsupported. An empty/comment-only **Keyboard macro** unassigns the mapping. Window actions remain assigned even with empty retained macro text.

Each macro allows at most 200 steps, 16,000 source characters, and 1,000 characters per text step. Only `key`, `delay`, and `text` are accepted: no arbitrary code, raw Send syntax, explicit down/up commands, loops, or mouse-output steps. Ctrl+Alt+F12 is reserved.

**Other AutoHotkey utilities:** held shortcut output uses SendEvent at level 1. A receiving script must accept that event level and track injected key releases. Companion utilities are maintained separately and are not included in this repository.

**PowerToys Grab And Move:** `key Win+Left` is Windows + Left Arrow. Even standalone `key Win` cannot activate Grab And Move in PowerToys 0.100.2: its [keyboard hook ignores injected events](https://github.com/microsoft/PowerToys/blob/v0.100.2/src/modules/GrabAndMove/GrabAndMove/main.cpp#L710-L718), as does its [mouse hook](https://github.com/microsoft/PowerToys/blob/v0.100.2/src/modules/GrabAndMove/GrabAndMove/main.cpp#L930-L938). Use this mapper's native **Move window / Resize window** actions. PowerToys itself still uses its configured physical modifier and mouse drag; this utility does not change PowerToys settings.

## Mouse ownership, cancellation, and limits

Assigned gestures, including initial presses reserved for configured larger/double mappings, are intercepted through their matching releases. A primary down that already passed through retains its native up; completing a keyboard combination by pressing a side afterward does not take over that existing mouse drag. Other unassigned primary clicks pass through. Ordinary clicks, dragging, and wheel scrolling remain native when not reserved by a mapping or recording.

With **Preserve** enabled, an unused intercepted side press is replayed as one complete XButton1/XButton2 click on release. Used/cancelled gestures do not replay. With Preserve disabled, standalone sides are blocked while active. Replay checks foreground, the window under the pointer, and mouse capture. It restores ordinary side-click actions with release-time delay, not original press timing or hold-dependent behavior; sampled context checks can miss very brief changes.

**Ctrl+Alt+F12** or the pause button/tray item toggles pause. **Esc** cancels pending/running input, recording, holds, or a drag. Entering mapper windows, changing profiles/settings, editing/saving, or changing foreground cancels current output. These operations release mapper-held keyboard keys and retain ownership cleanup for already intercepted mouse presses. Release all held buttons before restarting a gesture. Pins are independent and remain until toggled off or normal exit.

Release physical Ctrl, Alt, Shift, and Windows keys before starting a keyboard action. Existing physical keys are not adopted as mapper-owned holds. One-shot output is skipped while a mapper Hold is active; a destination app may apply its own key autorepeat. Failed held-key releases are retained for retry while the mapper runs.

Keyboard output is global Windows synthetic input. Focus is checked before delivery and text is split into small batches, but focus can change between checking and sending; already delivered input cannot be recalled. Changing a focused control within one window is not a foreground change. Games, elevated/protected apps, remote sessions, and vendor mouse remapping can behave differently. Side buttons must reach Windows as XButton1/XButton2.

## Local settings and verification

`mappings.ini` beside the script stores profiles and global preferences; the folder must be writable. Save validates every profile before atomically replacing the file. Invalid settings load paused and are not overwritten. Exit, repair or rename the file, then restart to recover or create defaults. Back it up to preserve mappings. Macro text/profile names use reversible UTF-8 hexadecimal encoding, **not encryption**; do not store secrets in macros. Unsaved drafts are memory-only. There are no network operations or automatic Windows startup entries.

Legacy settings versions **1–3** load into the **Default** profile. The writer chooses the required compatible format: version 1 for original keyboard mappings, 2 for original native move/resize actions, 3 for assigned multi-primary chords, 4 for profiles/cycle settings, 5 for any assigned double-click mapping, and 6 for any **Always on top** action. The highest required version wins across every profile. Older builds reject unsupported versions instead of silently dropping actions or executing retained macro text.

The focused runner exercises hidden native editor handlers, isolated settings, and mocked output:

```powershell
& "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut '.\MouseMacroMapper.ahk' --binding-test 2>&1 | ForEach-Object { $_ }
```

`--record-test` and `--ui-test` are separate hidden checks. Reports go under `tests\artifacts`. Focused model suites include `BindingGestureTests.ahk`, `HeldKeyOutputTests.ahk`, `MappingOptionsTests.ahk`, `ProfileSettingsTests.ahk`, and `ProfileCycleHotkeyTests.ahk`. `WindowDragTests.ahk`, `WindowDragOverlayTests.ahk`, and `AlwaysOnTopTests.ahk` use mocks and explicitly owned hidden native fixtures; they do not control user windows.

**These additions have no claimed visible desktop or physical-device pass.** Hidden/model checks do not prove actual hook behavior, mouse-driver compatibility, visual appearance on every monitor, or recipient-app behavior. See [VALIDATION.md](VALIDATION.md) for the exact checks and limits. The older `HookTests.ahk` suite deliberately takes focus and injects input into disposable receivers; run it only during a coordinated desktop check, not alongside normal work or as proof of every new mapping.
