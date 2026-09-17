; Real mapper handlers with hidden controls, disposable config and mocked output.
RunBindingRuntimeTests() {
    count := 0
    app := 0
    Check(condition, message) {
        count += 1
        if !condition
            throw Error(message)
    }
    root := A_ScriptDir "\tests\artifacts"
    DirCreate(root)
    try {
        app := BindingRuntimeMapper(root "\binding-runtime-" ProcessExist() ".ini", true)
        app.ResetFixture()
        Check(!DllCall("IsWindowVisible", "Ptr", app.Window.Hwnd) && !app.HasOwnProp("ForegroundHook"), "Hidden fixture without hooks")

        app.Bind("4L", "key Enter")
        app.SideDown(4, true)
        app.Press("LButton")
        Check(app.Running && app.BlockedPrimary("LButton"), "Press starts on primary-last and owns mouse up")
        app.Tick()
        app.Tick()
        Check(!app.HasCancelableInput(), "Completed press action does not keep native Escape intercepted")
        app.Press("LButton")
        Check(app.CountOutput("Tap") = 1 && !app.Running, "Duplicate primary down cannot repeat")
        app.PrimaryUp("LButton")
        app.SideUp(4)
        Check(app.Replays = 0 && app.State.AllReleased(), "Used press sides do not replay")

        app.ResetFixture()
        app.Press("LButton")
        Check(!app.BlockedPrimary("LButton"), "Native primary-first down passes through")
        app.SideDown(4, true)
        app.Tick()
        Check(app.CountOutput("Tap") = 1 && !app.BlockedPrimary("LButton"), "Side-last completes mapping without stealing original mouse up")
        app.SideDown(4, true)
        app.Tick()
        Check(!app.Running && app.CountOutput("Tap") = 1, "Duplicate side down cannot repeat")
        app.SideUp(4)
        app.PrimaryUp("LButton")

        app.ResetFixture()
        app.Bind("45M", "key Enter", "Release")
        app.SideDown(5, true)
        app.SideDown(4, true)
        app.Press("MButton")
        Check(!app.Running && app.Gestures.Active.Count = 1, "Release mapping arms without output")
        Check(app.HasCancelableInput(), "Pending Release enables Escape cancellation")
        app.SideUp(5)
        Check(app.Running && app.BlockedPrimary("MButton") && app.State.Sides[4].Down, "First side release triggers without waiting for other releases")
        app.Tick()
        app.Tick()
        app.SideUp(4)
        app.PrimaryUp("MButton")
        app.Tick()
        Check(app.CountOutput("Tap") = 1 && app.Replays = 0, "Remaining releases cannot retrigger or replay sides")

        app.ResetFixture()
        app.Bind("4L", "key Enter", "Release")
        app.Press("LButton")
        app.SideDown(4, true)
        app.PrimaryUp("LButton")
        app.Tick()
        Check(app.CountOutput("Tap") = 1 && app.State.Sides[4].Down, "Primary-first release mapping fires on primary up")
        app.SideUp(4)

        app.ResetFixture()
        app.Bind("45L", "", "Press")
        app.SideDown(4, true)
        app.Press("LButton")
        app.SideDown(5, true)
        app.SideUp(5)
        app.PrimaryUp("LButton")
        app.SideUp(4)
        Check(!app.Running && !app.Outputs.Length, "Extra side cancels old pending release; no smaller fallback on up")

        app.ResetFixture()
        app.Bind("5L", "key Win", "Press", true)
        app.SideDown(5, true)
        app.Press("LButton")
        Check(app.Held.Active && app.CountOutput("Down") = 1
            && app.Outputs[1].Key = MacroModel.HoldKeyIdentity("LWin"), "Standalone Win holds only Windows, not an arrow or mouse button")
        app.SideUp(5)
        Check(!app.Held.Active && app.CountOutput("Up") = 1 && app.BlockedPrimary("LButton"), "Standalone Win releases on first side up and retains click suppression")
        app.PrimaryUp("LButton")
        Check(app.State.AllReleased(), "Standalone modifier leaves no held mouse state")

        app.ResetFixture()
        app.Bind("4L", "key Ctrl+C", "Release", true)
        app.Bind("4R", "key Ctrl+C", "Press", true)
        app.SideDown(4, true)
        app.Press("LButton")
        Check(app.Held.Active && app.CountOutput("Down") = 2 && !app.Running, "Hold starts on completion despite stored Release timing")
        app.Press("RButton")
        Check(app.Held.Owners.Count = 2 && app.CountOutput("Down") = 2, "Overlapping holds share actual key downs")
        app.PrimaryUp("LButton")
        Check(app.Held.Active && app.CountOutput("Up") = 0, "First hold cannot release shared keys")
        app.SideUp(4)
        Check(!app.Held.Active && app.CountOutput("Up") = 2 && app.BlockedPrimary("RButton"), "First required side release ends final hold and retains primary up ownership")
        Check(app.Outputs[3].Key = app.Outputs[2].Key, "Base key is released before shortcut modifier")
        app.PrimaryUp("RButton")

        app.ResetFixture()
        app.Bind("4R", "key Enter")
        app.SideDown(4, true)
        app.Press("LButton")
        app.Press("RButton")
        Check(!app.Running && app.CountOutput("Tap") = 0 && app.Held.Active, "One-shot cannot disturb a held shortcut")
        app.EscapePressed()
        Check(!app.Held.Active && app.Gestures.Active.Count = 0 && app.BlockedPrimary("LButton"), "Escape releases keyboard while preserving intercepted mouse releases")
        app.PrimaryUp("LButton")
        app.PrimaryUp("RButton")
        app.SideUp(4)
        Check(app.State.AllReleased() && app.Replays = 0, "Cancelled hold drains without side replay")

        app.ResetFixture()
        app.SideDown(4, true)
        app.Press("LButton")
        app.TogglePause()
        Check(app.State.Paused && !app.Held.Active, "Pause releases injected keys")
        app.TogglePause()
        app.SideDown(4, true)
        Check(!app.Held.Active, "Resume cannot reactivate already-held buttons")
        app.PrimaryUp("LButton")
        app.SideUp(4)

        app.ResetFixture()
        app.SideDown(4, true)
        app.Press("LButton")
        app.FakeTarget := 202
        app.CheckForeground()
        Check(!app.Held.Active && app.Gestures.Active.Count = 0, "Focus change cleans held keyboard and latches")

        app.ResetFixture()
        app.SideDown(4, true)
        app.Press("LButton")
        app.ToggleRecording()
        Check(!app.Held.Active && app.Capture.Active, "Recording releases active holds")
        app.PrimaryUp("LButton")
        app.SideUp(4)
        app.UpdateCapture()
        app.SideDown(4, true)
        app.Press("LButton")
        Check(!app.Held.Active && !app.Running && app.CountOutput("Down") = 2, "Record combination cannot execute hold binding")
        app.Cancel()

        app.ResetFixture()
        app.SideDown(4, true)
        app.Press("LButton")
        app.FailedUps := 4
        app.PrimaryUp("LButton")
        Check(app.CleanupPending && app.Held.Active, "Failed up remains owned for retry")
        app.Tick()
        Check(!app.CleanupPending && !app.Held.Active, "Timer retries failed cleanup using mocked output")

        app.ResetFixture()
        app.Bind("4L", "key Enter", "Release")
        app.SideDown(4, true)
        app.Press("LButton")
        app.Cancel()
        app.SideUp(4)
        app.PrimaryUp("LButton")
        Check(!app.Running && !app.Outputs.Length, "Cancel pending Release never dispatches an action")
        app.ResetFixture()
        app.SideDown(4, true)
        app.SideUp(4)
        Check(app.Replays = 1, "Unused standalone side replay still works")
        app.ResetFixture()
        app.Bind("4L", "key Ctrl+C", "Press", true)
        app.SideDown(4, true)
        app.Press("LButton")
        app.EditSelected()
        Check(!app.Held.Active && app.Gestures.Active.Count = 0, "Entering editor releases held keys and cancels binding")
        app.CloseEditor()
        app.ResetFixture()
        RunBindingEditorChecks(app, Check)
        RunWindowActionChecks(app, Check)
        RunChordRuntimeChecks(app, Check)
        RunProfileRuntimeChecks(app, Check)
        RunNativeActionRuntimeChecks(app, Check)
        app.ResetFixture()
        app.Bind("4L", "key Ctrl+C", "Press", true)
        app.SideDown(4, true)
        app.Press("LButton")
        app.Cleanup()
        Check(!app.Held.Active && app.CountOutput("Up") = 2, "Exit cleanup releases keyboard keys")
        output := "PASS binding runtime/editor smoke / " count " assertions`nHidden native controls, isolated settings, mocked output; no hooks or desktop input.`n"
        FileAppend(output, "*")
        report := root "\binding-runtime-latest.log"
        if FileExist(report)
            FileDelete(report)
        FileAppend(output, report, "UTF-8")
    } catch Error as err {
        FileAppend("FAIL: " err.Message " at " err.File ":" err.Line "`n", "*")
        ExitApp(1)
    } finally {
        if IsObject(app) {
            app.Cleanup()
            if app.HasOwnProp("Editor")
                app.Editor.Destroy()
            app.Window.Destroy()
        }
    }
}

