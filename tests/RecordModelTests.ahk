#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include ../lib/ChordState.ahk
#Include ../lib/CombinationCapture.ahk

; Pure model tests: no input hooks, Send, windows, settings, timers, or focus changes.
global RecordingTestStats := {Checks: 0, Groups: 0, Failures: []}
RecordTest("idle and active primary suppression", TestRecordingSuppression)
if !(A_Args.Length && A_Args[1] = "--suppression-only") {
    RecordTest("all nine combinations, pause modes, both-side orders, and release orders", TestRecordingCombinations)
    RecordTest("arming preserves preexisting release ownership and requires a fresh click", TestRecordingArming)
    RecordTest("matched result remains fixed and completion is delivered once", TestRecordingFixedResult)
    RecordTest("cancellation drains every active phase without selection", TestRecordingCancellation)
    RecordTest("deadline boundary and matched timeout discard pending selection", TestRecordingTimeout)
    RecordTest("capture mask ignores pause but rejects unowned or stale sides", TestRecordingHeldMask)
    RecordTest("all 21 mappings and overlapping primary press orders", TestRecordingPrimarySets)
    RecordTest("primary-set upgrades require strict overlap and freeze on release", TestRecordingPrimarySetGuards)
    RecordTest("four double-click patterns preserve ownership and select after all releases", TestRecordingDoubles)
    RecordTest("double-click boundary uses first DOWN and requires first UP", TestRecordingDoubleTiming)
    RecordTest("double-click candidates reject side changes mixed input and disabled timing", TestRecordingDoubleGuards)
}

TestRecordingDoubles() {
    for , side in [4, 5] {
        for , button in ["LButton", "RButton"] {
            state := ChordState(), capture := CombinationCapture()
            mask := side = 4 ? 1 : 2
            capture.Begin(true, 100)
            state.SideDown(side, 111, true), state.UseSides()
            fresh := state.PrimaryDown(button, true)
            RecordCheck(capture.ObservePrimary(mask, button, fresh, state.Primary, 100, 200), "First click records singleton")
            RecordCheck(capture.ObserveUp(button), "First primary UP freezes chord growth")
            RecordCheck(state.PrimaryUp(button), "First primary UP retains blocked ownership")
            RecordEqual(capture.Advance(state.AllReleased(), 110), 0, "Held side preserves pending recording")
            fresh := state.PrimaryDown(button, true)
            RecordCheck(capture.ObservePrimary(mask, button, fresh, state.Primary, 299, 200), "Second DOWN before deadline records double")
            RecordEqual(capture.Result.Trigger, "D" SubStr(button, 1, 1), "Double trigger selected")
            RecordEqual(capture.Result.Button, button, "Double preserves legacy primary")
            RecordCheck(!IsObject(capture.DoubleCandidate), "Recognized double cannot seed third click")
            capture.ObserveUp(button)
            RecordCheck(state.PrimaryUp(button), "Second primary UP retains blocked ownership")
            fresh := state.PrimaryDown(button, true)
            RecordCheck(!capture.ObservePrimary(mask, button, fresh, state.Primary, 299, 200), "Third fresh click cannot rerecord")
            capture.ObserveUp(button), state.PrimaryUp(button)
            RecordEqual(capture.Advance(false, 300), 0, "Double result still waits for side release")
            capture.ObserveUp(side)
            RecordCheck(!state.SideUp(side, 111, true), "Double recording consumes standalone side action")
            result := capture.Advance(state.AllReleased(), 301)
            RecordEqual(result.Mask, mask, "Selected double side mask")
            RecordEqual(result.Trigger, "D" SubStr(button, 1, 1), "Selected double trigger survives drain")
            RecordEqual(capture.Advance(true, 302), 0, "Double selection delivered once")
        }
    }
}

RecordDoubleFixture(mask := 1, button := "LButton", delayMs := 200) {
    capture := CombinationCapture()
    primaryMap := Map("LButton", false, "RButton", false, "MButton", false)
    primaryMap[button] := true
    capture.Begin(true, 100)
    capture.ObservePrimary(mask, button, true, primaryMap, 100, delayMs)
    return {Capture: capture, Primary: primaryMap, Mask: mask, Button: button}
}

