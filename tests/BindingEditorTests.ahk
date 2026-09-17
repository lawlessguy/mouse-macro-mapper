; Included by the hidden runtime smoke runner. No auto-execution, hooks, or input.
; The caller provides a Testing=true mapper with an isolated settings path.
RunBindingEditorChecks(app, check) {
    if !app.Testing
        throw Error("Binding editor checks require a hidden test mapper.")
    app.SelectedMask := 1
    app.SelectedTrigger := "L"
    app.UpdateSelection()
    app.EditSelected()
    app.ActionChoice.Choose(1)
    app.NameEdit.Value := "Held shortcut draft"
    app.SourceEdit.Value := "key Ctrl+Shift+C"
    app.TimingChoice.Choose(2)
    app.HoldBox.Value := true
    app.BindingOptionsChanged()
    check.Call(!app.TimingChoice.Enabled, "Hold disables one-shot timing")
    draft := app.EditorDraft()
    check.Call(draft.Hold && draft.Timing = "Release", "Hold retains the stored Release choice")
    app.HoldBox.Value := false
    app.BindingOptionsChanged()
    check.Call(app.TimingChoice.Enabled && app.TimingChoice.Text = "Release", "Disabling Hold restores the retained timing")
    app.HoldBox.Value := true
    app.BindingOptionsChanged()
    check.Call(!app.TimingChoice.Enabled && app.TimingChoice.Text = "Release", "Re-enabling Hold retains timing")

    app.SetView("List")
    app.SetView("Mouse")
    draft := app.EditorDraft()
    check.Call(draft.Hold && draft.Timing = "Release" && draft.Source = "key Ctrl+Shift+C", "View changes preserve editor binding options and source")
    app.SelectedMask := 2
    app.SelectedTrigger := "R"
    app.UpdateSelection()
    app.EditSelected()
    check.Call(app.Drafts.Has("4L") && app.Drafts["4L"].Hold && app.Drafts["4L"].Timing = "Release", "Switching slots caches binding options")
    app.NameEdit.Value := "Other draft"
    app.SourceEdit.Value := "key Enter"
    app.TimingChoice.Choose(1)
    app.HoldBox.Value := false
    app.BindingOptionsChanged()
    app.SelectedMask := 1
    app.SelectedTrigger := "L"
    app.UpdateSelection()
    app.EditSelected()
    draft := app.EditorDraft()
    check.Call(draft.Name = "Held shortcut draft" && draft.Source = "key Ctrl+Shift+C" && draft.Hold && draft.Timing = "Release", "Returning to a slot restores the complete draft")
    check.Call(!app.TimingChoice.Enabled, "Restored hold draft disables timing")
    check.Call(!DllCall("IsWindowVisible", "Ptr", app.Window.Hwnd) && !DllCall("IsWindowVisible", "Ptr", app.Editor.Hwnd), "Editor checks keep both native windows hidden")

    app.SaveEditor()
    check.Call(!app.HasOwnProp("Editor"), "Valid hold saves and closes the editor")
    saved := app.Config.Mappings["4L"]
    check.Call(saved.Hold && saved.Timing = "Release" && saved.Source = "key Ctrl+Shift+C", "Saved mapping retains independent binding options")
    reloaded := MapperSettings(app.Config.Path)
    check.Call(reloaded.LoadError = "" && reloaded.Mappings["4L"].Hold && reloaded.Mappings["4L"].Timing = "Release", "Saved options reload from isolated settings")
    check.Call(app.Drafts.Has("5R") && app.Drafts["5R"].Name = "Other draft" && !app.Drafts["5R"].Hold, "Saving one slot preserves another unsaved draft")

    app.EditSelected()
    app.SourceEdit.Value := "text hello"
    app.SaveEditor()
    check.Call(app.HasOwnProp("Editor") && app.Config.Mappings["4L"].Source = saved.Source && app.EditFeedback.Text != "", "Text Hold is rejected without replacing the saved mapping")
    app.SourceEdit.Value := "key Enter`nkey Escape"
    app.SaveEditor()
    check.Call(app.HasOwnProp("Editor") && app.Config.Mappings["4L"].Source = saved.Source, "Multiple-command Hold is rejected with editor open")
    app.HoldBox.Value := false
    app.BindingOptionsChanged()
    app.SaveEditor()
    check.Call(!app.HasOwnProp("Editor") && !app.Config.Mappings["4L"].Hold && app.Config.Mappings["4L"].Timing = "Release" && app.Config.Mappings["4L"].Steps.Length = 2, "Disabling Hold permits a normal multi-step Release macro")
    reloaded := MapperSettings(app.Config.Path)
    check.Call(reloaded.LoadError = "" && !reloaded.Mappings["4L"].Hold && reloaded.Mappings["4L"].Timing = "Release" && reloaded.Mappings["4L"].Steps.Length = 2, "Updated normal macro and timing reload together")

    app.EditSelected()
    retainedSource := "invalid retained native draft"
    app.SourceEdit.Value := retainedSource
    app.TimingChoice.Choose(2)
    app.HoldBox.Value := true
    app.ActionChoice.Choose(2)
    app.BindingOptionsChanged()
    check.Call(!app.SourceEdit.Enabled && !app.TimingChoice.Enabled && !app.HoldBox.Enabled && !app.ExampleButton.Enabled, "Move window disables inactive macro controls")
    draft := app.EditorDraft()
    check.Call(draft.Action = "MoveWindow" && draft.Source = retainedSource && draft.Hold && draft.Timing = "Release", "Move window retains inactive macro text and options")
    app.SetView("List")
    app.SetView("Mouse")
    check.Call(app.EditorDraft().Action = "MoveWindow" && app.SourceEdit.Value = retainedSource, "View switching preserves the native-action draft")
    app.SelectedMask := 2
    app.SelectedTrigger := "R"
    app.UpdateSelection()
    app.EditSelected()
    app.ActionChoice.Choose(3)
    app.BindingOptionsChanged()
    check.Call(app.EditorDraft().Action = "ResizeWindow" && !app.SourceEdit.Enabled && !app.TimingChoice.Enabled && !app.HoldBox.Enabled && app.SourceEdit.Value = "key Enter", "Resize window disables controls while retaining its other draft")
    app.SelectedMask := 1
    app.SelectedTrigger := "L"
    app.UpdateSelection()
    app.EditSelected()
    draft := app.EditorDraft()
    check.Call(draft.Action = "MoveWindow" && draft.Source = retainedSource && draft.Hold && draft.Timing = "Release" && app.Drafts["5R"].Action = "ResizeWindow", "Slot switching preserves both native-action drafts and inactive options")
    app.SaveEditor()
    check.Call(!app.HasOwnProp("Editor") && app.Config.Mappings["4L"].Action = "MoveWindow" && app.Config.Mappings["4L"].Steps.Length = 0, "Move window saves independently of invalid inactive macro text")
    check.Call(InStr(FileRead(app.Config.Path), "Version=2`r`n"), "Saving a native action writes isolated version-2 settings")
    reloaded := MapperSettings(app.Config.Path)
    check.Call(reloaded.LoadError = "" && reloaded.Mappings["4L"].Source = retainedSource && reloaded.Mappings["4L"].Hold && reloaded.Mappings["4L"].Timing = "Release", "Native save/reload preserves inactive text and options")
    check.Call(InStr(app.Preview.Text, "Move window") && !InStr(app.Preview.Text, retainedSource), "Move preview describes the native action instead of inactive macro text")
    app.SelectedMask := 2
    app.SelectedTrigger := "R"
    app.UpdateSelection()
    app.EditSelected()
    check.Call(app.EditorDraft().Action = "ResizeWindow" && app.SourceEdit.Value = "key Enter" && !app.SourceEdit.Enabled, "Resize draft restores after saving another slot")
    app.SaveEditor()
    reloaded := MapperSettings(app.Config.Path)
    check.Call(!app.HasOwnProp("Editor") && reloaded.LoadError = "" && reloaded.Mappings["4L"].Action = "MoveWindow" && reloaded.Mappings["5R"].Action = "ResizeWindow", "Both native actions save and reload together")
    check.Call(InStr(app.Preview.Text, "Resize window"), "Resize preview describes the native action")
    app.SelectedMask := 1
    app.SelectedTrigger := "L"
    app.UpdateSelection()
    app.EditSelected()
    app.ActionChoice.Choose(1)
    app.BindingOptionsChanged()
    check.Call(app.SourceEdit.Enabled && app.HoldBox.Enabled && !app.TimingChoice.Enabled && app.SourceEdit.Value = retainedSource && app.HoldBox.Value && app.TimingChoice.Text = "Release", "Returning to Macro restores editing and retained Hold/timing semantics")
    check.Call(!app.ValidateEditor() && app.EditFeedback.Text != "", "Returning to Macro restores source validation")
    app.SaveEditor()
    check.Call(app.HasOwnProp("Editor") && app.Config.Mappings["4L"].Action = "MoveWindow", "Invalid reactivated macro keeps the saved native action and editor open")
    app.SourceEdit.Value := "key Win"
    check.Call(app.ValidateEditor(), "A corrected standalone modifier is valid after returning to Macro")
    app.SaveEditor()
    check.Call(!app.HasOwnProp("Editor") && app.Config.Mappings["4L"].Action = "Macro" && app.Config.Mappings["4L"].Hold && app.Config.Mappings["4L"].Timing = "Release", "Corrected macro saves with its retained binding options")
    check.Call(!DllCall("IsWindowVisible", "Ptr", app.Window.Hwnd), "Native editor checks leave the main window hidden")
}
