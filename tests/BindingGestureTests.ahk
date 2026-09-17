#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include ../lib/MacroModel.ahk
#Include ../lib/BindingGestures.ahk

; Focused, pure latch checks. No UI, hooks, Send, or settings access.
global BindingTestStats := {Checks: 0, Passed: 0, Failures: []}
BindingTest("Press runs with primary last or side last", CheckPressOrder)
BindingTest("Release fires once on the first constituent release", CheckReleaseOrder)
BindingTest("Exact-mask transitions cancel old release without smaller fallback", CheckExactMaskRelease)
BindingTest("Exact-mask transitions end old hold before beginning new hold", CheckExactMaskHold)
BindingTest("Duplicates and changed-button filtering retain explicit latches", CheckDuplicateAndCandidates)
BindingTest("Overlapping holds end independently", CheckOverlappingHolds)
BindingTest("Cancel ends only holds and preserves increasing tokens", CheckBindingCancel)
BindingTest("Timing and hold modes are captured at binding creation", CheckBindingSnapshots)
BindingTest("Window actions latch in either press order and ignore macro modes", CheckWindowOrderAndModes)
BindingTest("Exact-mask change ends the old window action first", CheckWindowExactMask)
BindingTest("Window actions end once on the first constituent release", CheckWindowRelease)
BindingTest("Window cancellation never taps and retains the action snapshot", CheckWindowCancel)
BindingTest("Assigned strict supersets delay starts only on the same side mask", CheckChordDelay)
BindingTest("A completed larger chord suppresses smaller actions inside the delay", CheckLargerWithinDelay)
BindingTest("Larger chords remain available after the smaller Press has fired", CheckLargerAfterPress)
BindingTest("Multistage chords replace pending actions through three primaries", CheckChordProgression)
BindingTest("Descriptor-based matching handles middle-button and both-side chords", CheckGeneralChordDescriptors)
BindingTest("Larger Release cancels the contained pending Release", CheckLargerRelease)
BindingTest("Quick delayed actions flush taps and balanced holds only", CheckQuickDelayedRelease)
BindingTest("Started smaller holds coexist only with larger keyboard holds", CheckStartedHoldProgression)
BindingTest("Cancellation and side-mask changes discard unopened starts", CheckDelayedCancellation)
BindingTest("Unwinding never starts subsets but fresh DOWN can complete again", CheckChordUnwind)
BindingTest("All four doubles replace both single clicks within the deadline", CheckDoubleRecognition)
BindingTest("Double recognition requires intervening UP and a strict deadline", CheckDoubleDeadline)
BindingTest("Expired released double candidates preserve single action semantics", CheckDoubleReleasedExpiry)
BindingTest("Expired held double candidates start Hold or arm Release correctly", CheckDoubleHeldExpiry)
BindingTest("Double-only mappings work and zero delay disables recognition", CheckDoubleAssignmentAndZeroDelay)
BindingTest("Double context breaks resolve or discard the first click safely", CheckDoubleContextBreaks)
BindingTest("Recognized doubles use their own Hold Release and Window lifetime", CheckDoubleOutputModes)
BindingTest("Always on top is a discrete timed action and ignores retained Hold", CheckToggleTiming)
BindingTest("Always on top observes chord delay quick release and cancellation", CheckToggleDelay)
BindingTest("Always on top participates in exclusive double recognition", CheckToggleDouble)

FileAppend("Passed groups: " BindingTestStats.Passed "`nAssertions: " BindingTestStats.Checks "`n", "*")
for , failure in BindingTestStats.Failures
    FileAppend("FAIL: " failure "`n", "*")
FileAppend(BindingTestStats.Failures.Length ? "RESULT: FAIL`n" : "RESULT: PASS`n", "*")
ExitApp(BindingTestStats.Failures.Length ? 1 : 0)

BindingTest(label, callback) {
    global BindingTestStats
    try {
        callback.Call()
        BindingTestStats.Passed += 1
        FileAppend("PASS: " label "`n", "*")
    } catch Error as err {
        BindingTestStats.Failures.Push(label ": " err.Message " (" err.File ":" err.Line ")")
    }
}

BindingCheck(condition, message) {
    global BindingTestStats
    BindingTestStats.Checks += 1
    if !condition
        throw Error(message)
}

BindingEqual(actual, expected, message) {
    BindingCheck(actual == expected, message " | expected=[" expected "] actual=[" actual "]")
}

EmptyBindings() {
    mappings := Map()
    for , id in MacroModel.IDs
        mappings[id] := {Steps: [], Timing: "Press", Hold: false}
    return mappings
}

BindingMapping(timing := "Press", hold := false) => {Steps: [{Kind: "key", Value: "{a}"}], Timing: timing, Hold: hold}

BindingPrimaries(left := false, right := false, middle := false) => Map("LButton", left, "RButton", right, "MButton", middle)

BindingAction(action, kind, id) {
    BindingEqual(action.Kind, kind, "Action kind for " id)
    BindingEqual(action.Binding.ID, id, "Action mapping identity")
}