TestRecordingDoubleTiming() {
    for , secondDown in [299, 300, 301] {
        fixture := RecordDoubleFixture(), capture := fixture.Capture
        capture.ObserveUp("LButton")
        matched := capture.ObservePrimary(1, "LButton", true, fixture.Primary, secondDown, 200)
        RecordEqual(matched, secondDown < 300, "Second DOWN must be strictly before first-DOWN deadline")
        RecordEqual(capture.Result.Trigger, secondDown < 300 ? "DL" : "L", "Expired double preserves first singleton")
    }
    fixture := RecordDoubleFixture(), capture := fixture.Capture
    RecordCheck(!capture.ObservePrimary(1, "LButton", true, fixture.Primary, 120, 200), "Fresh flag alone cannot replace required first UP")
    RecordCheck(!capture.ObservePrimary(1, "LButton", false, fixture.Primary, 130, 200), "Duplicate DOWN never completes double")
    capture.ObserveUp("LButton")
    RecordCheck(!capture.ObservePrimary(1, "LButton", true, fixture.Primary, 310, 200), "A late first UP cannot reset down-to-down deadline")
    fixture := RecordDoubleFixture(), capture := fixture.Capture
    capture.ObserveUp("LButton")
    capture.Advance(false, 300)
    RecordCheck(!IsObject(capture.DoubleCandidate), "Timer deadline clears pending double eligibility")
    RecordCheck(!capture.ObservePrimary(1, "LButton", true, fixture.Primary, 301, 200), "Timer-expired candidate cannot revive")
}

TestRecordingDoubleGuards() {
    for , sideRelease in [4, 5, "XButton1", "XButton2"] {
        fixture := RecordDoubleFixture(), capture := fixture.Capture
        capture.ObserveUp("LButton")
        capture.ObserveUp(sideRelease)
        RecordCheck(!capture.ObservePrimary(1, "LButton", true, fixture.Primary, 150, 200), "Any side release invalidates continuous-side double")
        RecordEqual(capture.Result.Trigger, "L", "Side release preserves first singleton")
    }
    fixture := RecordDoubleFixture(), capture := fixture.Capture
    capture.ObserveUp("LButton")
    RecordCheck(!capture.ObservePrimary(3, "LButton", true, fixture.Primary, 150, 200), "Different exact side mask rejects double")
    RecordCheck(!capture.ObservePrimary(1, "LButton", true, fixture.Primary, 160, 200), "Returning to original mask cannot revive candidate")
    fixture := RecordDoubleFixture(), capture := fixture.Capture
    capture.ObserveUp("LButton")
    fixture.Primary["RButton"] := true
    RecordCheck(!capture.ObservePrimary(1, "RButton", true, fixture.Primary, 130, 200), "Mixed primary DOWN after first UP does not combine")
    fixture.Primary["RButton"] := false
    RecordCheck(!capture.ObservePrimary(1, "LButton", true, fixture.Primary, 150, 200), "Mixed input invalidates later same-primary double")
    fixture := RecordDoubleFixture(), capture := fixture.Capture
    fixture.Primary["RButton"] := true
    RecordCheck(capture.ObservePrimary(1, "RButton", true, fixture.Primary, 130, 200), "Held primaries still grow into chord")
    capture.ObserveUp("RButton"), capture.ObserveUp("LButton")
    fixture.Primary["RButton"] := false
    RecordCheck(!capture.ObservePrimary(1, "LButton", true, fixture.Primary, 150, 200), "A captured multi-primary chord cannot become double")
    RecordEqual(capture.Result.Trigger, "LR", "Matched multi-primary chord stays frozen")
    for , fixture in [RecordDoubleFixture(1, "LButton", 0), RecordDoubleFixture(3), RecordDoubleFixture(1, "MButton")] {
        fixture.Capture.ObserveUp(fixture.Button)
        RecordCheck(!fixture.Capture.ObservePrimary(fixture.Mask, fixture.Button, true, fixture.Primary, 150, 200),
            "Zero delay, both sides, or middle cannot seed double")
    }
    fixture := RecordDoubleFixture(), capture := fixture.Capture
    capture.ObserveUp("LButton")
    RecordCheck(!capture.ObservePrimary(1, "LButton", true, fixture.Primary, 150, 0), "Disabling delay also cancels pending candidate")
    capture.Cancel()
    RecordCheck(!IsObject(capture.DoubleCandidate), "Cancellation clears double state")
}