class BindingRuntimeMapper extends MouseMapper {
    FakeTarget := 101
    Outputs := []
    Replays := 0
    FailedUps := 0
    FakeNow := 1000
    InputNow() => this.FakeNow
    CurrentTarget() => this.FakeTarget
    IsOwn(target) => false
    PointerContext() => {Root: this.FakeTarget, Capture: 0}
    CaptureCancelClick(button) => false
    KeyboardModifiersHeld() => false
    PhysicalKeyHeld(key) => false
    Press(button) => this.PrimaryDown(button, this.ShouldBlock(button))
    Bind(id, source, timing := "Press", hold := false, action := "Macro") {
        this.Config.Mappings[id] := {Name: "Fixture", Source: source,
            Steps: MacroModel.MappingSteps(source, action), Timing: timing, Hold: hold, Action: action}
    }
    ResetFixture() {
        this.Cancel()
        this.State := ChordState()
        this.State.Paused := false
        this.Capture := CombinationCapture()
        this.Config.Preserve := true
        this.FakeTarget := 101
        this.Foreground := 101
        this.Outputs := []
        this.Replays := 0
        this.FailedUps := 0
        this.FakeNow := 1000
    }
    CountOutput(kind) {
        count := 0
        for , entry in this.Outputs
            if entry.Kind = kind
                count += 1
        return count
    }
    EmitHeldKey(key, down) {
        if !down && this.FailedUps {
            this.FailedUps -= 1
            throw Error("Fixture key-up failure")
        }
        this.Outputs.Push({Kind: down ? "Down" : "Up", Key: key})
    }
    EmitMacroKey(value) => this.Outputs.Push({Kind: "Tap", Key: value})
    EmitMacroText(value) => this.Outputs.Push({Kind: "Text", Key: value})
    EmitSideReplay(id) => this.Replays += 1
}