CheckPressOrder() {
    mappings := EmptyBindings()
    ; Old mappings with no added fields must still behave as Press, not Hold.
    mappings["4L"] := {Steps: [{Kind: "key", Value: "{a}"}]}
    gestures := BindingGestures()
    actions := gestures.Down(1, BindingPrimaries(true), mappings, "LButton")
    BindingEqual(actions.Length, 1, "Primary-last Press emits one action")
    BindingAction(actions[1], "Tap", "4L")
    BindingEqual(actions[1].Binding.Button, "LButton", "Binding stores primary")
    BindingEqual(actions[1].Binding.Mask, 1, "Binding stores exact mask")
    BindingCheck(actions[1].Binding.Mapping = mappings["4L"], "Binding retains selected mapping")
    BindingEqual(gestures.Up("LButton").Length, 0, "Press does not repeat on release")
    BindingEqual(gestures.Active.Count, 0, "Press latch clears on release")
    actions := gestures.Down(1, BindingPrimaries(true), mappings)
    BindingEqual(actions.Length, 1, "Side-last Press considers held primary")
    BindingAction(actions[1], "Tap", "4L")
    BindingEqual(gestures.Up(4).Length, 0, "Side release does not repeat Press")
}

CheckReleaseOrder() {
    mappings := EmptyBindings()
    mappings["45M"] := BindingMapping("Release")
    for , firstRelease in ["MButton", 5] {
        gestures := BindingGestures()
        BindingEqual(gestures.Down(3, BindingPrimaries(false, false, true), mappings, "MButton").Length, 0, "Release timing is initially silent")
        BindingEqual(gestures.Active.Count, 1, "Pending Release is latched")
        actions := gestures.Up(firstRelease)
        BindingEqual(actions.Length, 1, "First constituent release emits exactly once")
        BindingAction(actions[1], "Tap", "45M")
        BindingEqual(gestures.Active.Count, 0, "First release removes latch")
        BindingEqual(gestures.Up("MButton").Length, 0, "Later/duplicate primary release is silent")
        BindingEqual(gestures.Up(4).Length, 0, "Later side4 release is silent")
        BindingEqual(gestures.Up(5).Length, 0, "Later/duplicate side5 release is silent")
    }
    gestures := BindingGestures()
    mappings["4L"] := BindingMapping("Release")
    gestures.Down(1, BindingPrimaries(true), mappings)
    BindingEqual(gestures.Up(5).Length, 0, "Unrelated side release leaves latch pending")
    BindingEqual(gestures.Active.Count, 1, "Unrelated release cannot remove binding")
    BindingAction(gestures.Up(4)[1], "Tap", "4L")
}

CheckExactMaskRelease() {
    mappings := EmptyBindings()
    mappings["4L"] := BindingMapping("Release")
    mappings["45L"] := BindingMapping("Release")
    gestures := BindingGestures()
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton")
    oldToken := gestures.Active["LButton"].Token
    BindingEqual(gestures.Down(3, BindingPrimaries(true), mappings).Length, 0, "Additional side cancels old pending release silently")
    BindingEqual(gestures.Active["LButton"].ID, "45L", "Larger exact binding replaces single-side binding")
    BindingCheck(gestures.Active["LButton"].Token > oldToken, "Replacement gets a new identity")
    actions := gestures.Up(5)
    BindingEqual(actions.Length, 1, "Only larger Release fires")
    BindingAction(actions[1], "Tap", "45L")
    BindingEqual(gestures.Active.Count, 0, "Side UP does not create a smaller binding")
    BindingEqual(gestures.Up("LButton").Length, 0, "Cancelled single-side Release never revives")

    mappings["45L"] := {Steps: []}
    gestures.Down(1, BindingPrimaries(true), mappings)
    BindingEqual(gestures.Down(3, BindingPrimaries(true), mappings).Length, 0, "Unassigned exact larger mapping cannot fall back")
    BindingEqual(gestures.Active.Count, 0, "Unassigned replacement still cancels old latch")
    BindingEqual(gestures.Up(4).Length, 0, "Cancelled pending release remains silent")
}

CheckExactMaskHold() {
    mappings := EmptyBindings()
    mappings["4L"] := BindingMapping("Release", true)
    mappings["45L"] := BindingMapping("Press", true)
    gestures := BindingGestures()
    BindingAction(gestures.Down(1, BindingPrimaries(true), mappings, "LButton")[1], "BeginHold", "4L")
    actions := gestures.Down(3, BindingPrimaries(true), mappings)
    BindingEqual(actions.Length, 2, "Larger chord ends and replaces hold")
    BindingAction(actions[1], "EndHold", "4L")
    BindingAction(actions[2], "BeginHold", "45L")
    BindingCheck(actions[1].Binding.Token != actions[2].Binding.Token, "Old/new holds have different identities")
    BindingAction(gestures.Up(4)[1], "EndHold", "45L")
    BindingEqual(gestures.Up("LButton").Length, 0, "Hold ends once")
    BindingEqual(gestures.Up(5).Length, 0, "No smaller hold starts on release")
}

CheckDuplicateAndCandidates() {
    mappings := EmptyBindings()
    mappings["4L"] := BindingMapping()
    mappings["4R"] := BindingMapping()
    gestures := BindingGestures()
    bothDown := BindingPrimaries(true, true)
    actions := gestures.Down(1, bothDown, mappings, "LButton")
    BindingEqual(actions.Length, 1, "Primary event considers only changed primary")
    BindingAction(actions[1], "Tap", "4L")
    token := gestures.Active["LButton"].Token
    BindingEqual(gestures.Down(1, bothDown, mappings, "LButton").Length, 0, "Duplicate down is silent")
    BindingEqual(gestures.Active["LButton"].Token, token, "Duplicate keeps binding identity")
    actions := gestures.Down(1, bothDown, mappings)
    BindingEqual(actions.Length, 1, "Side completion considers other held primary")
    BindingAction(actions[1], "Tap", "4R")
    BindingEqual(gestures.Down(1, bothDown, mappings).Length, 0, "Repeated completion cannot repeat actions")
    BindingEqual(gestures.Active.Count, 2, "Overlapping primary latches are retained")
    BindingEqual(gestures.Down(1, BindingPrimaries(true, true, true), mappings, "MButton").Length, 0, "Empty mapping does not latch or emit")
    BindingCheck(!gestures.Active.Has("MButton"), "Unassigned candidate remains absent")
}