TestRecordingPrimarySets() {
    mappings := 0, orders := 0
    for , mask in [1, 2, 3] {
        for , trigger in ["L", "R", "M", "LR", "LM", "RM", "LRM"] {
            mappings += 1
            buttons := CombinationCapture().ButtonsForTrigger(trigger)
            for , order in RecordPermutations(buttons) {
                orders += 1
                state := ChordState(), capture := CombinationCapture()
                capture.Begin(true, 100)
                sides := mask = 1 ? [4] : mask = 2 ? [5] : [4, 5]
                for , side in sides
                    state.SideDown(side, 111, true)
                state.UseSides()
                for , button in order {
                    fresh := state.PrimaryDown(button, true)
                    RecordCheck(capture.ObservePrimary(mask, button, fresh, state.Primary), "Fresh overlapping primary records or upgrades")
                    expected := ""
                    for , primary in ["LButton", "RButton", "MButton"] {
                        if state.Primary[primary]
                            expected .= SubStr(primary, 1, 1)
                    }
                    RecordEqual(capture.Result.Trigger, expected, "Intermediate trigger uses canonical L R M order")
                    RecordCheck(!capture.ObservePrimary(mask, button, false, state.Primary), "Duplicate DOWN cannot upgrade again")
                }
                RecordEqual(capture.Result.Trigger, trigger, "Every primary order reaches requested set")
                RecordEqual(capture.Result.Button, order[1], "Legacy Button retains first primary")
                RecordEqual(capture.Advance(false, 101), 0, "Matched result waits for all releases")
                RecordCheck(capture.ObserveUp(order[1]), "First constituent UP freezes combination")
                for , button in order {
                    capture.ObserveUp(button)
                    RecordCheck(state.PrimaryUp(button), "Recorded primary UP remains blocked")
                }
                RecordEqual(capture.Advance(state.AllReleased(), 102), 0, "Held sides still defer selection")
                RecordEqual(capture.Result.Trigger, trigger, "Release never downgrades result")
                for , side in sides {
                    capture.ObserveUp(side)
                    RecordCheck(!state.SideUp(side, 111, true), "Recorded side never replays")
                }
                outcome := capture.Advance(state.AllReleased(), 103)
                RecordEqual(outcome.Mask, mask, "Selected exact side mask")
                RecordEqual(outcome.Trigger, trigger, "Selected complete primary set")
                RecordEqual(outcome.Button, order[1], "Selected legacy first primary")
                RecordEqual(capture.Advance(true, 104), 0, "Selection delivered once")
            }
        }
    }
    RecordEqual(mappings, 21, "All mapping sets covered")
    RecordEqual(orders, 45, "All primary press permutations covered")
}

TestRecordingPrimarySetGuards() {
    held := Map("LButton", true, "RButton", true, "MButton", false)
    allHeld := Map("LButton", true, "RButton", true, "MButton", true)
    for , mask in [1, 2, 3] {
        releases := mask = 1 ? ["LButton", "RButton", 4] : mask = 2 ? ["LButton", "RButton", 5] : ["LButton", "RButton", 4, 5]
        for , firstRelease in releases {
            capture := CombinationCapture()
            capture.Begin(true, 0)
            capture.ObservePrimary(mask, "LButton", true)
            capture.ObservePrimary(mask, "RButton", true, held)
            RecordCheck(capture.ObserveUp(firstRelease), "Any matched primary or side release freezes pair")
            RecordCheck(!capture.ObservePrimary(mask, "MButton", true, allHeld), "Repress after constituent release cannot upgrade")
            RecordEqual(capture.Result.Trigger, "LR", "Frozen pair remains unchanged")
        }
    }
    capture := CombinationCapture()
    capture.Begin(true, 0)
    capture.ObservePrimary(1, "LButton", true)
    noOverlap := Map("LButton", false, "RButton", true, "MButton", false)
    RecordCheck(!capture.ObservePrimary(1, "RButton", true, noOverlap), "Snapshot without first primary cannot upgrade")
    RecordCheck(!capture.ObservePrimary(1, "RButton", true), "Legacy call without held snapshot cannot upgrade")
    RecordCheck(!capture.ObservePrimary(2, "RButton", true, held), "Different side mask cannot replace tentative match")
    RecordCheck(!capture.ObserveUp("MButton"), "Unmatched primary release does not freeze")
    RecordCheck(!capture.ObserveUp(5), "Unmatched side release does not freeze")
    RecordCheck(capture.ObservePrimary(1, "RButton", true, held), "Still-overlapping exact candidate may upgrade")
    RecordCheck(capture.ObservePrimary(1, "MButton", true, allHeld), "Pair may grow into all three primaries")
    RecordEqual(capture.Result.Trigger, "LRM", "Three-primary upgrade uses canonical trigger")
    RecordCheck(!capture.ObservePrimary(1, "LButton", true, held), "Matched set cannot shrink or re-add its first button")
    RecordCheck(capture.ObserveUp("MButton"), "Newest matched primary freezes full result")
    capture.Begin(true, 10)
    RecordCheck(!capture.Frozen, "New recording clears previous release latch")
    capture.ObservePrimary(3, "LButton", true)
    RecordCheck(capture.ObservePrimary(3, "RButton", true, held), "Both-side combined primary recording is supported")
    RecordEqual(capture.Result.Trigger, "LR", "Both-side result retains combined trigger")
    capture.Begin(true, 20)
    capture.ObservePrimary(1, "MButton", true)
    RecordCheck(!capture.ObservePrimary(1, "RButton", true, held), "Upgrade cannot discard previously matched middle button")
}