; Calls the real button/cancel/timer handlers; only window geometry is mocked.
RunWindowActionChecks(app, check) {
    adapter := BindingWindowAdapter()
    app.ResetFixture()
    app.WindowDrag := WindowDrag(adapter)
    app.Bind("5L", "invalid inactive macro", "Release", true, "MoveWindow")
    app.Bind("5R", "", "Release", true, "ResizeWindow")
    app.SideDown(5, true)
    check.Call(app.ShouldBlock("LButton"), "Empty-step window action owns the primary down")
    app.Press("LButton")
    check.Call(app.WindowDrag.Active && app.HasCancelableInput() && !app.Running && !app.Held.Active,
        "Move starts on completion and ignores retained macro/timing/hold options")
    adapter.Cursor := {X: 240, Y: 250}
    app.Tick()
    check.Call(adapter.Applied.Length = 1 && adapter.Applied[1].X = 140 && adapter.Applied[1].Y = 150,
        "Real timer dispatch applies the move delta")
    readCount := adapter.Starts
    app.Press("LButton")
    check.Call(adapter.Starts = readCount && app.WindowDrag.Active, "Duplicate down cannot restart the drag")
    adapter.Cursor := {X: 260, Y: 260}
    app.SideUp(5)
    check.Call(!app.WindowDrag.Active && adapter.Applied.Length = 2 && adapter.Applied[2].X = 160,
        "First side release flushes final cursor delta then stops")
    check.Call(app.BlockedPrimary("LButton") && !app.HasCancelableInput(), "Released drag retains only original primary-up ownership")
    app.PrimaryUp("LButton")
    check.Call(app.State.AllReleased() && !app.Outputs.Length && !app.Replays,
        "Completed drag emits no keyboard or side replay")

    app.ResetFixture()
    adapter.Cursor := {X: 450, Y: 350}
    app.SideDown(5, true)
    app.Press("RButton")
    adapter.Cursor := {X: 500, Y: 400}
    app.PrimaryUp("RButton")
    last := adapter.Applied[adapter.Applied.Length]
    check.Call(!app.WindowDrag.Active && last.W = 450 && last.H = 350 && last.X = 100,
        "Resize ends on primary release with final size")
    app.SideUp(5)
    check.Call(!app.Replays && !app.Outputs.Length, "Resize suppresses context-click and side replay through owned handlers")

    app.ResetFixture()
    app.Press("LButton")
    app.SideDown(5, true)
    check.Call(!app.WindowDrag.Active && !app.BlockedPrimary("LButton"),
        "Primary-first native drag cannot start window movement or steal native up")
    app.PrimaryUp("LButton")
    app.SideUp(5)
    check.Call(app.State.AllReleased() && !app.Replays, "Rejected window gesture drains cleanly")

    app.ResetFixture()
    app.Bind("4L", "key Enter")
    app.SideDown(5, true)
    app.Press("LButton")
    app.SideDown(4, true)
    check.Call(!app.WindowDrag.Active, "Added side stops window action when exact mask changes")
    app.SideUp(5)
    app.PrimaryUp("LButton")
    app.SideUp(4)
    check.Call(!app.Running && !app.Outputs.Length, "Release cannot start a smaller window or keyboard mapping")

    for , stop in ["Escape", "Pause", "Focus", "Record", "Editor"] {
        app.ResetFixture()
        app.SideDown(5, true)
        app.Press("LButton")
        check.Call(app.WindowDrag.Active, stop " fixture starts window action")
        appliedCount := adapter.Applied.Length
        adapter.Cursor := {X: adapter.Cursor.X + 20, Y: adapter.Cursor.Y + 20}
        switch stop {
            case "Escape": app.EscapePressed()
            case "Pause": app.TogglePause()
            case "Focus":
                app.FakeTarget := 202
                app.CheckForeground()
            case "Record": app.ToggleRecording()
            case "Editor": app.EditSelected()
        }
        check.Call(!app.WindowDrag.Active && !app.Gestures.Active.Count
            && adapter.Applied.Length = appliedCount && app.BlockedPrimary("LButton"),
            stop " stops without another move and preserves intercepted mouse-up cleanup")
        if stop = "Editor"
            app.CloseEditor()
        app.PrimaryUp("LButton")
        app.SideUp(5)
        check.Call(!app.Outputs.Length && !app.Replays, stop " has no late keyboard action or side replay")
    }

    app.ResetFixture()
    app.SideDown(5, true)
    app.Press("LButton")
    adapter.FailRead := true
    app.Tick()
    check.Call(!app.WindowDrag.Active && !app.Gestures.Active.Count && app.State.Inhibited,
        "Target failure cancels engine and gesture and requires fresh buttons")
    adapter.FailRead := false
    app.PrimaryUp("LButton")
    app.SideUp(5)
}

class BindingWindowAdapter {
    Cursor := {X: 200, Y: 200}
    Applied := []
    Starts := 0
    FailRead := false
    ReadTarget(hwnd) {
        if this.FailRead
            throw Error("Fixture target closed")
        this.Starts += 1
        return {Hwnd: hwnd, PID: 1, Thread: 2, Class: "Fixture", Rect: {X: 100, Y: 100, W: 400, H: 300},
            Own: false, Visible: true, Minimized: false, Maximized: false, Excluded: false, Resizable: true}
    }
    ReadCursor() => this.Cursor.Clone()
    ReadMinimum(hwnd) => {W: 100, H: 80}
    ApplyRect(hwnd, rect) => this.Applied.Push(rect.Clone())
}