CheckOverlappingHolds() {
    mappings := EmptyBindings()
    mappings["5L"] := BindingMapping("Press", true)
    mappings["5R"] := BindingMapping("Release", true)
    gestures := BindingGestures()
    first := gestures.Down(2, BindingPrimaries(true), mappings, "LButton")[1]
    second := gestures.Down(2, BindingPrimaries(true, true), mappings, "RButton")[1]
    BindingAction(first, "BeginHold", "5L")
    BindingAction(second, "BeginHold", "5R")
    BindingCheck(first.Binding.Token != second.Binding.Token, "Overlapping holds have distinct tokens")
    actions := gestures.Up("LButton")
    BindingEqual(actions.Length, 1, "Primary release ends only its own hold")
    BindingAction(actions[1], "EndHold", "5L")
    BindingCheck(gestures.Active.Has("RButton"), "Other primary hold remains active")
    actions := gestures.Up(5)
    BindingEqual(actions.Length, 1, "Shared side ends remaining hold")
    BindingAction(actions[1], "EndHold", "5R")
    BindingEqual(gestures.Active.Count, 0, "All holds released")
}

CheckBindingCancel() {
    mappings := EmptyBindings()
    mappings["4L"] := BindingMapping("Press")
    mappings["4R"] := BindingMapping("Release")
    mappings["4M"] := BindingMapping("Release", true)
    gestures := BindingGestures()
    gestures.Down(1, BindingPrimaries(true, true, true), mappings)
    lastToken := gestures.Sequence
    actions := gestures.Cancel()
    BindingEqual(actions.Length, 1, "Cancellation emits only held-key cleanup")
    BindingAction(actions[1], "EndHold", "4M")
    BindingEqual(gestures.Active.Count, 0, "Cancellation clears every latch")
    BindingEqual(gestures.Cancel().Length, 0, "Repeated cancellation emits nothing")
    BindingEqual(gestures.Up("RButton").Length, 0, "Cancelled Release action never fires")
    BindingEqual(gestures.Up(4).Length, 0, "Cancelled holds never end twice")
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton")
    BindingCheck(gestures.Active["LButton"].Token > lastToken, "Tokens never reset on cancellation")
}

CheckBindingSnapshots() {
    mappings := EmptyBindings()
    mappings["4L"] := BindingMapping("Release")
    gestures := BindingGestures()
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton")
    mappings["4L"].Timing := "Press"
    mappings["4L"].Hold := true
    BindingAction(gestures.Up("LButton")[1], "Tap", "4L")
    mappings["4L"] := BindingMapping("Release", true)
    BindingAction(gestures.Down(1, BindingPrimaries(true), mappings)[1], "BeginHold", "4L")
    mappings["4L"].Hold := false
    BindingAction(gestures.Cancel()[1], "EndHold", "4L")
}

WindowBinding(action, timing := "Press", hold := false) => {Action: action, Steps: [], Timing: timing, Hold: hold}

CheckWindowOrderAndModes() {
    mappings := EmptyBindings()
    mappings["5L"] := WindowBinding("MoveWindow", "Release", true)
    mappings["5R"] := WindowBinding("ResizeWindow", "Release")
    gestures := BindingGestures()
    actions := gestures.Down(2, BindingPrimaries(true), mappings, "LButton")
    BindingEqual(actions.Length, 1, "Primary-last window action begins with no keyboard steps")
    BindingAction(actions[1], "BeginWindow", "5L")
    BindingEqual(actions[1].Binding.Action, "MoveWindow", "Move action is captured")
    BindingEqual(gestures.PendingRelease(), false, "Window action ignores saved Release and Hold")
    BindingEqual(gestures.Down(2, BindingPrimaries(true), mappings, "LButton").Length, 0, "Duplicate window DOWN is silent")
    gestures.Up("LButton")
    actions := gestures.Down(2, BindingPrimaries(false, true), mappings)
    BindingEqual(actions.Length, 1, "Side-last window action begins for held primary")
    BindingAction(actions[1], "BeginWindow", "5R")
    BindingEqual(actions[1].Binding.Action, "ResizeWindow", "Resize action is captured")
    BindingEqual(gestures.PendingRelease(), false, "Release-only window action is not a pending macro")
    mappings["5M"] := BindingMapping("Release")
    gestures.Down(2, BindingPrimaries(false, true, true), mappings, "MButton")
    BindingEqual(gestures.PendingRelease(), true, "Concurrent Release macro still reports pending")
}

CheckWindowExactMask() {
    mappings := EmptyBindings()
    mappings["4L"] := WindowBinding("MoveWindow")
    mappings["45L"] := WindowBinding("ResizeWindow", "Release", true)
    gestures := BindingGestures()
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton")
    actions := gestures.Down(3, BindingPrimaries(true), mappings)
    BindingEqual(actions.Length, 2, "Exact-mask replacement has one end and one begin")
    BindingAction(actions[1], "EndWindow", "4L")
    BindingAction(actions[2], "BeginWindow", "45L")
    BindingCheck(actions[1].Binding.Token != actions[2].Binding.Token, "Replacement window binding gets a new token")
    BindingEqual(actions[1].Binding.Action, "MoveWindow", "Old window end retains its action")
    BindingEqual(actions[2].Binding.Action, "ResizeWindow", "Replacement retains its action")
    gestures.Cancel()
    mappings["45L"] := {Steps: []}
    gestures.Down(1, BindingPrimaries(true), mappings)
    actions := gestures.Down(3, BindingPrimaries(true), mappings)
    BindingEqual(actions.Length, 1, "Unassigned larger chord still ends window action")
    BindingAction(actions[1], "EndWindow", "4L")
    BindingEqual(gestures.Active.Count, 0, "No smaller window fallback remains active")
}