FileAppend("Passed groups: " RecordingTestStats.Groups "`nAssertions: " RecordingTestStats.Checks "`n", "*")
for , failure in RecordingTestStats.Failures
    FileAppend("FAIL: " failure "`n", "*")
FileAppend(RecordingTestStats.Failures.Length ? "RESULT: FAIL`n" : "RESULT: PASS`n", "*")
ExitApp(RecordingTestStats.Failures.Length ? 1 : 0)

RecordTest(label, callback) {
    global RecordingTestStats
    try {
        callback.Call()
        RecordingTestStats.Groups += 1
        FileAppend("PASS: " label "`n", "*")
    } catch Error as err {
        RecordingTestStats.Failures.Push(label ": " err.Message " (" err.File ":" err.Line ")")
    }
}

RecordCheck(condition, message) {
    global RecordingTestStats
    RecordingTestStats.Checks += 1
    if !condition
        throw Error(message)
}

RecordEqual(actual, expected, message) {
    RecordCheck(actual == expected, message " | expected=[" expected "] actual=[" actual "]")
}

TestRecordingSuppression() {
    capture := CombinationCapture()
    RecordEqual(capture.Phase, "Idle", "Initial phase")
    RecordCheck(!capture.Active, "Idle recording is inactive")
    RecordCheck(!capture.ShouldBlockPrimary(false, false), "Idle plain click passes")
    RecordCheck(!capture.ShouldBlockPrimary(false, true), "Idle chord capture does not own input")
    RecordEqual(capture.Advance(true, 0), 0, "Idle emits no completion")
    for , phase in ["Arming", "Listening", "Matched", "Draining"] {
        capture.Phase := phase
        for , anySide in [false, true] {
            RecordCheck(capture.ShouldBlockPrimary(false, anySide), phase " swallows every fresh primary down")
            RecordCheck(!capture.ShouldBlockPrimary(true, anySide), phase " retains preexisting down ownership")
        }
    }
}

RecordPermutations(values, prefix := unset, output := unset) {
    if !IsSet(prefix)
        prefix := []
    if !IsSet(output)
        output := []
    if !values.Length {
        output.Push(prefix)
        return output
    }
    for index, value in values {
        remaining := values.Clone()
        remaining.RemoveAt(index)
        next := prefix.Clone()
        next.Push(value)
        RecordPermutations(remaining, next, output)
    }
    return output
}

