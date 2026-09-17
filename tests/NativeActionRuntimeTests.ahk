RunNativeActionRuntimeChecks(app, check) {
    Reset() {
        app.ResetFixture()
        app.Config.ChordDelayMs := 200
        for , id in MacroModel.IDs
            app.Bind(id, "")
    }
    Reset()
    app.Pins := NativeRuntimePins()
    app.Bind("4LR", "inactive source", "Release", true, "ToggleTopmost")
    app.SideDown(4, true)
    app.Press("LButton")
    app.Press("RButton")
    check.Call(!app.Pins.Pinned && !app.Held.Active && !app.WindowDrag.Active,
        "Always-on-top Release arms without treating retained Hold as a drag")
    app.PrimaryUp("LButton")
    check.Call(app.Pins.Pinned && app.Pins.Toggles = 1 && !app.Outputs.Length,
        "First required UP toggles persistent pin exactly once")
    app.PrimaryUp("RButton")
    app.SideUp(4)
    app.Cancel()
    check.Call(app.Pins.Pinned && app.Pins.Toggles = 1, "Release and general cancellation do not undo persistent pin")
    other := app.CreateProfile("Pin profile")
    check.Call(other && app.Pins.Pinned, "Profile switching leaves persistent pin ownership alone")
    Reset()
    app.Bind("5L", "key A")
    app.Bind("5DL", "", "Press", true, "ToggleTopmost")
    app.SideDown(5, true)
    app.Press("LButton")
    app.PrimaryUp("LButton")
    app.FakeNow += 100
    app.Press("LButton")
    check.Call(!app.Pins.Pinned && app.Pins.Toggles = 2 && !app.Outputs.Length,
        "Recognized double toggles off while replacing both single clicks")
    app.PrimaryUp("LButton")
    app.SideUp(5)

    Reset()
    app.SelectedMask := 1
    app.SelectedTrigger := "L"
    app.UpdateSelection()
    app.EditSelected()
    app.SourceEdit.Value := "saved inactive steps"
    app.HoldBox.Value := true
    app.TimingChoice.Choose(2)
    app.ActionChoice.Choose(4)
    app.BindingOptionsChanged()
    check.Call(app.EditorAction() = "ToggleTopmost" && app.TimingChoice.Enabled
        && !app.SourceEdit.Enabled && !app.HoldBox.Enabled, "Topmost editor keeps Press/Release active and disables retained keyboard options")
    check.Call(app.ValidateEditor() && InStr(app.EditFeedback.Text, "always on top"), "Validation describes a discrete topmost toggle")
    app.SaveEditor()
    loaded := MapperSettings(app.Config.Path)
    check.Call(loaded.Mappings["4L"].Action = "ToggleTopmost" && loaded.Mappings["4L"].Hold
        && loaded.Mappings["4L"].Timing = "Release" && loaded.Mappings["4L"].Source = "saved inactive steps",
        "Topmost editor saves inactive keyboard options and active timing")

    Reset()
    app.Bind("4L", "key A`ndelay 500`nkey B")
    app.Bind("4LR", "key Ctrl+C", "Press", true)
    app.Bind("4LM", "key D")
    app.SideDown(4, true)
    app.Press("LButton")
    app.FakeNow += 200
    app.Tick()
    app.Tick()
    app.Press("RButton")
    app.Press("MButton")
    check.Call(app.ActionQueue.Length = 2, "Concurrent larger held/tap actions queue behind the finite macro")
    app.Due := 0
    app.Tick()
    app.Tick()
    check.Call(!app.Running && app.HasCancelableInput(), "Escape remains eligible between macro completion and queued work")
    app.Tick()
    check.Call(app.Held.Active && app.ActionQueue.Length = 1 && app.CountOutput("Tap") = 2,
        "Queued hold blocks later finite action without discarding it")
    app.PrimaryUp("RButton")
    app.Tick()
    check.Call(!app.Held.Active && !app.ActionQueue.Length && app.CountOutput("Tap") = 3,
        "Queued finite action runs after the hold releases")

    Reset()
    app.Config.ChordDelayMs := 0
    app.Bind("4L", "key A")
    app.Bind("4LR", "key B")
    app.SideDown(4, true)
    app.Press("LButton")
    app.Press("RButton")
    app.Tick()
    app.Tick()
    check.Call(!app.Running && app.ActionQueue.Length = 1 && app.HasCancelableInput(), "Queued finite action alone keeps cancellation enabled")
    app.EscapePressed()
    app.Tick()
    check.Call(!app.ActionQueue.Length && app.CountOutput("Tap") = 1, "Escape discards pending finite queue")
    Reset()
}

class NativeRuntimePins {
    Pinned := false
    Toggles := 0
    Toggle(hwnd) {
        this.Pinned := !this.Pinned
        this.Toggles += 1
        return "Mock pin toggled."
    }
    Tick() {
    }
    ConfigureOutline(enabled, color, thickness) {
    }
    Dispose() {
        this.Pinned := false
    }
}