CheckWindowRelease() {
    mappings := EmptyBindings()
    mappings["45L"] := WindowBinding("MoveWindow", "Release", true)
    for , firstRelease in ["LButton", 4, 5] {
        gestures := BindingGestures()
        gestures.Down(3, BindingPrimaries(true), mappings, "LButton")
        actions := gestures.Up(firstRelease)
        BindingEqual(actions.Length, 1, "First constituent release ends window action")
        BindingAction(actions[1], "EndWindow", "45L")
        BindingEqual(gestures.Active.Count, 0, "First release clears window latch")
        BindingEqual(gestures.Up("LButton").Length, 0, "Later primary release cannot repeat end")
        BindingEqual(gestures.Up(4).Length, 0, "Later side4 release cannot repeat end or fall back")
        BindingEqual(gestures.Up(5).Length, 0, "Later side5 release cannot repeat end or fall back")
    }
}

CheckWindowCancel() {
    mappings := EmptyBindings()
    mappings["4L"] := WindowBinding("ResizeWindow", "Release", true)
    mappings["4R"] := BindingMapping("Release")
    gestures := BindingGestures()
    gestures.Down(1, BindingPrimaries(true, true), mappings)
    mappings["4L"].Action := "Macro"
    mappings["4L"].Hold := false
    actions := gestures.Cancel()
    BindingEqual(actions.Length, 1, "Cancellation ends window action without tapping pending macro")
    BindingAction(actions[1], "EndWindow", "4L")
    BindingEqual(actions[1].Binding.Action, "ResizeWindow", "Window lifetime uses original action snapshot")
    BindingEqual(gestures.Active.Count, 0, "Cancellation clears window and macro latches")
    BindingEqual(gestures.PendingRelease(), false, "Cancellation removes pending macro state")
    BindingEqual(gestures.Cancel().Length, 0, "Repeated cancellation has no output")
    BindingEqual(gestures.Up(4).Length, 0, "Release after cancellation cannot tap or repeat window end")
}

CheckChordDelay() {
    mappings := EmptyBindings()
    mappings["4L"] := BindingMapping()
    mappings["5LR"] := BindingMapping()
    gestures := BindingGestures()
    BindingAction(gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 100)[1], "Tap", "4L")
    gestures.Cancel()
    mappings["4LR"] := BindingMapping()
    BindingEqual(gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 100).Length, 0, "Assigned same-mask superset postpones Press")
    binding := gestures.Active["LButton"]
    BindingEqual(binding.Buttons.Length, 1, "Singleton retains an explicit Buttons array")
    BindingEqual(binding.Buttons[1], "LButton", "Singleton button snapshot")
    BindingEqual(binding.Due, 300, "Default completion deadline is 200 ms")
    BindingEqual(gestures.PendingRelease(), true, "Pending start enables cancellation")
    BindingEqual(gestures.Advance(299).Length, 0, "No output before deadline")
    actions := gestures.Advance(300)
    BindingEqual(actions.Length, 1, "Deadline emits one action")
    BindingAction(actions[1], "Tap", "4L")
    BindingCheck(actions[1].Binding = binding, "Delayed action preserves the original binding and runtime metadata")
    BindingEqual(gestures.Advance(500).Length, 0, "Deadline cannot emit twice")
    gestures.Cancel()
    BindingAction(gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 600, 0)[1], "Tap", "4L")
}

CheckLargerWithinDelay() {
    for , mask in [1, 2] {
        prefix := mask = 1 ? "4" : "5"
        first := mask = 1 ? "LButton" : "RButton"
        second := mask = 1 ? "RButton" : "LButton"
        mappings := EmptyBindings()
        mappings[prefix "L"] := BindingMapping()
        mappings[prefix "R"] := BindingMapping()
        mappings[prefix "LR"] := BindingMapping()
        gestures := BindingGestures()
        BindingEqual(gestures.Down(mask, BindingPrimaries(first = "LButton", first = "RButton"), mappings, first, 100).Length, 0, "First singleton waits")
        actions := gestures.Down(mask, BindingPrimaries(true, true), mappings, second, 250)
        BindingEqual(actions.Length, 1, "Larger chord is the only output within deadline")
        BindingAction(actions[1], "Tap", prefix "LR")
        BindingEqual(actions[1].Binding.Buttons.Length, 2, "Larger binding exposes both required primaries")
        BindingEqual(gestures.Active.Count, 1, "Unopened smaller latches are replaced")
        BindingEqual(gestures.Advance(500).Length, 0, "Cancelled smaller timer never revives")
        BindingEqual(gestures.Down(mask, BindingPrimaries(true, true), mappings, second, 600).Length, 0, "Repeated DOWN cannot repeat larger action")
    }
}

CheckLargerAfterPress() {
    mappings := EmptyBindings()
    mappings["4L"] := BindingMapping()
    mappings["4LR"] := BindingMapping()
    gestures := BindingGestures()
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 0)
    BindingAction(gestures.Advance(200)[1], "Tap", "4L")
    actions := gestures.Down(1, BindingPrimaries(true, true), mappings, "RButton", 350)
    BindingEqual(actions.Length, 1, "Already-fired singleton cannot block larger chord")
    BindingAction(actions[1], "Tap", "4LR")
    BindingCheck(gestures.Active.Has("LButton"), "Fired singleton keeps its original completion latch")
    gestures.Cancel()
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 1000)
    actions := gestures.Down(1, BindingPrimaries(true, true), mappings, "RButton", 1201)
    BindingEqual(actions.Length, 2, "A late timer deadline is honored before a later larger completion")
    BindingAction(actions[1], "Tap", "4L")
    BindingAction(actions[2], "Tap", "4LR")
}