TestRecordingCombinations() {
    cases := 0
    for , paused in [false, true] {
        for , mask in [1, 2, 3] {
            downOrders := mask = 1 ? [[4]] : mask = 2 ? [[5]] : [[4, 5], [5, 4]]
            for , sides in downOrders {
                for , button in ["LButton", "RButton", "MButton"] {
                    releases := sides.Clone()
                    releases.Push(button)
                    for , order in RecordPermutations(releases) {
                        cases += 1
                        state := ChordState()
                        state.Paused := paused
                        capture := CombinationCapture()
                        capture.Begin(state.AllReleased(), 1000)
                        for , id in sides {
                            state.SideDown(id, 111, true)
                            state.UseSides()
                        }
                        RecordEqual(CombinationCapture.HeldMask(state), mask, "Exact recording mask")
                        if paused
                            RecordEqual(state.Mask(111), 0, "Normal mapping mask remains paused")
                        fresh := state.PrimaryDown(button, capture.ShouldBlockPrimary(false, true))
                        RecordCheck(capture.ObservePrimary(CombinationCapture.HeldMask(state), button, fresh), "Fresh valid combination records")
                        RecordEqual(capture.Phase, "Matched", "Match waits for release")
                        RecordEqual(capture.Advance(false, 1001), 0, "Held buttons defer selection")
                        for index, release in order {
                            if IsNumber(release)
                                RecordCheck(!state.SideUp(release, 111, true), "Recorded side never replays standalone")
                            else
                                RecordCheck(state.PrimaryUp(release), "Recorded primary retains swallowed release")
                            outcome := capture.Advance(state.AllReleased(), 1001 + index)
                            if index < order.Length
                                RecordEqual(outcome, 0, "Intermediate release does not select")
                            else {
                                RecordEqual(outcome.Kind, "Selected", "Final release selects")
                                RecordEqual(outcome.Mask, mask, "Selection retains exact side mask")
                                RecordEqual(outcome.Button, button, "Selection retains exact primary")
                            }
                        }
                        RecordCheck(!capture.Active && state.AllReleased(), "Completed recording is idle and released")
                        RecordEqual(capture.Advance(true, 2000), 0, "Selection delivered only once")
                        RecordEqual(state.Paused, paused, "Recording does not change pause state")
                    }
                }
            }
        }
    }
    RecordEqual(cases, 96, "All combinations and release permutations covered")
}

TestRecordingArming() {
    state := ChordState()
    state.PrimaryDown("LButton", false)
    capture := CombinationCapture()
    capture.Begin(state.AllReleased(), 1000)
    RecordEqual(capture.Phase, "Arming", "Preexisting launch click delays listening")
    state.SideDown(4, 111, true)
    state.UseSides()
    RecordCheck(!capture.ObservePrimary(1, "LButton", true), "Arming cannot match")
    RecordEqual(capture.Advance(false, 1001), 0, "Arming waits for all releases")
    RecordCheck(!state.PrimaryUp("LButton"), "Preexisting passthrough primary up stays passthrough")
    RecordEqual(capture.Advance(state.AllReleased(), 1002), 0, "Side still held prevents listening")
    RecordEqual(capture.Phase, "Arming", "No premature listening")
    RecordCheck(!state.SideUp(4, 111, true), "Arming side is consumed")
    RecordEqual(capture.Advance(state.AllReleased(), 1003), 0, "All-up arms without selecting")
    RecordEqual(capture.Phase, "Listening", "Fresh gesture now accepted")

    RecordCheck(!capture.ObservePrimary(0, "LButton", true), "No-side click never records")
    RecordCheck(!capture.ObservePrimary(4, "LButton", true), "Unsupported mask never records")
    RecordCheck(!capture.ObservePrimary(1, "WheelUp", true), "Wheel cannot record")
    RecordCheck(!capture.ObservePrimary(1, "LButton", false), "Repeated down cannot record")
    state.PrimaryDown("RButton", true)
    state.SideDown(5, 111, true)
    duplicateFresh := state.PrimaryDown("RButton", true)
    RecordCheck(!capture.ObservePrimary(CombinationCapture.HeldMask(state), "RButton", duplicateFresh), "Side pressed after primary does not retroactively record")
    RecordCheck(state.PrimaryUp("RButton"), "Rejected plain click still drains swallowed up")
    fresh := state.PrimaryDown("RButton", true)
    RecordCheck(capture.ObservePrimary(CombinationCapture.HeldMask(state), "RButton", fresh), "Fresh click with held side records")
    RecordEqual(capture.Result.Mask, 2, "Fresh result reflects only side5")
}

TestRecordingFixedResult() {
    capture := CombinationCapture()
    capture.Begin(true, 100)
    RecordCheck(capture.ObservePrimary(3, "MButton", true), "Both-middle matched")
    RecordCheck(!capture.ObservePrimary(1, "LButton", true), "Later click cannot replace match")
    RecordCheck(!capture.ObservePrimary(2, "RButton", true), "Side release does not downgrade match")
    RecordEqual(capture.Result.Mask, 3, "Both mask stays frozen")
    RecordEqual(capture.Result.Button, "MButton", "Primary stays frozen")
    RecordEqual(capture.Advance(false, 500), 0, "Additional held button delays completion")
    outcome := capture.Advance(true, 501)
    RecordEqual(outcome.Kind, "Selected", "All-up produces selected outcome")
    RecordEqual(outcome.Mask, 3, "Both mask survives drain")
    RecordEqual(outcome.Button, "MButton", "Middle survives drain")
    RecordEqual(capture.Result, 0, "Consumed result is cleared")
    RecordEqual(capture.Advance(true, 502), 0, "No duplicate selection")
}

