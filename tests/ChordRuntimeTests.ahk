; Real runtime dispatch with a deterministic clock, hidden GUI and mocked output.
RunChordRuntimeChecks(app, check) {
    Reset() {
        app.ResetFixture()
        app.Config.ChordDelayMs := 200
        for , id in MacroModel.IDs
            app.Bind(id, "")
    }
    for , chord in MacroModel.Chords {
        if chord.Kind != "Chord"
            continue
        Reset()
        app.Bind(chord.ID, "key Enter")
        if chord.Mask & 1
            app.SideDown(4, true)
        if chord.Mask & 2
            app.SideDown(5, true)
        loop chord.Buttons.Length
            app.Press(chord.Buttons[chord.Buttons.Length - A_Index + 1])
        check.Call(app.Running, "All held buttons complete native handler mapping " chord.ID)
        app.Tick()
        app.Tick()
        for , button in chord.Buttons
            app.PrimaryUp(button)
        if chord.Mask & 1
            app.SideUp(4)
        if chord.Mask & 2
            app.SideUp(5)
        check.Call(app.CountOutput("Tap") = 1 && !app.Replays && app.State.AllReleased(),
            "Exactly one action and clean release for " chord.ID)
    }

    Reset()
    app.Bind("4L", "key A")
    app.Bind("4LR", "key B")
    app.Bind("4LRM", "key C")
    app.SideDown(4, true)
    app.Press("LButton")
    check.Call(!app.Running && app.HasCancelableInput(), "Configured superset defers singleton and permits Escape")
    app.FakeNow += 100
    app.Press("RButton")
    check.Call(!app.Running && !app.Outputs.Length, "Pair suppresses pending singleton but waits for configured triple")
    app.FakeNow += 100
    app.Press("MButton")
    app.Tick()
    check.Call(app.CountOutput("Tap") = 1 && app.Outputs[1].Key = "{c}", "Triple wins multi-stage chord grace")
    app.PrimaryUp("MButton")
    app.PrimaryUp("RButton")
    app.PrimaryUp("LButton")
    app.SideUp(4)
    app.FakeNow += 1000
    app.Tick()
    check.Call(app.CountOutput("Tap") = 1, "Unwinding and expired timers cannot fire suppressed subsets")

    Reset()
    app.Bind("5L", "key A`ndelay 500`nkey B")
    app.Bind("5LR", "key C")
    app.SideDown(5, true)
    app.Press("LButton")
    app.FakeNow += 200
    app.Tick()
    app.Tick()
    app.Press("RButton")
    check.Call(app.ActionQueue.Length = 1 && app.CountOutput("Tap") = 1,
        "Larger completion after expiry queues without truncating smaller sequence")
    app.Due := 0
    app.Tick()
    app.Tick()
    app.Tick()
    check.Call(app.CountOutput("Tap") = 3 && app.Outputs[2].Key = "{b}" && app.Outputs[3].Key = "{c}",
        "Smaller finite macro finishes before additive larger action")

    Reset()
    app.Bind("4L", "key A")
    app.Bind("4LR", "key B")
    app.SideDown(4, true)
    app.Press("LButton")
    app.FakeNow += 20
    app.PrimaryUp("LButton")
    app.Tick()
    check.Call(app.CountOutput("Tap") = 1 && app.Outputs[1].Key = "{a}",
        "Quick singleton Press flushes at release when no double is assigned")
    app.SideUp(4)

    for , stop in ["Pause", "Record", "Editor", "Focus", "Delay"] {
        Reset()
        app.Bind("4L", "key A")
        app.Bind("4LR", "key B")
        app.SideDown(4, true)
        app.Press("LButton")
        switch stop {
            case "Pause": app.TogglePause()
            case "Record": app.ToggleRecording()
            case "Editor": app.EditSelected()
            case "Focus":
                app.FakeTarget := 202
                app.CheckForeground()
            case "Delay":
                app.ChordDelayEdit.Value := 150
                app.ApplyChordDelay()
        }
        app.FakeNow += 1000
        app.Tick()
        check.Call(!app.Outputs.Length && !app.Gestures.PendingRelease() && app.BlockedPrimary("LButton"),
            stop " cancels delayed actions without losing mouse-up ownership")
        if stop = "Editor"
            app.CloseEditor()
    }
    Reset()
    app.ChordDelayEdit.Value := "1001"
    check.Call(!app.ApplyChordDelay() && app.Config.ChordDelayMs = 200, "Invalid wait cannot change configuration")
    app.ChordDelayEdit.Value := "0"
    check.Call(app.ApplyChordDelay() && MapperSettings(app.Config.Path).ChordDelayMs = 0, "Zero wait saves and reloads")
    RunDoubleRuntimeChecks(app, check)
    Reset()
}