CheckChordProgression() {
    mappings := EmptyBindings()
    mappings["4L"] := BindingMapping()
    mappings["4LR"] := BindingMapping("Press", true)
    mappings["4LRM"] := BindingMapping("Press", true)
    gestures := BindingGestures()
    BindingEqual(gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 0).Length, 0, "First stage waits")
    BindingEqual(gestures.Down(1, BindingPrimaries(true, true), mappings, "RButton", 80).Length, 0, "Two-primary stage also waits for configured third primary")
    BindingCheck(!gestures.Active.Has("LButton"), "Second stage cancels unopened first stage")
    BindingEqual(gestures.Active["4LR"].Due, 280, "Second stage starts its own completion window")
    actions := gestures.Down(1, BindingPrimaries(true, true, true), mappings, "MButton", 120)
    BindingEqual(actions.Length, 1, "Third stage starts without intermediate output")
    BindingAction(actions[1], "BeginHold", "4LRM")
    BindingEqual(actions[1].Binding.Buttons.Length, 3, "Third stage requires all primaries")
    BindingEqual(gestures.Active.Count, 1, "Only final stage remains after pending progression")
    BindingEqual(gestures.Advance(600).Length, 0, "Superseded deadlines stay cancelled")
    BindingAction(gestures.Up("MButton", 700)[1], "EndHold", "4LRM")
}

CheckGeneralChordDescriptors() {
    mappings := EmptyBindings()
    mappings["5LM"] := BindingMapping("Release")
    gestures := BindingGestures()
    BindingEqual(gestures.Down(2, BindingPrimaries(true), mappings, "LButton").Length, 0, "Missing middle cannot complete LM")
    BindingEqual(gestures.Active.Count, 0, "Incomplete descriptor does not latch")
    gestures.Down(2, BindingPrimaries(true, false, true), mappings, "MButton")
    BindingAction(gestures.Up("LButton")[1], "Tap", "5LM")

    mappings["45RM"] := WindowBinding("ResizeWindow")
    gestures := BindingGestures()
    actions := gestures.Down(3, BindingPrimaries(false, true, true), mappings)
    BindingEqual(actions.Length, 1, "Side-last completes both-side RM descriptor")
    BindingAction(actions[1], "BeginWindow", "45RM")
    BindingAction(gestures.Up(5)[1], "EndWindow", "45RM")
    BindingEqual(gestures.Up("MButton").Length, 0, "Descriptor ends once on first required UP")

    mappings["45LRM"] := BindingMapping()
    gestures := BindingGestures()
    BindingAction(gestures.Down(3, BindingPrimaries(true, true, true), mappings)[1], "Tap", "45LRM")
}

CheckLargerRelease() {
    mappings := EmptyBindings()
    mappings["4L"] := BindingMapping("Release")
    mappings["4LR"] := BindingMapping("Release")
    gestures := BindingGestures()
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 0)
    BindingEqual(gestures.Advance(500).Length, 0, "Release timing never runs on the completion deadline")
    BindingEqual(gestures.Down(1, BindingPrimaries(true, true), mappings, "RButton", 600).Length, 0, "Larger Release silently replaces smaller Release")
    actions := gestures.Up("LButton", 700)
    BindingEqual(actions.Length, 1, "Only larger Release fires on shared constituent UP")
    BindingAction(actions[1], "Tap", "4LR")
    BindingEqual(gestures.Up("RButton", 710).Length, 0, "Second constituent release is silent")
}

CheckQuickDelayedRelease() {
    examples := [
        {Mapping: BindingMapping(), Kind: "Tap", Count: 1},
        {Mapping: BindingMapping("Press", true), Kind: "BeginHold", Count: 2},
        {Mapping: WindowBinding("MoveWindow"), Kind: "", Count: 0},
        {Mapping: BindingMapping("Release"), Kind: "Tap", Count: 1}]
    for , example in examples {
        mappings := EmptyBindings()
        mappings["4L"] := example.Mapping
        mappings["4LR"] := BindingMapping()
        gestures := BindingGestures()
        gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 100)
        actions := gestures.Up("LButton", 150)
        BindingEqual(actions.Length, example.Count, "Quick release output matches action mode")
        if example.Count
            BindingAction(actions[1], example.Kind, "4L")
        if example.Count = 2 {
            BindingAction(actions[2], "EndHold", "4L")
            BindingEqual(actions[1].Binding.Token, actions[2].Binding.Token, "Quick hold cleanup owns the same token")
        }
        BindingEqual(gestures.Advance(400).Length, 0, "Quick release cancels its deadline")
        BindingEqual(gestures.Up(4, 450).Length, 0, "Later side release does not repeat quick output")
    }
}

