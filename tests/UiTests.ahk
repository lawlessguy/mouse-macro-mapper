; Included by the application. Run MouseMacroMapper.ahk --ui-test.
; Calls the real handlers against hidden controls: no hooks, Send, or focus changes.
RunUiTests() {
    checks := 0
    root := A_ScriptDir "\tests\artifacts"
    DirCreate(root)
    path := root "\ui-test-" ProcessExist() ".ini"
    report := root "\ui-latest.log"
    lines := "Hidden native UI handler tests / AHK " A_AhkVersion "`n"
    app := 0
    try {
        app := MouseMapper(path, true)
        Check(condition, message) {
            checks += 1
            if !condition
                throw Error(message)
        }
        Check(!DllCall("IsWindowVisible", "Ptr", app.Window.Hwnd), "Test window must remain hidden")
        Check(!app.HasOwnProp("ForegroundHook"), "Test must not install input/focus hooks")
        for part, point in Map("4", [84,149], "5", [77,211], "L", [145,114], "R", [246,114], "M", [193,123])
            Check(app.Diagram.HitTest(point*) = part, "Accurate diagram hit region: " part)
        Check(app.Diagram.HitTest(5,5) = "", "Blank diagram space is inert")

        Check(app.List.GetCount() = 25 && MacroModel.Chords.Length = 25, "List exposes all 25 mappings")
        for index, chord in MacroModel.Chords {
            mask := chord.Mask, trigger := chord.Trigger, id := chord.ID
            app.SelectedMask := mask
                app.DiagramClicked(trigger)
                Check(app.SelectedID() = id && app.EditID = id, "Correct editor: " id)
                Check(app.List.GetText(index, 1) = chord.Label, "Exact list descriptor: " id)
                Check(app.Diagram.Mask = mask && app.Diagram.Trigger = trigger, "Highlight matches: " id)
                Check(!DllCall("IsWindowVisible", "Ptr", app.Editor.Hwnd), "Editor remains hidden")
                app.NameEdit.Value := "Test " id
                app.SourceEdit.Value := "key Ctrl+Shift+S`r`ndelay 25`r`ntext Test " id
                originalHwnd := app.Editor.Hwnd
                app.SetView("List")
                Check(app.List.Visible && !app.Diagram.Control.Visible, "List view controls: " id)
                Check(app.SelectedID() = id && app.List.GetNext() = app.SelectedRow(), "List shares selection: " id)
                Check(app.Editor.Hwnd = originalHwnd && InStr(app.SourceEdit.Value, "Test " id), "Draft survives Mouse to List: " id)
                app.SetView("Mouse")
                Check(!app.List.Visible && app.Diagram.Control.Visible, "Mouse view controls: " id)
                Check(app.Editor.Hwnd = originalHwnd && InStr(app.SourceEdit.Value, "Test " id), "Draft survives List to Mouse: " id)
                app.SaveEditor()
                Check(!app.HasOwnProp("Editor"), "Successful save closes editor: " id)
                saved := MapperSettings(path)
                Check(saved.LoadError = "" && saved.Mappings[id].Name = "Test " id, "Persist mapping label: " id)
                Check(saved.Mappings[id].Steps.Length = 3, "Persist all macro steps: " id)
                Check(saved.Selected = id && saved.View = "Mouse", "Persist selection/view: " id)
                app.EditSelected()
                Check(InStr(app.SourceEdit.Value, "Test " id), "Reopen saved mapping: " id)
                app.CloseEditor()
        }
        lines .= "PASS all 25 mouse/editor selections, exact list rows, two-way view switching, saving and reopening`n"

        app.SelectedMask := 3
        app.DiagramClicked("L")
        app.CloseEditor()
        for , invalidTrigger in ["DL", "DR"] {
            app.DiagramClicked(invalidTrigger)
            Check(app.SelectedID() = "45L" && !app.HasOwnProp("Editor"), "Both-side double is refused: " invalidTrigger)
            Check(InStr(app.Message, "separately"), "Unsupported double selection explains allowed sides")
        }

        app.SelectedMask := 3
        app.DiagramClicked("L")
        app.SourceEdit.Value := "text Unsaved draft retained"
        app.DiagramClicked("R")
        Check(app.EditID = "45R", "Switch exact combination while editing")
        app.DiagramClicked("L")
        Check(app.SourceEdit.Value = "text Unsaved draft retained", "Restore per-combination draft")
        Check(InStr(app.EditFeedback.Text, "Unsaved draft"), "Draft state is explicit")
        app.SetView("List")
        app.ListSelectionChanged(app.List, 2, true)
        Check(app.SelectedID() = "4R", "List row selects exact same model")
        app.EditSelected()
        Check(app.EditID = "4R", "List opens correct editor")
        app.SetView("Mouse")
        app.SelectedMask := 3
        app.DiagramClicked("L")
        Check(app.SourceEdit.Value = "text Unsaved draft retained", "Draft survives view and combination changes")
        before := app.Config.Mappings["45L"].Source
        app.SourceEdit.Value := "key {Ctrl down}"
        app.SaveEditor()
        Check(app.HasOwnProp("Editor") && app.Config.Mappings["45L"].Source = before, "Invalid edit cannot replace saved macro")
        app.CloseEditor()
        app.EditSelected()
        Check(app.SourceEdit.Value = before, "Cancel discards only unsaved edit")
        app.SourceEdit.Value := ""
        app.SaveEditor()
        Check(app.Config.Mappings["45L"].Steps.Length = 0, "Empty editor unassigns mapping")
        lines .= "PASS unsaved drafts, modeless view/selection changes, invalid-save rejection, cancel and clear`n"

        app.SelectedMask := 0
        app.DiagramClicked("L")
        Check(!app.HasOwnProp("Editor"), "No-side selection does not open invalid mapping")
        app.DiagramClicked("4")
        Check(app.SelectedMask = 1 && app.Side4Box.Value && !app.Side5Box.Value, "Diagram side4 toggles checkbox")
        app.DiagramClicked("5")
        Check(app.SelectedMask = 3 && app.Side4Box.Value && app.Side5Box.Value, "Diagram both-side selection")
        app.Side4Box.Value := 0
        app.SideBoxesChanged()
        Check(app.SelectedMask = 2, "Accessible checkbox changes diagram selection")
        app.PreserveBox.Value := 0
        app.PreserveChanged()
        Check(!MapperSettings(path).Preserve, "Preserve off saved")
        app.PreserveBox.Value := 1
        app.PreserveChanged()
        Check(MapperSettings(path).Preserve, "Preserve on saved")
        app.TogglePause()
        Check(!app.State.Paused && !MapperSettings(path).Paused, "Resume handler persisted")
        app.TogglePause()
        Check(app.State.Paused && MapperSettings(path).Paused, "Pause handler persisted")
        app.SetView("List")
        Check(MapperSettings(path).View = "List", "List view survives relaunch")
        Check(!app.Running, "Diagram and editor controls never execute a macro")
        lines .= "PASS side toggles, accessible equivalents, unassigned state, preferences and no macro execution`n"
        lines .= "RESULT PASS / " checks " assertions`nNo visible windows, input hooks, or synthetic input were used.`n"
        FileAppend(lines, "*")
        if FileExist(report)
            FileDelete(report)
        FileAppend(lines, report, "UTF-8")
    } catch Error as err {
        lines .= "RESULT FAIL / " checks " assertions / " err.Message " at " err.File ":" err.Line "`n"
        FileAppend(lines, "*")
        if FileExist(report)
            FileDelete(report)
        FileAppend(lines, report, "UTF-8")
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
