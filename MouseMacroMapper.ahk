#Requires AutoHotkey v2.0
#SingleInstance Off
#Include lib\ChordState.ahk
#Include lib\CombinationCapture.ahk
#Include lib\MacroModel.ahk
#Include lib\BindingGestures.ahk
#Include lib\HeldKeyOutput.ahk
#Include lib\MapperKeyOutput.ahk
#Include lib\ProfileCycleHotkey.ahk
#Include lib\AppearanceSettings.ahk
#Include lib\WindowDrag.ahk
#Include lib\WindowDragOverlay.ahk
#Include lib\AlwaysOnTop.ahk
#Include lib\MouseDiagram.ahk
#Include tests\UiTests.ahk
#Include tests\RecordUiTests.ahk
#Include tests\BindingEditorTests.ahk
#Include tests\ChordRuntimeTests.ahk
#Include tests\ProfileRuntimeTests.ahk
#Include tests\NativeActionRuntimeTests.ahk
#Include tests\BindingRuntimeTests.ahk

if A_Args.Length && A_Args[1] = "--ui-test" {
    RunUiTests()
    ExitApp()
}
if A_Args.Length && A_Args[1] = "--record-test" {
    RunRecordUiTests()
    ExitApp()
}
if A_Args.Length && A_Args[1] = "--binding-test" {
    RunBindingRuntimeTests()
    ExitApp()
}