CheckStartedHoldProgression() {
    mappings := EmptyBindings()
    mappings["4L"] := BindingMapping("Press", true)
    mappings["4LR"] := BindingMapping("Press", true)
    gestures := BindingGestures()
    BindingAction(gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 0, 0)[1], "BeginHold", "4L")
    actions := gestures.Down(1, BindingPrimaries(true, true), mappings, "RButton", 50, 0)
    BindingEqual(actions.Length, 1, "Larger hold does not release a started smaller hold")
    BindingAction(actions[1], "BeginHold", "4LR")
    BindingEqual(gestures.Active.Count, 2, "Both hold owners stay latched")
    BindingAction(gestures.Up("RButton", 100)[1], "EndHold", "4LR")
    BindingCheck(gestures.Active.Has("LButton"), "Smaller hold survives unrelated larger constituent UP")
    BindingAction(gestures.Up("LButton", 110)[1], "EndHold", "4L")

    mappings["4LR"] := BindingMapping()
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 200, 0)
    actions := gestures.Down(1, BindingPrimaries(true, true), mappings, "RButton", 250, 0)
    BindingEqual(actions.Length, 2, "Larger Tap first releases the smaller hold")
    BindingAction(actions[1], "EndHold", "4L")
    BindingAction(actions[2], "Tap", "4LR")
    gestures.Cancel()

    mappings["4LR"] := WindowBinding("MoveWindow")
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 300, 0)
    actions := gestures.Down(1, BindingPrimaries(true, true), mappings, "RButton", 350, 0)
    BindingAction(actions[1], "EndHold", "4L")
    BindingAction(actions[2], "BeginWindow", "4LR")
    gestures.Cancel()

    mappings["4L"] := WindowBinding("MoveWindow")
    mappings["4LR"] := BindingMapping("Press", true)
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 400, 0)
    actions := gestures.Down(1, BindingPrimaries(true, true), mappings, "RButton", 450, 0)
    BindingAction(actions[1], "EndWindow", "4L")
    BindingAction(actions[2], "BeginHold", "4LR")
}

CheckDelayedCancellation() {
    mappings := EmptyBindings()
    mappings["4L"] := BindingMapping("Press", true)
    mappings["4LR"] := BindingMapping()
    mappings["45L"] := BindingMapping()
    gestures := BindingGestures()
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 0)
    BindingEqual(gestures.Cancel().Length, 0, "Cancel never opens a pending hold")
    BindingEqual(gestures.Advance(500).Length, 0, "Cancelled timer stays silent")
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 600)
    actions := gestures.Down(3, BindingPrimaries(true), mappings, "", 650)
    BindingEqual(actions.Length, 1, "Side-mask change discards pending old start before replacement")
    BindingAction(actions[1], "Tap", "45L")
    BindingEqual(gestures.Advance(1000).Length, 0, "Old exact-mask deadline cannot revive")
}

CheckChordUnwind() {
    mappings := EmptyBindings()
    mappings["4L"] := BindingMapping()
    mappings["4LR"] := BindingMapping("Press", true)
    mappings["4LRM"] := BindingMapping("Press", true)
    gestures := BindingGestures()
    actions := gestures.Down(1, BindingPrimaries(true, true, true), mappings, "", 0)
    BindingEqual(actions.Length, 1, "Side-last chooses the maximal configured completion")
    BindingAction(actions[1], "BeginHold", "4LRM")
    actions := gestures.Up("MButton", 30)
    BindingEqual(actions.Length, 1, "First UP only ends the larger binding")
    BindingAction(actions[1], "EndHold", "4LRM")
    BindingEqual(gestures.Active.Count, 0, "UP cannot latch smaller LR or L")
    BindingEqual(gestures.Advance(500).Length, 0, "Unwound subset has no deadline")
    actions := gestures.Down(1, BindingPrimaries(true, true, true), mappings, "MButton", 600)
    BindingEqual(actions.Length, 1, "Fresh DOWN completes larger again without releasing all partners")
    BindingAction(actions[1], "BeginHold", "4LRM")
    BindingEqual(gestures.Down(1, BindingPrimaries(true, true, true), mappings, "MButton", 650).Length, 0, "Duplicate completion cannot repeat")
    BindingAction(gestures.Up(4, 700)[1], "EndHold", "4LRM")
    BindingEqual(gestures.Up("LButton", 710).Length, 0, "Later UP remains silent")
}

CheckDoubleRecognition() {
    for , id in ["4DL", "4DR", "5DL", "5DR"] {
        chord := MacroModel.Chord(id)
        button := chord.Buttons[1]
        singles := BindingPrimaries(button = "LButton", button = "RButton")
        singleID := MacroModel.ChordID(chord.Mask, button)
        mappings := EmptyBindings()
        mappings[singleID] := BindingMapping()
        mappings[id] := BindingMapping()
        gestures := BindingGestures()
        BindingEqual(gestures.Down(chord.Mask, singles, mappings, button, 100).Length, 0, "First double candidate does not emit singleton")
        first := gestures.Active[button]
        first.Target := 123
        first.Epoch := 9
        BindingCheck(first.DoublePending, "First candidate remains visible for runtime tagging")
        BindingEqual(gestures.Up(button, 130).Length, 0, "First UP remains silent during recognition")
        BindingCheck(gestures.Active[button] = first && first.Released, "Released first candidate retains original metadata")
        actions := gestures.Down(chord.Mask, singles, mappings, button, 250)
        BindingEqual(actions.Length, 1, "Second DOWN replaces both singles with one double")
        BindingAction(actions[1], "Tap", id)
        BindingCheck(actions[1].Binding.IsDouble, "Runtime can identify recognized double output")
        BindingCheck(!gestures.Active.Has(button), "Replaced singleton is no longer latched")
        BindingEqual(gestures.Advance(500).Length, 0, "Recognized double leaves no singleton deadline")
        BindingEqual(gestures.Up(button, 510).Length, 0, "Press double does not repeat on second UP")
    }
}