RunDoubleRuntimeChecks(app, check) {
    Reset() {
        app.ResetFixture()
        app.Config.ChordDelayMs := 200
        for , id in MacroModel.IDs
            app.Bind(id, "")
    }
    Pump(count := 4) {
        loop count {
            ; Deterministically finish fixture macros without sleeping or input.
            app.Due := 0
            app.Tick()
        }
    }
    Taps(key) {
        total := 0
        for , output in app.Outputs
            if output.Kind = "Tap" && output.Key = key
                total += 1
        return total
    }

    for , id in ["4DL", "4DR", "5DL", "5DR"] {
        Reset()
        chord := MacroModel.Chord(id)
        button := chord.Buttons[1]
        side := chord.Mask = 1 ? 4 : 5
        app.Bind(MacroModel.ChordID(chord.Mask, button), "key A")
        app.Bind(id, "key B")
        app.SideDown(side, true)
        app.Press(button)
        candidate := app.Gestures.Active[button]
        check.Call(app.BlockedPrimary(button) && !app.Outputs.Length && !app.Running,
            id " first native handler down is owned and silent")
        check.Call(candidate.Target = app.FakeTarget && candidate.Epoch = app.State.Epoch,
            id " deferred candidate receives target and epoch metadata")
        app.FakeNow += 30
        app.PrimaryUp(button)
        check.Call(!app.BlockedPrimary(button) && app.Gestures.Active[button] = candidate
            && !app.Running && !app.Outputs.Length, id " first up retains candidate without dispatch")
        app.FakeNow += 70
        app.Press(button)
        check.Call(app.Running && app.BlockedPrimary(button), id " second down dispatches recognized double")
        Pump()
        app.PrimaryUp(button)
        app.SideUp(side)
        app.FakeNow += 500
        Pump()
        check.Call(Taps("{b}") = 1 && Taps("{a}") = 0 && !app.Replays && app.State.AllReleased(),
            id " replaces both singles and drains mouse ownership without replay")
    }

    for , secondOffset in [199, 200, 201] {
        Reset()
        app.Bind("4L", "key A")
        app.Bind("4DL", "key B")
        app.SideDown(4, true)
        firstDown := app.FakeNow
        app.Press("LButton")
        app.FakeNow += 30
        app.PrimaryUp("LButton")
        app.FakeNow := firstDown + secondOffset
        app.Press("LButton")
        Pump()
        app.FakeNow += 10
        app.PrimaryUp("LButton")
        app.FakeNow += 200
        Pump()
        check.Call(secondOffset < 200 ? Taps("{b}") = 1 && Taps("{a}") = 0
            : Taps("{b}") = 0 && Taps("{a}") = 2,
            "Second DOWN at " secondOffset " ms respects strict first-DOWN deadline")
        app.SideUp(4)
    }

    Reset()
    app.Bind("5R", "key A", "Release")
    app.Bind("5DR", "key B", "Release")
    app.SideDown(5, true)
    app.Press("RButton")
    app.FakeNow += 30
    app.PrimaryUp("RButton")
    Pump()
    check.Call(!app.Running && !app.Outputs.Length && app.Gestures.PendingRelease(),
        "Release singleton does not fire on first UP while double recognition is possible")
    app.FakeNow += 70
    app.Press("RButton")
    check.Call(!app.Running && !app.Outputs.Length, "Recognized Release double waits for its second UP")
    app.PrimaryUp("RButton")
    Pump()
    check.Call(Taps("{b}") = 1 && Taps("{a}") = 0, "Only recognized double Release dispatches")
    app.SideUp(5)

    Reset()
    app.Bind("4L", "key Ctrl+C", "Press", true)
    app.Bind("4DL", "key B")
    app.SideDown(4, true)
    app.Press("LButton")
    app.FakeNow += 20
    app.PrimaryUp("LButton")
    check.Call(!app.Held.Active && !app.Outputs.Length, "Quick held singleton waits through first double UP")
    app.FakeNow += 180
    Pump()
    check.Call(app.CountOutput("Down") = 2 && app.CountOutput("Up") = 2
        && !app.Held.Active && !app.CleanupPending && !app.Running,
        "Quick held singleton expiry emits balanced shortcut down/up through real dispatcher")
    app.SideUp(4)

    Reset()
    app.Bind("4L", "key A")
    app.Bind("4DL", "key B")
    app.SideDown(4, true)
    app.Press("LButton")
    app.FakeNow += 20
    app.PrimaryUp("LButton")
    app.FakeNow += 10
    app.Press("RButton")
    Pump()
    app.PrimaryUp("RButton")
    app.FakeNow += 20
    app.Press("LButton")
    check.Call(Taps("{a}") = 1 && Taps("{b}") = 0 && !app.Running,
        "Other-primary DOWN interrupts a pending double before a later same-button click")
    app.PrimaryUp("LButton")
    app.FakeNow += 200
    Pump()
    check.Call(Taps("{a}") = 2 && Taps("{b}") = 0, "Interrupted clicks resolve as independent legitimate singles")
    app.SideUp(4)

    Reset()
    app.Bind("4L", "key A")
    app.Bind("4DL", "key B")
    app.Bind("4LR", "key C", "Press", true)
    app.SideDown(4, true)
    app.Press("LButton")
    app.FakeNow += 50
    app.Press("RButton")
    check.Call(app.Held.Active && app.CountOutput("Down") = 1 && !app.CountOutput("Tap"),
        "Larger held chord consumes deferred singleton and double recognition")
    app.PrimaryUp("RButton")
    app.FakeNow += 400
    Pump()
    check.Call(!app.Held.Active && app.CountOutput("Up") = 1 && !app.CountOutput("Tap"),
        "Larger held release leaves no late singleton or double action")
    app.PrimaryUp("LButton")
    app.SideUp(4)

    Reset()
    app.Bind("4M", "key A`ndelay 500`nkey B")
    app.Bind("4L", "key D")
    app.Bind("4DL", "key C")
    app.SideDown(4, true)
    app.Press("MButton")
    app.Tick()
    app.Tick()
    app.PrimaryUp("MButton")
    app.Press("LButton")
    app.FakeNow += 20
    app.PrimaryUp("LButton")
    app.FakeNow += 80
    app.Press("LButton")
    check.Call(app.ActionQueue.Length = 1 && app.ActionQueue[1].Binding.IsDouble
        && app.ActionQueue[1].Binding.Target = app.FakeTarget
        && app.ActionQueue[1].Binding.Epoch = app.State.Epoch,
        "Queued double retains target and epoch from its native handler completion")
    app.PrimaryUp("LButton")
    Pump(8)
    check.Call(Taps("{a}") = 1 && Taps("{b}") = 1 && Taps("{c}") = 1 && !Taps("{d}")
        && !app.ActionQueue.Length, "Queued double survives latch removal and follows the complete earlier macro")
    app.SideUp(4)

    Reset()
    app.Bind("4L", "key A")
    app.Bind("4DL", "key B")
    app.Config.ChordDelayMs := 0
    app.SideDown(4, true)
    app.Press("LButton")
    Pump()
    app.PrimaryUp("LButton")
    app.FakeNow += 30
    app.Press("LButton")
    Pump()
    app.PrimaryUp("LButton")
    check.Call(Taps("{a}") = 2 && !Taps("{b}"), "Zero delay executes ordinary singles and disables double recognition")
    app.SideUp(4)
    Reset()
}
