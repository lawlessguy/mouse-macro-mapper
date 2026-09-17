; Small opt-in smoke test: hidden controls, isolated settings, no hooks or input.
RunRecordUiTests() {
    checks := 0
    root := A_ScriptDir "\tests\artifacts"
    DirCreate(root)
    path := root "\record-smoke-" ProcessExist() ".ini"
    app := 0
    Check(condition, message) {
        checks += 1
        if !condition
            throw Error(message)
    }
    try {
        app := RecordingSmokeMapper(path, true)
        app.Foreground := app.Window.Hwnd
        Check(!DllCall("IsWindowVisible", "Ptr", app.Window.Hwnd), "Main window hidden")
        Check(!app.HasOwnProp("ForegroundHook"), "No input/focus hooks")
        app.SetView("List")
        Check(app.RecordButton.Visible, "Record available in List View")
        app.SetView("Mouse")
        Check(app.RecordButton.Visible, "Record available in Mouse View")
        before := FileRead(path)
        for , chord in MacroModel.Chords
            app.Config.Mappings[chord.ID] := {Name: "Smoke " chord.ID, Source: "key Enter", Steps: MacroModel.Parse("key Enter")}
        app.EditSelected()
        oldID := app.EditID
        app.SourceEdit.Value := "key Enter"
        app.Running := true
        app.ToggleRecording()
        Check(!app.Running && app.State.Paused, "Recording stops macro and preserves pause")
        Check(app.ShouldBlock("RButton"), "Listening suppresses fresh primary down without sides")
        app.SideDown(5, true)
        app.SideDown(4, true)
        Check(app.ShouldBlock("MButton"), "Capture swallows middle down while paused in own GUI")
        app.PrimaryDown("MButton", true)
        Check(app.Capture.Phase = "Matched" && app.EditID = oldID, "Match waits before switching editor")
        app.SideUp(4)
        app.SideUp(5)
        app.UpdateCapture()
        Check(app.BlockedPrimary("MButton") && app.EditID = oldID, "Captured primary UP still owned after sides released")
        app.PrimaryUp("MButton")
        app.UpdateCapture()
        Check(app.SelectedID() = "45M" && app.EditID = "45M", "Both-side middle selects and opens editor")
        Check(!app.Capture.Active && app.State.AllReleased(), "Capture finishes after all releases")
        Check(!DllCall("IsWindowVisible", "Ptr", app.Editor.Hwnd), "Editor stays hidden in test")
        Check(app.Drafts.Has(oldID) && app.Drafts[oldID].Source = "key Enter", "Old editor draft retained")
        Check(FileRead(path) = before, "Recording does not write settings or mappings")
        Check(app.Dispatches = 0 && app.Replays = 0, "Recording emits no macro or side replay")

        app.State.SetPaused(false)
        app.ToggleRecording()
        app.SideDown(4, true)
        app.PrimaryDown("LButton", app.ShouldBlock("LButton"))
        app.EscapePressed()
        Check(app.Capture.Phase = "Draining" && app.BlockedPrimary("LButton"), "Escape cancels result and retains release ownership")
        app.PrimaryUp("LButton")
        app.SideUp(4)
        app.UpdateCapture()
        Check(!app.Capture.Active && app.EditID = "45M" && !app.State.Paused, "Cancel leaves selection and pause unchanged")
        Check(!app.ShouldBlock("LButton") && !app.BlockedPrimary("LButton"), "Ordinary click restored after cancellation")
        app.PrimaryDown("LButton", false)
        app.ToggleRecording()
        Check(app.Capture.Phase = "Arming" && !app.BlockedPrimary("LButton"), "Preexisting launch click retains native release")
        Check(app.ShouldBlock("RButton") && !app.ShouldBlock("LButton"), "Arming suppresses fresh click but preserves existing press")
        app.PrimaryUp("LButton")
        app.UpdateCapture()
        Check(app.Capture.Phase = "Listening", "Recorder arms after launch release")
        app.UpdateCapture(app.Capture.Deadline)
        Check(!app.Capture.Active && InStr(app.Message, "timed out"), "15 second timeout returns to idle")
        app.ToggleRecording()
        app.Hide()
        app.UpdateCapture()
        Check(!app.Capture.Active, "Hiding cancels recording")
        Check(app.Dispatches = 0 && app.Replays = 0 && app.State.AllReleased(), "No output or held state remains")

        chordCount := 0, doubleCount := 0
        for index, chord in MacroModel.Chords {
            app.FakeNow := A_TickCount
            app.Config.ChordDelayMs := 200
            app.ToggleRecording()
            Check(app.Capture.Phase = "Listening", "All-up recorder listens: " chord.ID)
            sides := chord.Mask = 1 ? [4] : chord.Mask = 2 ? [5] : [5, 4]
            for , side in sides
                app.SideDown(side, true)
            buttons := chord.Buttons.Clone()
            if Mod(index, 2) = 0 {
                reversed := []
                loop buttons.Length
                    reversed.Push(buttons[buttons.Length - A_Index + 1])
                buttons := reversed
            }
            for , button in buttons {
                Check(app.ShouldBlock(button), "Recording owns fresh primary: " chord.ID)
                app.PrimaryDown(button, true)
                app.FakeNow += 10
            }
            if chord.Kind = "Double" {
                doubleCount += 1
                app.PrimaryUp(buttons[1])
                app.UpdateCapture(app.FakeNow)
                Check(app.Capture.Active && app.State.AnySide(), "First click waits with side held: " chord.ID)
                app.FakeNow += 100
                app.PrimaryDown(buttons[1], app.ShouldBlock(buttons[1]))
            } else
                chordCount += 1
            Check(app.Capture.Result.Trigger = chord.Trigger, "Actual handlers capture exact trigger: " chord.ID)
            for , side in sides
                app.SideUp(side)
            app.UpdateCapture(app.FakeNow)
            Check(app.Capture.Active, "Selection waits for remaining primary releases: " chord.ID)
            for , button in buttons {
                Check(app.BlockedPrimary(button), "Primary release remains owned after sides: " chord.ID)
                app.PrimaryUp(button)
            }
            app.UpdateCapture(app.FakeNow)
            Check(app.SelectedID() = chord.ID && app.EditID = chord.ID, "Capture opens exact editor: " chord.ID)
            Check(!app.Capture.Active && app.State.AllReleased(), "All released after selection: " chord.ID)
            Check(!DllCall("IsWindowVisible", "Ptr", app.Editor.Hwnd), "Captured editor remains hidden: " chord.ID)
            Check(FileRead(path) = before, "Capture never writes configuration: " chord.ID)
            Check(app.Dispatches = 0 && app.Replays = 0, "Assigned recording never dispatches: " chord.ID)
        }
        Check(chordCount = 21 && doubleCount = 4, "All 25 recording paths exercised")

        for , mixed in [false, true] {
            app.FakeNow := A_TickCount
            app.ToggleRecording()
            app.SideDown(4, true)
            app.PrimaryDown("LButton", app.ShouldBlock("LButton"))
            app.PrimaryUp("LButton")
            if mixed {
                app.FakeNow += 20
                app.PrimaryDown("RButton", app.ShouldBlock("RButton"))
                app.PrimaryUp("RButton")
                app.FakeNow += 20
            } else
                app.FakeNow += app.Config.ChordDelayMs
            app.PrimaryDown("LButton", app.ShouldBlock("LButton"))
            Check(app.Capture.Result.Trigger = "L", mixed ? "Mixed primary cancels double eligibility" : "Exact deadline expires double eligibility")
            app.PrimaryUp("LButton")
            app.SideUp(4)
            app.UpdateCapture(app.FakeNow)
            Check(app.SelectedID() = "4L" && app.EditID = "4L", "Failed double retains first singleton")
        }
        Check(FileRead(path) = before && app.Dispatches = 0 && app.Replays = 0 && app.State.AllReleased(),
            "Expanded recording checks leave settings, output and held state untouched")
        text := "PASS Record combination smoke / " checks " assertions`nHidden controls and isolated settings; no hooks, focus changes or synthetic input.`n"
        FileAppend(text, "*")
        report := root "\record-smoke-latest.log"
        if FileExist(report)
            FileDelete(report)
        FileAppend(text, report, "UTF-8")
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

class RecordingSmokeMapper extends MouseMapper {
    Dispatches := 0
    Replays := 0
    FakeNow := A_TickCount
    InputNow() => this.FakeNow
    CurrentTarget() => this.Window.Hwnd
    PointerContext() => {Root: this.Window.Hwnd, Capture: 0}
    CaptureCancelClick(button) => false
    StartMacro(id, target, mapping := unset) {
        this.Dispatches += 1
    }
    EmitSideReplay(id) {
        this.Replays += 1
    }
}