CheckDoubleDeadline() {
    mappings := EmptyBindings()
    mappings["4L"] := BindingMapping()
    mappings["4DL"] := BindingMapping()
    gestures := BindingGestures()
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 0)
    BindingEqual(gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 100).Length, 0, "Duplicate DOWN without UP is not a double")
    BindingAction(gestures.Advance(200)[1], "Tap", "4L")
    BindingEqual(gestures.Up("LButton", 210).Length, 0, "Expired first Press cannot repeat on UP")
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 300)
    gestures.Up("LButton", 320)
    actions := gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 500)
    BindingEqual(actions.Length, 1, "A second DOWN at the deadline resolves the first singleton")
    BindingAction(actions[1], "Tap", "4L")
    BindingCheck(gestures.Active["LButton"].DoublePending, "Late click starts a new independent recognition window")
    BindingEqual(gestures.Active["LButton"].Due, 700, "New window is anchored to its own first DOWN")
}

CheckDoubleReleasedExpiry() {
    examples := [
        {Mapping: BindingMapping(), Kind: "Tap", Count: 1},
        {Mapping: BindingMapping("Release"), Kind: "Tap", Count: 1},
        {Mapping: BindingMapping("Press", true), Kind: "BeginHold", Count: 2},
        {Mapping: WindowBinding("MoveWindow"), Kind: "", Count: 0}]
    for , example in examples {
        mappings := EmptyBindings()
        mappings["4L"] := example.Mapping
        mappings["4DL"] := BindingMapping()
        gestures := BindingGestures()
        gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 0)
        original := gestures.Active["LButton"]
        original.Target := 456
        original.Epoch := 10
        BindingEqual(gestures.Up("LButton", 50).Length, 0, "First UP cannot leak any singleton mode")
        BindingEqual(gestures.Advance(199).Length, 0, "Released first click remains pending until deadline")
        actions := gestures.Advance(200)
        BindingEqual(actions.Length, example.Count, "Expiry resolves the released singleton mode once")
        if example.Count {
            BindingAction(actions[1], example.Kind, "4L")
            BindingCheck(actions[1].Binding = original, "Expiry preserves original target/epoch record")
        }
        if example.Count = 2 {
            BindingAction(actions[2], "EndHold", "4L")
            BindingEqual(actions[1].Binding.Token, actions[2].Binding.Token, "Expired quick hold has balanced ownership")
        }
        BindingEqual(gestures.Active.Count, 0, "Released expired candidate removes its latch")
        BindingEqual(gestures.Advance(400).Length, 0, "Expiry cannot repeat")
    }
}

CheckDoubleHeldExpiry() {
    mappings := EmptyBindings()
    mappings["5R"] := BindingMapping("Press", true)
    mappings["5DR"] := BindingMapping()
    gestures := BindingGestures()
    gestures.Down(2, BindingPrimaries(false, true), mappings, "RButton", 0)
    BindingAction(gestures.Advance(200)[1], "BeginHold", "5R")
    BindingAction(gestures.Up("RButton", 250)[1], "EndHold", "5R")
    mappings["5R"] := BindingMapping("Release")
    gestures.Down(2, BindingPrimaries(false, true), mappings, "RButton", 300)
    BindingEqual(gestures.Advance(500).Length, 0, "Held Release only arms after recognition expires")
    BindingAction(gestures.Up(5, 600)[1], "Tap", "5R")
    BindingEqual(gestures.Up("RButton", 650).Length, 0, "Release singleton still fires only on first required UP")
}

CheckDoubleAssignmentAndZeroDelay() {
    mappings := EmptyBindings()
    mappings["4DL"] := BindingMapping()
    gestures := BindingGestures()
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 0)
    BindingEqual(gestures.Active["LButton"].Assigned, false, "Unassigned singleton can carry a double candidate")
    gestures.Up("LButton", 30)
    BindingAction(gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 100)[1], "Tap", "4DL")
    gestures.Cancel()
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 300)
    gestures.Up("LButton", 350)
    BindingEqual(gestures.Advance(500).Length, 0, "Unassigned singleton expiry emits nothing")
    mappings["4L"] := BindingMapping()
    BindingAction(gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 600, 0)[1], "Tap", "4L")
    gestures.Up("LButton", 610)
    BindingAction(gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 650, 0)[1], "Tap", "4L")
    gestures.Cancel()
    BindingAction(gestures.Down(1, BindingPrimaries(true), mappings, "", 800)[1], "Tap", "4L")
    BindingEqual(gestures.Active["LButton"].DoublePending, false, "Side-last is an ordinary chord, not a synthetic first click")
}

CheckDoubleContextBreaks() {
    mappings := EmptyBindings()
    mappings["4L"] := BindingMapping()
    mappings["4R"] := BindingMapping()
    mappings["4DL"] := BindingMapping()
    mappings["4LR"] := BindingMapping()
    gestures := BindingGestures()
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 0)
    actions := gestures.Down(1, BindingPrimaries(true, true), mappings, "RButton", 50)
    BindingEqual(actions.Length, 1, "Joining primary lets configured larger chord consume deferred singleton")
    BindingAction(actions[1], "Tap", "4LR")
    BindingEqual(gestures.Advance(500).Length, 0, "Larger completion cancels double recognition deadline")
    gestures.Cancel()

    mappings["4LR"] := {Steps: []}
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 600)
    gestures.Up("LButton", 620)
    actions := gestures.Down(1, BindingPrimaries(false, true), mappings, "RButton", 630)
    BindingEqual(actions.Length, 2, "Mixed click resolves old singleton and new independent click")
    BindingAction(actions[1], "Tap", "4L")
    BindingAction(actions[2], "Tap", "4R")
    gestures.Cancel()

    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 700)
    gestures.Up("LButton", 720)
    BindingAction(gestures.Up(4, 730)[1], "Tap", "4L")
    BindingEqual(gestures.Advance(1000).Length, 0, "Side UP ends continuous-side recognition")

    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 1100)
    gestures.Up("LButton", 1120)
    BindingEqual(gestures.Down(3, BindingPrimaries(), mappings, "", 1130).Length, 0, "Side-mask replacement cancels old candidate without playback")
    BindingEqual(gestures.Advance(1400).Length, 0, "Changed-mask candidate never revives")
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 1500)
    gestures.Up("LButton", 1520)
    BindingEqual(gestures.Cancel().Length, 0, "Mode/profile cancellation discards deferred first click")
    BindingEqual(gestures.Advance(1800).Length, 0, "Cancelled double timer is silent")
}