; A per-folder mutex prevents duplicate hooks without replacing another running script.
mapperMutex := DllCall("CreateMutexW", "Ptr", 0, "Int", 0,
    "Str", "Local\MouseMacroMapper-" StrReplace(StrLower(A_ScriptFullPath), "\", "|"), "Ptr")
if A_LastError = 183 {
    MsgBox("Mouse Macro Mapper is already running. Open it from its tray icon.", "Mouse Macro Mapper")
    ExitApp()
}
SetWorkingDir(A_ScriptDir)
SetKeyDelay(-1, -1)
SetMouseDelay(-1)
SendMode("Input")
global Mapper := MouseMapper(A_ScriptDir "\mappings.ini")
Persistent()

class MouseMapper {
    __New(path, testing := false) {
        this.Testing := testing
        this.Config := MapperSettings(path)
        this.State := ChordState()
        this.Capture := CombinationCapture()
        this.Gestures := BindingGestures()
        this.KeyOutput := MapperKeyOutput()
        this.Held := HeldKeyOutput(ObjBindMethod(this, "EmitHeldKey"), ObjBindMethod(this, "PhysicalKeyHeld"))
        this.DragOverlay := testing ? 0 : WindowDragOverlay(false, this.Config.OverlayColor, this.Config.OverlayTransparency)
        this.WindowDrag := testing ? WindowDrag() : WindowDrag(, this.DragOverlay)
        this.Pins := testing ? 0 : AlwaysOnTop()
        if IsObject(this.Pins)
            this.Pins.ConfigureOutline(this.Config.PinOutlineEnabled, this.Config.PinOutlineColor, this.Config.PinOutlineThickness)
        this.CleanupPending := false
        this.State.Paused := this.Config.Paused
        this.Running := false
        this.ActionQueue := []
        this.Message := "Select a combination and choose Edit mapping."
        this.Foreground := WinExist("A")
        this.SideContexts := Map()
        this.Drafts := Map()
        this.ProfileDrafts := Map(this.Config.ActiveProfileID, this.Drafts)
        this.EditorPresentation := ""
        this.CycleHotkey := testing ? 0 : ProfileCycleHotkey(ObjBindMethod(this, "CycleProfile", true))
        this.Selecting := false
        selectedChord := MacroModel.Chord(this.Config.Selected)
        this.SelectedMask := selectedChord.Mask
        this.SelectedTrigger := selectedChord.Trigger
        this.BuildGui()
        if testing {
            this.Refresh()
            return
        }
        this.RegisterHotkeys()
        try this.CycleHotkey.Configure(this.Config.CycleShortcut)
        catch Error as err
            this.Message := "Profile shortcut inactive: " err.Message
        ; Seed existing downs so startup never steals the end of an existing drag.
        for id, key in Map(4, "XButton1", 5, "XButton2")
            if DllCall("GetAsyncKeyState", "Int", GetKeyVK(key), "Short") & 0x8000
                this.State.SideDown(id, this.Foreground, false)
        for button, down in this.State.Primary
            if DllCall("GetAsyncKeyState", "Int", GetKeyVK(button), "Short") & 0x8000
                this.State.PrimaryDown(button)
        this.State.Cancel()
        this.ForegroundCallback := CallbackCreate(ObjBindMethod(this, "ForegroundChanged"), "", 7)
        this.ForegroundHook := DllCall("SetWinEventHook", "UInt", 3, "UInt", 3, "Ptr", 0,
            "Ptr", this.ForegroundCallback, "UInt", 0, "UInt", 0, "UInt", 0, "Ptr")
        this.TickFn := ObjBindMethod(this, "Tick")
        SetTimer(this.TickFn, 15)
        OnExit(ObjBindMethod(this, "Cleanup"))
        this.SetupTray()
        this.Refresh()
        this.Window.Show("w860 h779")
        if this.Config.LoadError != ""
            MsgBox("Mappings were not loaded; the mapper is paused. Your settings file is unchanged.`n`n"
                this.Config.LoadError, "Settings need attention", "Icon!")
    }

    BuildGui() {
        this.Window := Gui("-MaximizeBox", "Mouse Macro Mapper")
        this.Window.BackColor := "F3F6FA"
        this.Window.SetFont("s10", "Segoe UI")
        this.Window.SetFont("s23 w600 c17253E", "Segoe UI")
        this.Window.AddText("x24 y20 w760 h43", "Mouse Macro Mapper")
        this.Window.SetFont("s10 norm c57657B", "Segoe UI")
        this.Window.AddText("x26 y67 w640 h23", "Make every button your own. " MacroModel.IDs.Length " mappings, one familiar mouse.")
        this.Window.AddButton("x682 y57 w154 h32", "Window appearance").OnEvent("Click", ObjBindMethod(this, "OpenAppearance"))
        this.MouseViewButton := this.Window.AddRadio("x26 y103 w132 h26 Group", "Mouse View")
        this.ListViewButton := this.Window.AddRadio("x176 y103 w132 h26", "List View")
        this.MouseViewButton.OnEvent("Click", (*) => this.SetView("Mouse"))
        this.ListViewButton.OnEvent("Click", (*) => this.SetView("List"))
        this.RecordHint := this.Window.AddText("x332 y99 w246 h36 c57657B", "Record a trigger with your mouse.`nWorks while paused.")
        this.RecordButton := this.Window.AddButton("x592 y99 w244 h34", "Record combination")
        this.RecordButton.OnEvent("Click", ObjBindMethod(this, "ToggleRecording"))
        this.MouseControls := []
        this.Diagram := MouseDiagram(this.Window, 24, 139, 354, 362, ObjBindMethod(this, "DiagramClicked"))
        this.MouseControls.Push(this.Diagram.Control)
        this.MouseControls.Push(this.Window.AddText("x400 y151 w410 h24 c667791", "SELECTED COMBINATION"))
        this.Window.SetFont("s17 w600 c17253E", "Segoe UI")
        this.SelectionLabel := this.Window.AddText("x400 y183 w418 h58", "")
        this.MouseControls.Push(this.SelectionLabel)
        this.Window.SetFont("s10 norm c57657B", "Segoe UI")
        this.MappingName := this.Window.AddText("x400 y248 w412 h25", "")
        this.MouseControls.Push(this.MappingName)
        this.Window.SetFont("s10 c334968", "Consolas")
        this.Preview := this.Window.AddText("x400 y282 w412 h94", "")
        this.MouseControls.Push(this.Preview)
        this.Window.SetFont("s10 c17253E", "Segoe UI")
        this.MouseControls.Push(this.Window.AddText("x400 y385 w412 h22", "1. Select side modifiers"))
        this.Side4Box := this.Window.AddCheckbox("x400 y413 w150 h25", "Button &4")
        this.Side5Box := this.Window.AddCheckbox("x566 y413 w150 h25", "Button &5")
        this.Side4Box.OnEvent("Click", ObjBindMethod(this, "SideBoxesChanged"))
        this.Side5Box.OnEvent("Click", ObjBindMethod(this, "SideBoxesChanged"))
        this.MouseControls.Push(this.Side4Box, this.Side5Box)
        this.MouseControls.Push(this.Window.AddText("x400 y450 w412 h22", "2. Choose the click or held clicks"))
        this.PrimaryChoices := ["L", "R", "M", "LR", "LM", "RM", "LRM", "DL", "DR"]
        this.PrimaryChoice := this.Window.AddDropDownList("x400 y477 w412", ["Left click", "Right click", "Middle click", "Left + Right", "Left + Middle", "Right + Middle", "Left + Right + Middle", "Double Left (one side only)", "Double Right (one side only)"])
        this.PrimaryChoice.OnEvent("Change", (*) => this.DiagramClicked(this.PrimaryChoices[this.PrimaryChoice.Value]))
        this.MouseControls.Push(this.PrimaryChoice)
        this.MouseControls.Push(this.Window.AddText("x33 y503 w345 h22 Center c667791", "Toggle 4 / 5, then select a click region"))
        this.List := this.Window.AddListView("x24 y143 w812 h366 -Multi +Grid", ["Mouse combination", "Name", "Action / first step"])
        this.List.ModifyCol(1, 225)
        this.List.ModifyCol(2, 170)
        this.List.ModifyCol(3, 390)
        this.List.OnEvent("DoubleClick", ObjBindMethod(this, "EditSelected"))
        this.List.OnEvent("ItemSelect", ObjBindMethod(this, "ListSelectionChanged"))
        this.Window.AddButton("x24 y570 w150 h35 Default", "Edit mapping...").OnEvent("Click", ObjBindMethod(this, "EditSelected"))
        this.PauseButton := this.Window.AddButton("x190 y570 w155 h35", "Resume mappings")
        this.PauseButton.OnEvent("Click", ObjBindMethod(this, "TogglePause"))
        this.Window.AddButton("x362 y570 w144 h35", "Hide to tray").OnEvent("Click", (*) => this.Hide())
        this.Window.AddButton("x522 y570 w144 h35", "Usage guide").OnEvent("Click", ObjBindMethod(this, "ShowHelp"))
        this.Window.AddButton("x682 y570 w154 h35", "Exit mapper").OnEvent("Click", (*) => ExitApp())
        this.PreserveBox := this.Window.AddCheckbox("x24 y535 w476 h25", "Preserve unused side-button actions (replay on release)")
        this.PreserveBox.Value := this.Config.Preserve
        this.PreserveBox.OnEvent("Click", ObjBindMethod(this, "PreserveChanged"))
        this.Window.AddText("x506 y539 w127 h23", "Input window (ms)")
        this.ChordDelayEdit := this.Window.AddEdit("x634 y535 w66 h25 Number Limit4", this.Config.ChordDelayMs)
        this.Window.AddButton("x710 y533 w126 h29", "Apply wait").OnEvent("Click", ObjBindMethod(this, "ApplyChordDelay"))
        this.Status := this.Window.AddText("x24 y616 w812 h21 c334968", "")
        this.Window.AddText("x24 y639 w812 h19 c667791", "Ctrl+Alt+F12  pause / resume     |     Esc  cancel recording / macro     |     Close hides to tray")
        this.Window.AddText("x24 y666 w240 h20 c334968", "Active profile")
        this.ProfileChoice := this.Window.AddDropDownList("x24 y691 w250", [])
        this.ProfileChoice.OnEvent("Change", ObjBindMethod(this, "ProfileChoiceChanged"))
        for index, operation in ["New", "Duplicate", "Rename", "Remove"] {
            profileButton := this.Window.AddButton("x" (286 + (index - 1) * 140) " y687 w130 h30", operation)
            profileButton.OnEvent("Click", ObjBindMethod(this, "ProfilePrompt", operation))
        }
        this.Window.AddText("x24 y738 w142 h23", "Cycle shortcut")
        this.CycleShortcutEdit := this.Window.AddEdit("x169 y733 w310 h26", this.Config.CycleShortcut)
        this.Window.AddButton("x491 y731 w120 h30", "Apply shortcut").OnEvent("Click", ObjBindMethod(this, "ApplyCycleShortcut"))
        this.Window.AddText("x627 y733 w209 h36 c667791", "Example: Ctrl+Alt+F10`nLeave empty to disable.")
        this.Window.OnEvent("Close", (*) => this.Hide())
        this.Window.OnEvent("Escape", (*) => this.EscapePressed())
        this.Populate()
        this.UpdateSelection()
        this.SetView(this.Config.View, false)
        this.RefreshProfiles()
    }

    RefreshProfiles() {
        this.ProfileChoice.Delete()
        names := [], selected := 1
        for index, profile in this.Config.Profiles {
            names.Push(profile.Name)
            if profile.ID = this.Config.ActiveProfileID
                selected := index
        }
        this.ProfileChoice.Add(names)
        this.ProfileChoice.Choose(selected)
        this.Window.Title := "Mouse Macro Mapper - " this.Config.ActiveProfile().Name
        if this.HasOwnProp("Editor")
            this.Editor.Title := "Edit - " this.Config.ActiveProfile().Name " - " MacroModel.Chord(this.EditID).Label
    }

    OpenAppearance(*) {
        this.Cancel("Window appearance settings open.")
        if this.HasOwnProp("Appearance") {
            if !this.Testing
                this.Appearance.Window.Show()
            return
        }
        this.Appearance := MapperAppearance(this)
    }

    ApplyAppearance() {
        if this.HasOwnProp("DragOverlay") && IsObject(this.DragOverlay)
            this.DragOverlay.Configure(this.Config.OverlayColor, this.Config.OverlayTransparency)
        if this.HasOwnProp("Pins") && IsObject(this.Pins)
            this.Pins.ConfigureOutline(this.Config.PinOutlineEnabled, this.Config.PinOutlineColor, this.Config.PinOutlineThickness)
    }

    ProfileChoiceChanged(*) {
        if this.ProfileChoice.Value
            this.SwitchProfile(this.Config.Profiles[this.ProfileChoice.Value].ID)
    }

    StashProfileEditor() {
        if !this.HasOwnProp("Editor")
            return false
        this.Drafts[this.EditID] := this.EditorDraft()
        this.Editor.Destroy()
        this.DeleteProp("Editor")
        return true
    }

    SwitchProfile(id, notify := false) {
        if id = this.Config.ActiveProfileID
            return true
        this.Cancel("Switching profile; release held mouse buttons.")
        if this.CleanupPending {
            this.RefreshProfiles()
            return false
        }
        editorVisible := this.HasOwnProp("Editor") && DllCall("IsWindowVisible", "Ptr", this.Editor.Hwnd, "Int")
        wasEditing := this.StashProfileEditor()
        previous := this.Config.ActiveProfileID
        this.Config.SelectProfile(id)
        success := this.SavePreferences()
        if !success
            this.Config.SelectProfile(previous)
        if !this.ProfileDrafts.Has(this.Config.ActiveProfileID)
            this.ProfileDrafts[this.Config.ActiveProfileID] := Map()
        this.Drafts := this.ProfileDrafts[this.Config.ActiveProfileID]
        this.Populate()
        this.RefreshProfiles()
        if wasEditing {
            this.EditorPresentation := notify ? (editorVisible ? "NoActivate" : "Hidden") : ""
            try this.EditSelected()
            finally this.EditorPresentation := ""
        }
        this.Message := "Active profile: " this.Config.ActiveProfile().Name ". Release held buttons before starting."
        this.Refresh()
        if success && notify && !this.Testing
            TrayTip("Active profile: " this.Config.ActiveProfile().Name, "Mouse Macro Mapper")
        return success
    }

    CycleProfile(notify := false, *) {
        if this.Config.Profiles.Length < 2
            return false
        for index, profile in this.Config.Profiles
            if profile.ID = this.Config.ActiveProfileID
                return this.SwitchProfile(this.Config.Profiles[Mod(index, this.Config.Profiles.Length) + 1].ID, notify)
    }

    CreateProfile(name, duplicate := false) {
        try {
            id := this.Config.CreateProfile(name, duplicate ? this.Config.ActiveProfileID : "")
            if !this.SwitchProfile(id) {
                this.Config.DeleteProfile(id)
                this.RefreshProfiles()
                return false
            }
            return id
        } catch Error as err {
            this.Message := err.Message
            this.Refresh()
            return false
        }
    }

    RenameProfile(name) {
        profile := this.Config.ActiveProfile()
        previous := profile.Name
        try {
            this.Config.RenameProfile(profile.ID, name)
            success := this.SavePreferences()
            if !success
                profile.Name := previous
            this.RefreshProfiles()
            return success
        } catch Error as err {
            this.Message := err.Message
            this.Refresh()
            return false
        }
    }

    RemoveProfile() {
        if this.Config.Profiles.Length < 2 {
            this.Message := "Keep at least one profile."
            this.Refresh()
            return false
        }
        previous := this.Config.ActiveProfileID
        if !this.CycleProfile()
            return false
        profiles := this.Config.Profiles.Clone()
        this.Config.DeleteProfile(previous)
        if !this.SavePreferences() {
            this.Config.Profiles := profiles
            this.RefreshProfiles()
            return false
        }
        if this.ProfileDrafts.Has(previous)
            this.ProfileDrafts.Delete(previous)
        this.RefreshProfiles()
        return true
    }

    ProfilePrompt(operation, *) {
        if operation = "Remove" {
            if MsgBox("Remove profile '" this.Config.ActiveProfile().Name "' and its saved mappings and unsaved drafts?", "Remove profile", "YesNo Icon!") = "Yes"
                this.RemoveProfile()
            return
        }
        proposed := operation = "Rename" ? this.Config.ActiveProfile().Name : ""
        result := InputBox("Profile name", operation " profile", "w380 h135", proposed)
        if result.Result != "OK"
            return
        if operation = "Rename"
            this.RenameProfile(result.Value)
        else
            this.CreateProfile(result.Value, operation = "Duplicate")
    }

    ApplyCycleShortcut(*) {
        previous := this.Config.CycleShortcut
        try {
            parsed := ProfileCycleHotkey.Parse(this.CycleShortcutEdit.Value)
            shortcut := this.Testing ? parsed.Shortcut : this.CycleHotkey.Configure(this.CycleShortcutEdit.Value)
            this.Config.CycleShortcut := shortcut
            if !this.SavePreferences() {
                this.Config.CycleShortcut := previous
                if !this.Testing
                    this.CycleHotkey.Configure(previous)
                return false
            }
            this.CycleShortcutEdit.Value := shortcut
            this.Message := shortcut = "" ? "Profile shortcut disabled." : "Profile shortcut: " shortcut
            this.Refresh()
            return true
        } catch Error as err {
            this.Config.CycleShortcut := previous
            this.Message := "Shortcut unchanged: " err.Message
            this.Refresh()
            return false
        }
    }

    Populate() {
        this.Selecting := true
        this.List.Delete()
        for i, id in MacroModel.IDs {
            m := this.Config.Mappings[id]
            this.List.Add("", MacroModel.Labels[i], m.Name, this.BindingSummary(m))
        }
        this.Selecting := false
        this.UpdateSelection()
    }

    SelectedID() => MacroModel.ChordID(this.SelectedMask, this.SelectedTrigger)

    ActionLabel(action) => Map("Macro", "Keyboard macro", "MoveWindow", "Move window", "ResizeWindow", "Resize window", "ToggleTopmost", "Always on top")[action]

    BindingSummary(mapping) => MacroModel.Action(mapping) = "ToggleTopmost"
        ? MacroModel.Timing(mapping) ": Toggle always on top"
        : MacroModel.Action(mapping) != "Macro"
        ? this.ActionLabel(MacroModel.Action(mapping)) " while dragging"
        : (MacroModel.IsHold(mapping) ? "Hold" : MacroModel.Timing(mapping)) ": " MacroModel.Summary(mapping.Source)

    SelectedRow() {
        for i, id in MacroModel.IDs
            if id = this.SelectedID()
                return i
        return 0
    }

    SetView(view, persist := true) {
        this.Config.View := view
        this.MouseViewButton.Value := view = "Mouse"
        this.ListViewButton.Value := view = "List"
        for , control in this.MouseControls
            control.Visible := view = "Mouse"
        this.List.Visible := view = "List"
        if persist
            this.SavePreferences()
    }

    DiagramClicked(part, *) {
        if part != "4" && part != "5" && this.SelectedMask && !MacroModel.ChordID(this.SelectedMask, part) {
            this.Message := "Double clicks support Button 4 or Button 5 separately."
            this.UpdateSelection()
            this.Refresh()
            return
        }
        if part = "4" || part = "5"
            this.SelectedMask ^= part = "4" ? 1 : 2
        else
            this.SelectedTrigger := part
        this.UpdateSelection()
        this.SavePreferences()
        if part != "4" && part != "5"
            this.EditSelected()
    }

    SideBoxesChanged(*) {
        this.SelectedMask := (this.Side4Box.Value ? 1 : 0) | (this.Side5Box.Value ? 2 : 0)
        this.UpdateSelection()
        this.SavePreferences()
    }

    ListSelectionChanged(control, row, selected) {
        if this.Selecting || !selected || !row
            return
        id := MacroModel.IDs[row]
        if id = this.SelectedID()
            return
        chord := MacroModel.Chord(id)
        this.SelectedMask := chord.Mask
        this.SelectedTrigger := chord.Trigger
        this.UpdateSelection()
        this.SavePreferences()
    }

    UpdateSelection() {
        if this.SelectedMask && !this.SelectedID()
            this.SelectedTrigger := "L"
        for index, trigger in this.PrimaryChoices
            if trigger = this.SelectedTrigger
                this.PrimaryChoice.Choose(index)
        this.Side4Box.Value := !!(this.SelectedMask & 1)
        this.Side5Box.Value := !!(this.SelectedMask & 2)
        this.Diagram.SetSelection(this.SelectedMask, this.SelectedTrigger)
        row := this.SelectedRow()
        this.Selecting := true
        this.List.Modify(0, "-Select")
        if row
            this.List.Modify(row, "Select Focus Vis")
        this.Selecting := false
        if !row {
            this.SelectionLabel.Text := "Choose a side button"
            this.MappingName.Text := "Select button 4, button 5, or both."
            this.Preview.Text := "The mouse graphic only edits bindings.`nIt never executes a macro."
            return
        }
        id := MacroModel.IDs[row]
        this.Config.Selected := id
        mapping := this.Config.Mappings[id]
        this.SelectionLabel.Text := MacroModel.Labels[row]
        this.MappingName.Text := mapping.Name != "" ? mapping.Name : "No label yet"
        this.Preview.Text := MacroModel.Action(mapping) = "ToggleTopmost"
            ? "Always on top - toggle on " StrLower(MacroModel.Timing(mapping)) "`nRepeat the combination to unpin the window."
            : MacroModel.Action(mapping) != "Macro"
            ? this.ActionLabel(MacroModel.Action(mapping)) "`nHold side button(s), then click and drag.`nRelease any required button to stop."
            : mapping.Steps.Length ? (MacroModel.IsHold(mapping) ? "Hold until first release" : "Run on " StrLower(MacroModel.Timing(mapping))) "`n" SubStr(mapping.Source, 1, 150)
            : "Unassigned`nThe normal click will pass through."
    }

    SetupTray() {
        A_TrayMenu.Delete()
        A_TrayMenu.Add("Open mapper", (*) => this.Show())
        A_TrayMenu.Add("Pause / resume", ObjBindMethod(this, "TogglePause"))
        A_TrayMenu.Add()
        A_TrayMenu.Add("Exit mapper", (*) => ExitApp())
        A_TrayMenu.Default := "Open mapper"
        A_IconTip := "Mouse Macro Mapper"
    }

    Show() {
        this.Cancel("Editing - mappings are disabled in this app.")
        if !this.Testing
            this.Window.Show()
        if this.HasOwnProp("Editor") && !this.Testing
            this.Editor.Show()
    }

    Hide() {
        this.Cancel("Hidden; recording and pending output cancelled.")
        if this.HasOwnProp("Editor")
            this.Editor.Hide()
        this.Window.Hide()
    }

    Refresh() {
        this.PauseButton.Text := this.State.Paused ? "Resume mappings" : "Pause mappings"
        phase := this.Capture.Phase
        this.RecordButton.Text := this.Capture.Active ? "Cancel recording (Esc)" : "Record combination"
        this.RecordHint.Text := phase = "Arming" ? "Release all mouse buttons first.`nEsc cancels."
            : phase = "Listening" ? "Hold sides, then any L / R / M set.`n15 seconds. Esc cancels."
            : phase = "Matched" ? "Add held clicks, or release to finish.`nEsc cancels."
            : phase = "Draining" ? "Recording cancelled.`nRelease all mouse buttons."
            : "Record a trigger with your mouse.`nWorks while paused."
        mode := this.State.Paused ? "PAUSED - mouse works normally." : "ACTIVE - ready outside this editor."
        if this.Capture.Active
            mode := "RECORDING - macros disabled."
        this.Status.Text := mode "  " this.Message
        A_IconTip := "Mouse Macro Mapper - " this.Config.ActiveProfile().Name " - " (this.State.Paused ? "Paused" : "Active")
    }

    ToggleRecording(*) {
        Critical("On")
        if this.Capture.Active {
            this.Cancel("Recording cancelled.")
            this.UpdateCapture()
            return
        }
        this.CheckForeground()
        this.Cancel("Hold side 4, 5 or both, then hold any Left / Right / Middle set. Esc cancels.")
        ; Do not toggle pause or save settings. Existing downs retain their UP ownership.
        this.Capture.Begin(this.State.AllReleased(), A_TickCount)
        this.Refresh()
    }

    EscapePressed(*) {
        if this.HasCancelableInput() {
            this.Cancel("Recording / macro cancelled.")
            this.UpdateCapture()
        } else
            this.Hide()
    }

    UpdateCapture(now := A_TickCount) {
        Critical("On")
        if !this.Capture.Active
            return
        try {
            previous := this.Capture.Phase
            result := this.Capture.Advance(this.State.AllReleased(), now)
            if IsObject(result) {
                if result.Kind = "Selected" {
                    this.SelectedMask := result.Mask
                    this.SelectedTrigger := result.Trigger
                    this.UpdateSelection()
                    ; Opening on the timer, after every UP, prevents click-through.
                    ; EditSelected also caches any draft in the existing editor.
                    this.EditSelected()
                    this.EditFeedback.Text := "Combination recorded. Enter macro steps, then Save mapping."
                    this.Message := "Recorded " this.SelectedID() ". Edit the macro, then save."
                } else
                    this.Message := result.Reason
                this.Refresh()
            } else if previous != this.Capture.Phase
                this.Refresh()
        } catch Error as err {
            this.Cancel("Recording stopped: " err.Message)
        }
    }

    SavePreferences() {
        this.Config.Paused := this.State.Paused
        try this.Config.Save()
        catch Error as err {
            this.Cancel("Save failed; pending input cancelled.")
            this.State.SetPaused(true)
            this.Config.Paused := true
            this.Message := "Save failed; paused."
            this.Refresh()
            MsgBox(err.Message, "Could not save settings", "Icon!")
            return false
        }
        return true
    }

    TogglePause(*) {
        this.Cancel("Release held buttons before a new gesture.")
        this.State.SetPaused(!this.State.Paused)
        this.SavePreferences()
        this.Refresh()
    }

    PreserveChanged(*) {
        previous := this.Config.Preserve
        this.Config.Preserve := this.PreserveBox.Value
        this.Cancel("Side-button preference updated.")
        if !this.SavePreferences() {
            this.Config.Preserve := previous
            this.PreserveBox.Value := previous
        }
        this.Refresh()
    }

    ApplyChordDelay(*) {
        try delay := this.Config.ValidateChordDelay(this.ChordDelayEdit.Value)
        catch Error as err {
            this.Message := err.Message
            this.Refresh()
            return false
        }
        previous := this.Config.ChordDelayMs
        this.Cancel("Chord wait updated; release buttons for a new gesture.")
        this.Config.ChordDelayMs := delay
        if !this.SavePreferences() {
            this.Config.ChordDelayMs := previous
            this.ChordDelayEdit.Value := previous
            return false
        }
        this.Refresh()
        return true
    }

    EditSelected(*) {
        row := this.SelectedRow()
        if !row
            return
        this.Cancel("Editing - mappings are disabled in this app.")
        if this.HasOwnProp("Editor") {
            this.Drafts[this.EditID] := this.EditorDraft()
            this.EditID := MacroModel.IDs[row]
            mapping := this.Drafts.Has(this.EditID) ? this.Drafts[this.EditID] : this.Config.Mappings[this.EditID]
            this.Editor.Title := "Edit - " this.Config.ActiveProfile().Name " - " MacroModel.Labels[row]
            this.EditorLabel.Text := MacroModel.Labels[row]
            this.NameEdit.Value := mapping.Name
            this.SourceEdit.Value := mapping.Source
            this.LoadBindingOptions(mapping)
            this.EditFeedback.Text := this.Drafts.Has(this.EditID) ? "Unsaved draft restored. Save to apply it." : ""
            this.PresentEditor()
            return
        }
        this.EditID := MacroModel.IDs[row]
        mapping := this.Drafts.Has(this.EditID) ? this.Drafts[this.EditID] : this.Config.Mappings[this.EditID]
        this.Editor := Gui("+Owner" this.Window.Hwnd " -MinimizeBox -MaximizeBox", "Edit - " this.Config.ActiveProfile().Name " - " MacroModel.Labels[row])
        this.Editor.BackColor := "F3F6FA"
        this.Editor.SetFont("s10", "Segoe UI")
        this.EditorLabel := this.Editor.AddText("x20 y14 w580 h23", MacroModel.Labels[row])
        this.Editor.AddText("x20 y47 w100 h22", "Label (optional)")
        this.NameEdit := this.Editor.AddEdit("x132 y44 w447 h25 Limit80", mapping.Name)
        this.Editor.AddText("x20 y84 w105 h23", "Action")
        this.ActionChoice := this.Editor.AddDropDownList("x132 y80 w447", ["Keyboard macro", "Move window", "Resize window", "Always on top"])
        this.ActionChoice.OnEvent("Change", ObjBindMethod(this, "BindingOptionsChanged"))
        this.Editor.AddText("x20 y116 w565 h23", "Macro steps - retained when choosing a window action.")
        this.Editor.SetFont("s11", "Consolas")
        this.SourceEdit := this.Editor.AddEdit("x20 y142 w559 h167 Multi WantTab -Wrap Limit16000", mapping.Source)
        this.Editor.SetFont("s10", "Segoe UI")
        this.Editor.AddText("x20 y325 w110 h23", "Run once on")
        this.TimingChoice := this.Editor.AddDropDownList("x132 y321 w130", ["Press", "Release"])
        this.HoldBox := this.Editor.AddCheckbox("x282 y322 w297 h25", "Hold bound key / shortcut")
        this.TimingHint := this.Editor.AddText("x20 y357 w560 h58 c334968", "")
        this.TimingChoice.OnEvent("Change", ObjBindMethod(this, "BindingOptionsChanged"))
        this.HoldBox.OnEvent("Click", ObjBindMethod(this, "BindingOptionsChanged"))
        this.Editor.AddText("x20 y425 w562 h65", "Examples: key F8  |  key Ctrl+Shift+S  |  delay 150  |  text Hello`nHold requires exactly one key command. Text, delays and multiple steps use Run once.`nUse Plus for + in one-shot macros. No raw AutoHotkey code or down/up steps.")
        this.EditFeedback := this.Editor.AddText("x20 y497 w560 h44 cA03030", "")
        this.Editor.AddButton("x20 y548 w110 h31", "Validate").OnEvent("Click", ObjBindMethod(this, "ValidateEditor"))
        this.ExampleButton := this.Editor.AddButton("x142 y548 w145 h31", "Insert example")
        this.ExampleButton.OnEvent("Click", ObjBindMethod(this, "InsertExample"))
        this.LoadBindingOptions(mapping)
        this.Editor.AddButton("x337 y548 w115 h31 Default", "Save mapping").OnEvent("Click", ObjBindMethod(this, "SaveEditor"))
        this.Editor.AddButton("x464 y548 w115 h31", "Cancel").OnEvent("Click", (*) => this.CloseEditor())
        this.Editor.OnEvent("Close", (*) => this.CloseEditor())
        this.Editor.OnEvent("Escape", (*) => this.Capture.Active ? this.EscapePressed() : this.CloseEditor())
        if !this.Testing {
            this.Window.GetPos(&mainX, &mainY, &mainW)
            this.PresentEditor("w600 h595 x" Min(A_ScreenWidth - 610, mainX + mainW - 80) " y" Max(0, Min(A_ScreenHeight - 640, mainY + 75)))
        }
    }

    PresentEditor(options := "") {
        if this.Testing || this.EditorPresentation = "Hidden"
            return
        this.Editor.Show(options (this.EditorPresentation = "NoActivate" ? " NA" : ""))
        if this.EditorPresentation != "NoActivate" {
            if this.SourceEdit.Enabled
                this.SourceEdit.Focus()
            else
                this.ActionChoice.Focus()
        }
    }

    EditorDraft() => {Name: this.NameEdit.Value, Source: this.SourceEdit.Value,
        Timing: this.TimingChoice.Text, Hold: !!this.HoldBox.Value, Action: this.EditorAction()}

    EditorAction() => ["Macro", "MoveWindow", "ResizeWindow", "ToggleTopmost"][Max(1, this.ActionChoice.Value)]

    LoadBindingOptions(mapping) {
        this.ActionChoice.Choose(Map("Macro", 1, "MoveWindow", 2, "ResizeWindow", 3, "ToggleTopmost", 4)[MacroModel.Action(mapping)])
        this.TimingChoice.Choose(MacroModel.Timing(mapping) = "Release" ? 2 : 1)
        this.HoldBox.Value := MacroModel.IsHold(mapping)
        this.BindingOptionsChanged()
    }

    BindingOptionsChanged(*) {
        isMacro := this.EditorAction() = "Macro"
        this.SourceEdit.Enabled := isMacro
        this.HoldBox.Enabled := isMacro
        this.TimingChoice.Enabled := this.EditorAction() = "ToggleTopmost" || (isMacro && !this.HoldBox.Value)
        if this.HasOwnProp("ExampleButton")
            this.ExampleButton.Enabled := isMacro
        this.TimingHint.Text := this.EditorAction() = "ToggleTopmost"
            ? "Toggle the active window's always-on-top state on Press or Release.`nRepeat to unpin it. Hold and keyboard text are retained but unused.`nAlready-topmost windows owned by another app are left unchanged."
            : !isMacro
            ? "Hold side button(s), then click and drag inside the active window.`nStops on the first button release. Restore maximized windows first.`nKeyboard macro and timing options are retained but are not used."
            : this.HoldBox.Value
            ? "Key down when all required buttons are held; key up on the first release.`nRun-on timing is ignored; your choice is retained. One-shot macros are`nskipped while any key hold is active."
            : this.TimingChoice.Text = "Release"
                ? "Arm when all required buttons are held. Run once on the FIRST release`nof any required button (either side or the primary click)."
                : "Run once when the last required button is pressed. Either button order`nworks; a primary click begun first keeps its normal mouse release."
    }

    InsertExample(*) {
        if this.EditorAction() != "Macro"
            return
        ; Append without discarding anything the user has already typed.
        this.SourceEdit.Value .= (this.SourceEdit.Value = "" ? "" : "`r`n") "key Ctrl+C`r`ndelay 150`r`nkey Ctrl+V"
        if !this.Testing
            this.SourceEdit.Focus()
    }

    ValidateEditor(*) {
        try {
            steps := MacroModel.ValidateMapping(this.EditorDraft())
            this.EditFeedback.SetFont("c287240")
            this.EditFeedback.Text := this.EditorAction() = "ToggleTopmost"
                ? "Valid - toggles always on top using the selected Press / Release timing."
                : this.EditorAction() != "Macro"
                ? "Valid - window follows your mouse while the combination is held."
                : steps.Length ? "Valid - " steps.Length " step(s). Nothing was executed." : "Unassigned - the normal mouse click will pass through."
            return true
        } catch Error as err {
            this.EditFeedback.SetFont("cA03030")
            this.EditFeedback.Text := err.Message
            return false
        }
    }

    SaveEditor(*) {
        this.Cancel("Mapping edit; pending input cancelled.")
        if !this.ValidateEditor()
            return
        old := this.Config.Mappings[this.EditID]
        mapping := this.EditorDraft()
        mapping.Name := Trim(mapping.Name)
        mapping.Steps := MacroModel.ValidateMapping(mapping)
        this.Config.Mappings[this.EditID] := mapping
        try this.Config.Save()
        catch Error as err {
            this.Config.Mappings[this.EditID] := old
            this.EditFeedback.SetFont("cA03030")
            this.EditFeedback.Text := "Not saved: " err.Message
            return
        }
        this.Message := "Mapping saved."
        if this.Drafts.Has(this.EditID)
            this.Drafts.Delete(this.EditID)
        this.Populate()
        this.CloseEditor()
    }

    CloseEditor() {
        if this.Capture.Active
            this.Cancel("Recording cancelled when the editor closed.")
        if this.Drafts.Has(this.EditID)
            this.Drafts.Delete(this.EditID)
        this.Editor.Destroy()
        this.DeleteProp("Editor")
        if !this.Testing
            this.Window.Show()
        this.Refresh()
    }

    ShowHelp(*) {
        this.Cancel("Usage guide open.")
        MsgBox("Choose side 4, 5 or both, then choose any held Left / Right / Middle set in the dropdown. All 21 sets are available. Double Left and Double Right are also available with side 4 or 5 separately. List View contains the same 25 entries.`n`n"
            "Choose Action, optional label and Press / Release timing. Keyboard macro accepts key F8, key Ctrl+C, delay 150 and text Hello. Hold requires one key command. Save mapping applies only this edit; the drawing and editor never execute it.`n`n"
            "Input window (ms), default 200, is shared by chord growth and doubles. Apply wait saves 0-1000 ms; 0 disables doubles. Only configured larger possibilities delay a smaller action. Adding held buttons within the wait replaces the pending smaller action; adding them after it fired can run the larger too. A finite macro finishes before its queued larger action. Releases never start subsets.`n`n"
            "A double requires the same side held continuously and two matching clicks, first DOWN to second DOWN strictly inside the window. Only the double runs. At or after expiry, the clicks are singles. Keep all matched buttons held for a held chord; their first required release ends Hold or runs Release. Quick pending Holds are balanced down/up.`n`n"
            "Record combination works while paused: hold sides, then the primary set (or a supported double), and release all buttons to open its editor. It records the trigger only. Esc cancels; keep the mapper focused. Recording never runs mappings.`n`n"
            "Move / Resize window: focus a restored window, hold the sides first, then click and drag. Preview shows intended geometry even if the app lags. First required release stops. Always on top toggles a persistent pin; repeat to unpin. Existing external pins stay unchanged. These actions need no PowerToys. Window appearance sets preview tint/transparency and pin outline color/thickness.`n`n"
            "Profiles keep independent mappings and unsaved drafts. New creates blank mappings; Duplicate copies saved mappings. Cycle shortcut is unset until you apply one, then each physical press advances once and wraps. Switching profiles cancels pending old output, releases keys and waits for held mouse buttons to clear. Pins remain until unpinned or mapper exit.`n`n"
            "Resume mappings and focus your target app. Assigned larger chords reserve their participating clicks. Unused sides can replay on release if Preserve is enabled. Ctrl+Alt+F12 pauses/resumes; Esc cancels pending output. Focus changes cancel remaining input. Close hides to tray; save wanted drafts and Exit mapper before relaunching updates. Drafts are lost on exit. See README.md for details.", "Mouse Macro Mapper - usage", "Iconi")
    }

    IsOwn(target) {
        if !target
            return true
        try return WinGetPID("ahk_id " target) = ProcessExist()
        catch
            return true
    }

    PointerContext() {
        MouseGetPos(, , &underPointer)
        root := underPointer ? DllCall("GetAncestor", "Ptr", underPointer, "UInt", 2, "Ptr") : 0
        info := Buffer(A_PtrSize = 8 ? 72 : 48, 0)
        NumPut("UInt", info.Size, info)
        capture := DllCall("GetGUIThreadInfo", "UInt", 0, "Ptr", info)
            ? NumGet(info, 8 + 2 * A_PtrSize, "Ptr") : 0
        return {Root: root, Capture: capture}
    }

    RegisterHotkeys() {
        for id, key in Map(4, "XButton1", 5, "XButton2") {
            HotIf((*) => this.Capture.Active || !this.State.Paused)
            Hotkey("*" key, ObjBindMethod(this, "SideDown", id, true))
            HotIf()
            Hotkey("~*" key, ObjBindMethod(this, "SideDown", id, false))
            HotIf(ObjBindMethod(this, "CapturedSide", id))
            Hotkey("*" key " Up", ObjBindMethod(this, "SideUp", id))
            HotIf()
            Hotkey("~*" key " Up", ObjBindMethod(this, "SideUp", id))
        }
        for button, down in this.State.Primary {
            HotIf(ObjBindMethod(this, "ShouldBlock", button))
            Hotkey("*" button, ObjBindMethod(this, "PrimaryDown", button, true))
            HotIf()
            Hotkey("~*" button, ObjBindMethod(this, "PrimaryDown", button, false))
            HotIf(ObjBindMethod(this, "BlockedPrimary", button))
            Hotkey("*" button " Up", ObjBindMethod(this, "PrimaryUp", button))
            HotIf()
            Hotkey("~*" button " Up", ObjBindMethod(this, "PrimaryUp", button))
        }
        HotIf((*) => this.HasCancelableInput())
        ; Another script can receive our level-1 held output. Our own keyboard
        ; controls must ignore that level so a held binding cannot cancel itself.
        Hotkey("*Esc", ObjBindMethod(this, "EscapePressed"), "I" MapperKeyOutput.ControlInputLevel)
        HotIf()
        Hotkey("$^!F12", ObjBindMethod(this, "TogglePause"), "I" MapperKeyOutput.ControlInputLevel)
    }

    CapturedSide(id, *) => this.State.Sides[id].Captured
    BlockedPrimary(button, *) => this.State.Blocked[button]
    HasCancelableInput() => this.Running || this.ActionQueue.Length || this.Capture.Active || this.Held.Active || this.WindowDrag.Active || this.Gestures.PendingRelease()

    MappingID(mask, button) => MacroModel.ChordID(mask, button)

    InputNow() => DllCall("Kernel32\GetTickCount64", "UInt64")

    AllBindingButtonsBlocked(binding) {
        for , button in binding.Buttons
            if !this.State.Blocked[button]
                return false
        return true
    }

    CurrentTarget() => WinExist("A")

    CaptureCancelClick(button) {
        ; Only the recorder's own Cancel control can receive a fresh native click.
        ; Every other fresh primary DOWN is swallowed while listening.
        if button != "LButton" || this.State.AnySide()
            || (this.Capture.Phase != "Listening" && this.Capture.Phase != "Arming")
            || this.CurrentTarget() != this.Window.Hwnd
            return false
        MouseGetPos(, , , &control, 2)
        return control = this.RecordButton.Hwnd
    }

    ShouldBlock(button, *) {
        if this.State.Blocked[button]
            return true
        if this.Capture.Active
            return this.Capture.ShouldBlockPrimary(this.State.Primary[button], this.State.AnySide())
                && !this.CaptureCancelClick(button)
        target := this.CurrentTarget()
        if this.State.Primary[button] || this.IsOwn(target)
            return false
        mask := this.State.Mask(target)
        if !mask || this.PointerContext().Root != target
            return false
        ; Reserve participating clicks of an assigned larger chord before it is
        ; complete, so no native click leaks while waiting for the other buttons.
        for , chord in MacroModel.Chords {
            if chord.Mask != mask || !MacroModel.Assigned(this.Config.Mappings[chord.ID])
                continue
            if chord.Kind = "Double" && this.Config.ChordDelayMs = 0
                continue
            for , required in chord.Buttons
                if required = button
                    return true
        }
        return false
    }

    SideDown(id, captured, *) {
        Critical("On")
        this.CheckForeground()
        target := this.CurrentTarget()
        fresh := !this.State.Sides[id].Down
        if !fresh
            return
        this.SideContexts[id] := this.PointerContext()
        this.State.SideDown(id, target, captured)
        if this.Capture.Active || this.IsOwn(target) || this.State.Inhibited
            this.State.UseSides()
        if !this.Capture.Active
            this.BindingDown()
    }

    SideUp(id, *) {
        Critical("On")
        this.CheckForeground()
        target := this.CurrentTarget()
        this.Capture.ObserveUp(id)
        this.ExecuteBindingActions(this.Gestures.Up(id, this.InputNow()))
        replay := this.State.SideUp(id, target, this.Config.Preserve)
        if this.Capture.Active
            replay := false
        current := this.PointerContext()
        if !this.SideContexts.Has(id)
            replay := false
        else {
            original := this.SideContexts[id]
            replay := replay && original.Root = current.Root && original.Capture = current.Capture
            this.SideContexts.Delete(id)
        }
        if replay && !this.IsOwn(target) && this.CurrentTarget() = target
            this.EmitSideReplay(id)
    }

    EmitSideReplay(id) {
        if this.Testing
            throw Error("Test mode cannot send native mouse input.")
        SendLevel(0)
        SendInput(id = 4 ? "{Blind}{XButton1}" : "{Blind}{XButton2}")
    }

    PrimaryDown(button, blocked, *) {
        Critical("On")
        this.CheckForeground()
        target := this.CurrentTarget()
        recording := this.Capture.Active
        mask := recording ? CombinationCapture.HeldMask(this.State) : this.State.Mask(target)
        fresh := this.State.PrimaryDown(button, blocked)
        if recording {
            if blocked && this.Capture.ObservePrimary(mask, button, fresh, this.State.Primary, this.InputNow(), this.Config.ChordDelayMs)
                this.Refresh()
            return
        }
        ; Passthrough clicks still interrupt a pending double sequence. The
        ; original native DOWN/UP ownership stays in State.Blocked.
        if fresh && (blocked || mask)
            this.BindingDown(button)
    }

    PrimaryUp(button, *) {
        Critical("On")
        this.CheckForeground()
        this.Capture.ObserveUp(button)
        this.ExecuteBindingActions(this.Gestures.Up(button, this.InputNow()))
        this.State.PrimaryUp(button)
    }

    BindingDown(changedButton := "") {
        target := this.CurrentTarget()
        if this.Capture.Active || this.CleanupPending || this.IsOwn(target)
            || this.PointerContext().Root != target {
            if this.Gestures.Active.Count
                this.Cancel("Mouse context changed; pending binding cancelled.")
            return
        }
        mask := this.State.Mask(target)
        if !mask
            return
        try {
            actions := this.Gestures.Down(mask, this.State.Primary, this.Config.Mappings, changedButton, this.InputNow(), this.Config.ChordDelayMs)
            for , binding in this.Gestures.Active {
                if !binding.HasOwnProp("Target") {
                    binding.Target := target
                    binding.Epoch := this.State.Epoch
                }
            }
            if this.Gestures.Active.Count
                this.State.UseSides()
            this.ExecuteBindingActions(actions)
        } catch Error as err {
            this.Cancel("Binding stopped: " err.Message)
        }
    }

    ExecuteBindingActions(actions) {
        try {
            for , action in actions {
                binding := action.Binding
                if action.Kind = "EndWindow" {
                    if this.WindowDrag.End(binding.Token)
                        this.Message := "Window drag stopped."
                    continue
                }
                if action.Kind = "EndHold" {
                    this.Held.Release(binding.Token)
                    this.Message := "Held key released."
                    continue
                }
                if this.Capture.Active || this.CleanupPending || this.State.Paused
                    || binding.Epoch != this.State.Epoch || binding.Target != this.CurrentTarget()
                    || this.IsOwn(binding.Target)
                    continue
                if this.Running && (binding.Buttons.Length > 1 || (binding.HasOwnProp("IsDouble") && binding.IsDouble)) {
                    this.ActionQueue.Push(action)
                    this.Message := "Larger combination queued after the current macro."
                    continue
                }
                if action.Kind = "ToggleTopmost" {
                    if this.Testing && (!this.HasOwnProp("Pins") || !IsObject(this.Pins))
                        throw Error("Test pin actions require a mock manager.")
                    this.Message := this.Pins.Toggle(binding.Target)
                } else if action.Kind = "BeginWindow" {
                    if this.WindowDrag.Active {
                        this.Message := "Finish the current window drag first."
                        continue
                    }
                    if !this.AllBindingButtonsBlocked(binding) {
                        this.Message := "For window dragging, hold side button(s) before the primary click."
                        continue
                    }
                    if !this.WindowDrag.Begin(binding.Token, binding.Action, binding.Target)
                        continue
                    this.Running := false
                    this.ReleaseHeldKeys()
                    if this.CleanupPending
                        throw Error("Window drag cancelled while keyboard release is pending.")
                    this.Message := this.ActionLabel(binding.Action) ": drag, then release a required button. Esc stops."
                } else if this.WindowDrag.Active {
                    this.Message := "Finish the window drag before starting another action."
                    continue
                } else if action.Kind = "BeginHold" {
                    if this.KeyboardModifiersHeld() {
                        this.Message := "Release physical keyboard modifiers before holding a binding."
                        continue
                    }
                    ; A one-shot Send could release a held shortcut's keys. Holds take
                    ; priority and one-shot macros are skipped while any hold is active.
                    this.Running := false
                    keys := MacroModel.HoldKeys(binding.Mapping.Steps)
                    this.Message := this.Held.Acquire(binding.Token, keys)
                        ? "Holding " binding.ID ". First mouse release or Esc releases keys."
                        : "Release the bound keyboard key before trying this hold."
                } else if !this.Held.Active && !this.Running
                    this.StartMacro(binding.ID, binding.Target, binding.Mapping)
                else
                    this.Message := "One-shot skipped while another macro or key hold is active."
            }
            if actions.Length
                this.Refresh()
        } catch Error as err {
            this.Cancel("Binding output stopped: " err.Message)
        }
    }

    PhysicalKeyHeld(key) => GetKeyState(key, "P")

    DrainActionQueue() {
        while !this.Running && this.ActionQueue.Length {
            if this.Held.Active || this.WindowDrag.Active || this.CleanupPending
                break
            action := this.ActionQueue.RemoveAt(1)
            if action.Kind != "Tap" && action.Kind != "ToggleTopmost" {
                stillHeld := false
                for , binding in this.Gestures.Active
                    if binding.Token = action.Binding.Token
                        stillHeld := true
                if !stillHeld
                    continue
            }
            this.ExecuteBindingActions([action])
        }
    }

    EmitHeldKey(key, down) {
        if this.Testing
            throw Error("Test mode cannot send keyboard input.")
        this.KeyOutput.SendHeldKey(key, down)
    }

    ReleaseHeldKeys() {
        wasPending := this.CleanupPending
        try {
            this.Held.ReleaseAll()
            this.CleanupPending := false
            if wasPending {
                this.Message := "Key release cleanup completed. Release mouse buttons before retrying."
                this.Refresh()
            }
        } catch Error as err {
            this.CleanupPending := true
            this.Message := "Key release failed; retrying cleanup: " err.Message
        }
    }

    KeyboardModifiersHeld() {
        for , key in ["LControl", "RControl", "LAlt", "RAlt", "LShift", "RShift", "LWin", "RWin"]
            if GetKeyState(key, "P")
                return true
        return false
    }

    StartMacro(id, target, mapping := unset) {
        if this.Capture.Active || this.Held.Active || this.WindowDrag.Active || this.CleanupPending
            return
        if this.KeyboardModifiersHeld() {
            this.Message := "Release keyboard modifiers before triggering a macro."
            this.Refresh()
            return
        }
        this.Steps := IsSet(mapping) ? mapping.Steps : this.Config.Mappings[id].Steps
        this.StepIndex := 1
        this.TextOffset := 1
        this.Due := A_TickCount
        this.MacroTarget := target
        this.MacroEpoch := this.State.Epoch
        this.Running := true
        this.Message := "Running " id ". Esc cancels."
        this.Refresh()
    }

    Tick() {
        this.CheckForeground()
        if IsObject(this.Pins) {
            try this.Pins.Tick()
            catch Error as err
                this.Message := "Pin outline update failed: " err.Message
        }
        if this.CleanupPending
            this.ReleaseHeldKeys()
        this.UpdateCapture()
        if !this.Capture.Active && !this.State.Paused && !this.CleanupPending
            this.ExecuteBindingActions(this.Gestures.Advance(this.InputNow()))
        if !this.Running
            this.DrainActionQueue()
        if this.WindowDrag.Active {
            try this.WindowDrag.Tick()
            catch Error as err
                this.Cancel("Window drag stopped: " err.Message)
        }
        ; Invalidate a pending standalone action even if the pointer later returns.
        if this.State.AnySide() {
            context := this.PointerContext()
            for id, side in this.State.Sides {
                if side.Down && side.Captured && !side.Used && this.SideContexts.Has(id) {
                    original := this.SideContexts[id]
                    if context.Root != original.Root || context.Capture != original.Capture
                        this.State.UseSides()
                }
            }
        }
        if !this.Running || A_TickCount < this.Due
            return
        if this.State.Paused || this.State.Epoch != this.MacroEpoch
            || this.CurrentTarget() != this.MacroTarget || this.IsOwn(this.MacroTarget) {
            this.Cancel("Macro cancelled after focus or mode change.")
            return
        }
        if this.StepIndex > this.Steps.Length {
            this.Running := false
            this.Message := "Macro completed."
            this.Refresh()
            return
        }
        if this.KeyboardModifiersHeld() {
            this.Cancel("Macro cancelled: a keyboard modifier is held.")
            return
        }
        step := this.Steps[this.StepIndex]
        try {
            if step.Kind = "delay"
                this.Due := A_TickCount + step.Value
            else {
                ; Keep complete keyboard taps atomic with respect to this script's threads.
                Critical("On")
                if this.CurrentTarget() != this.MacroTarget || this.State.Epoch != this.MacroEpoch
                    return
                SendLevel(0)
                if step.Kind = "key"
                    this.EmitMacroKey(step.Value)
                else {
                    ; Small text batches let focus changes / Escape cancel long text steps.
                    length := 16
                    last := SubStr(step.Value, this.TextOffset + length - 1, 1)
                    if last != "" && Ord(last) >= 0xD800 && Ord(last) <= 0xDBFF
                        length += 1
                    chunk := SubStr(step.Value, this.TextOffset, length)
                    this.EmitMacroText(chunk)
                    this.TextOffset += StrLen(chunk)
                    if this.TextOffset <= StrLen(step.Value)
                        return
                    this.TextOffset := 1
                }
            }
            this.StepIndex += 1
        } catch Error as err {
            this.Cancel("Macro stopped: " err.Message)
        } finally {
            Critical("Off")
        }
    }

    EmitMacroKey(value) {
        if this.Testing
            throw Error("Test mode cannot send keyboard input.")
        SendInput(value)
    }

    EmitMacroText(value) {
        if this.Testing
            throw Error("Test mode cannot send keyboard input.")
        SendText(value)
    }

    CheckForeground() {
        target := this.CurrentTarget()
        if target != this.Foreground {
            this.Foreground := target
            this.Cancel("Focus changed; pending output cancelled.")
        }
    }

    ForegroundChanged(hook, event, hwnd, object, child, thread, time) {
        if hwnd && hwnd != this.Foreground {
            this.Foreground := hwnd
            this.Cancel("Focus changed; pending output cancelled.")
        }
    }

    Cancel(message := "Cancelled.") {
        this.Running := false
        this.ActionQueue := []
        try this.WindowDrag.Cancel()
        catch Error as err
            message .= " Overlay cleanup: " err.Message
        this.Gestures.Cancel()
        if this.Capture.Active
            this.Capture.Cancel(message)
        this.State.Cancel()
        this.Message := message
        this.ReleaseHeldKeys()
        this.Refresh()
    }

    Cleanup(*) {
        this.Running := false
        this.ActionQueue := []
        this.Gestures.Cancel()
        this.ReleaseHeldKeys()
        this.Capture.Cancel("Mapper exiting.")
        this.State.Cancel()
        ; Each external-resource cleanup gets a chance even if another fails.
        try this.WindowDrag.Dispose()
        if IsObject(this.Pins)
            try this.Pins.Dispose()
        if this.HasOwnProp("Appearance")
            try this.Appearance.Close()
        if IsObject(this.CycleHotkey)
            try this.CycleHotkey.Dispose()
        this.Diagram.Dispose()
        if this.HasOwnProp("ForegroundHook") && this.ForegroundHook
            DllCall("UnhookWinEvent", "Ptr", this.ForegroundHook)
        if this.HasOwnProp("ForegroundCallback")
            CallbackFree(this.ForegroundCallback)
    }
}