TestRecordingCancellation() {
    for , phase in ["Arming", "Listening", "Matched", "Draining"] {
        capture := CombinationCapture()
        capture.Begin(true, 1000)
        capture.Phase := phase
        capture.Result := {Mask: 3, Button: "LButton"}
        capture.Cancel("Focus changed.")
        RecordEqual(capture.Phase, "Draining", phase " cancellation drains")
        RecordEqual(capture.Result, 0, phase " cancellation clears pending result")
        RecordCheck(capture.Active, phase " remains active while input may be held")
        RecordEqual(capture.Advance(false, 1001), 0, phase " cannot finish before releases")
        outcome := capture.Advance(true, 1002)
        RecordEqual(outcome.Kind, "Cancelled", phase " never returns selection")
        RecordEqual(outcome.Reason, "Focus changed.", phase " retains cancellation reason")
        RecordCheck(!capture.Active, phase " cancellation ends idle")
        RecordEqual(capture.Advance(true, 1003), 0, phase " cancellation delivered once")
        capture.Begin(true, 1004)
        RecordEqual(capture.Result, 0, "Restart cannot revive cancelled result")
        RecordEqual(capture.Reason, "", "New recording clears old reason")
    }
    capture := CombinationCapture()
    capture.Cancel("Unrelated focus event")
    RecordCheck(!capture.Active, "Idle cancellation does not arm capture")
    RecordEqual(capture.Advance(true, 0), 0, "Idle cancellation produces no completion")
}

TestRecordingTimeout() {
    for , phase in ["Arming", "Listening", "Matched"] {
        capture := CombinationCapture()
        capture.Begin(true, 1000, 100)
        capture.Phase := phase
        if phase = "Matched"
            capture.Result := {Mask: 2, Button: "RButton"}
        RecordEqual(capture.Advance(false, 1099), 0, phase " remains active before deadline")
        RecordEqual(capture.Phase, phase, phase " does not time out early")
        RecordEqual(capture.Advance(false, 1100), 0, phase " timeout drains held input")
        RecordEqual(capture.Phase, "Draining", phase " times out exactly at deadline")
        RecordEqual(capture.Result, 0, phase " timeout clears match")
        outcome := capture.Advance(true, 1101)
        RecordEqual(outcome.Kind, "Cancelled", phase " timeout cannot select")
        RecordEqual(outcome.Reason, "Recording timed out.", phase " timeout reason")
    }
    capture := CombinationCapture()
    capture.Begin(true, 1000, 100)
    outcome := capture.Advance(true, 1100)
    RecordEqual(outcome.Kind, "Cancelled", "All-up listening times out immediately")
    capture.Begin(true, 2000, 100)
    capture.Cancel("Escape pressed.")
    outcome := capture.Advance(true, 3000)
    RecordEqual(outcome.Reason, "Escape pressed.", "Deadline does not overwrite an earlier explicit cancellation")
}

TestRecordingHeldMask() {
    for , paused in [false, true] {
        for , order in [[4, 5], [5, 4]] {
            state := ChordState()
            state.Paused := paused
            RecordEqual(CombinationCapture.HeldMask(state), 0, "Empty mask")
            state.SideDown(order[1], 111, true)
            RecordEqual(CombinationCapture.HeldMask(state), order[1] = 4 ? 1 : 2, "First side uses its own bit")
            state.SideDown(order[2], 111, true)
            RecordEqual(CombinationCapture.HeldMask(state), 3, "Both mask independent of press order and pause")
            state.Inhibited := true
            RecordEqual(CombinationCapture.HeldMask(state), 3, "Capture mask is independent of normal mapping inhibition")
            state.Sides[order[1]].Captured := false
            RecordEqual(CombinationCapture.HeldMask(state), 0, "Uncaptured side invalidates entire chord without fallback")
            state.Sides[order[1]].Captured := true
            state.Sides[order[2]].Epoch -= 1
            RecordEqual(CombinationCapture.HeldMask(state), 0, "Stale side invalidates entire chord without fallback")
            state.Sides[order[2]].Epoch := state.Epoch
            state.Cancel()
            RecordEqual(CombinationCapture.HeldMask(state), 0, "Cancelled generation cannot be reused")
        }
    }
}