CheckDoubleOutputModes() {
    examples := [
        {Mapping: BindingMapping("Press", true), Begin: "BeginHold", End: "EndHold"},
        {Mapping: BindingMapping("Release"), Begin: "", End: "Tap"},
        {Mapping: WindowBinding("ResizeWindow"), Begin: "BeginWindow", End: "EndWindow"}]
    for , example in examples {
        mappings := EmptyBindings()
        mappings["5R"] := BindingMapping()
        mappings["5DR"] := example.Mapping
        gestures := BindingGestures()
        gestures.Down(2, BindingPrimaries(false, true), mappings, "RButton", 0)
        gestures.Up("RButton", 30)
        actions := gestures.Down(2, BindingPrimaries(false, true), mappings, "RButton", 100)
        BindingEqual(actions.Length, example.Begin = "" ? 0 : 1, "Double begins according to its own output mode")
        if example.Begin != ""
            BindingAction(actions[1], example.Begin, "5DR")
        actions := gestures.Up(5, 130)
        BindingEqual(actions.Length, 1, "First second-click constituent UP completes double")
        BindingAction(actions[1], example.End, "5DR")
        BindingEqual(gestures.Up("RButton", 150).Length, 0, "Later second-click UP cannot repeat double cleanup")
        BindingEqual(gestures.Advance(500).Length, 0, "Double output leaves no old singles behind")
    }
}

CheckToggleTiming() {
    mappings := EmptyBindings()
    mappings["4L"] := WindowBinding("ToggleTopmost", "Press", true)
    gestures := BindingGestures()
    actions := gestures.Down(1, BindingPrimaries(true), mappings, "LButton")
    BindingEqual(actions.Length, 1, "Press toggle emits one discrete action")
    BindingAction(actions[1], "ToggleTopmost", "4L")
    BindingEqual(actions[1].Binding.Hold, true, "Stored Hold remains retained in the snapshot")
    BindingEqual(gestures.Up("LButton").Length, 0, "Press toggle has no hold/window cleanup")
    mappings["4L"] := WindowBinding("ToggleTopmost", "Release", true)
    BindingEqual(gestures.Down(1, BindingPrimaries(true), mappings, "LButton").Length, 0, "Release toggle ignores retained Hold and only arms")
    BindingCheck(gestures.PendingRelease(), "Release toggle enables cancellation")
    BindingAction(gestures.Up(4)[1], "ToggleTopmost", "4L")
    BindingEqual(gestures.Up("LButton").Length, 0, "Toggle fires only on the first required UP")
}

CheckToggleDelay() {
    mappings := EmptyBindings()
    mappings["4L"] := WindowBinding("ToggleTopmost", "Press", true)
    mappings["4LR"] := BindingMapping()
    gestures := BindingGestures()
    BindingEqual(gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 0).Length, 0, "Ambiguous toggle waits for a larger chord")
    BindingAction(gestures.Up("LButton", 30)[1], "ToggleTopmost", "4L")
    BindingEqual(gestures.Advance(300).Length, 0, "Quick toggle does not repeat at the deadline")
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 400)
    BindingEqual(gestures.Cancel().Length, 0, "Profile/mode cancellation drops unopened toggle")
    BindingEqual(gestures.Advance(700).Length, 0, "Cancelled toggle has no delayed output")
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 800)
    actions := gestures.Down(1, BindingPrimaries(true, true), mappings, "RButton", 850)
    BindingEqual(actions.Length, 1, "Larger chord suppresses the pending toggle")
    BindingAction(actions[1], "Tap", "4LR")
    BindingEqual(gestures.Advance(1200).Length, 0, "Suppressed toggle cannot revive")
}

CheckToggleDouble() {
    mappings := EmptyBindings()
    mappings["4L"] := WindowBinding("ToggleTopmost", "Press", true)
    mappings["4DL"] := WindowBinding("ToggleTopmost", "Release", true)
    gestures := BindingGestures()
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 0)
    BindingEqual(gestures.Up("LButton", 20).Length, 0, "Double candidate suppresses quick first toggle")
    BindingEqual(gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 100).Length, 0, "Recognized Release double waits despite stored Hold")
    BindingAction(gestures.Up("LButton", 130)[1], "ToggleTopmost", "4DL")
    BindingEqual(gestures.Advance(400).Length, 0, "Exclusive double leaves no single toggles")
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 500)
    gestures.Up("LButton", 520)
    BindingAction(gestures.Advance(700)[1], "ToggleTopmost", "4L")
    mappings["4L"] := WindowBinding("ToggleTopmost", "Release", true)
    gestures.Down(1, BindingPrimaries(true), mappings, "LButton", 800)
    BindingEqual(gestures.Advance(1000).Length, 0, "Held Release singleton only arms when double window expires")
    BindingAction(gestures.Up("LButton", 1050)[1], "ToggleTopmost", "4L")
}
