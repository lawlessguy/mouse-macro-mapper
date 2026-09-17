RunProfileRuntimeChecks(app, check) {
    Reset() {
        app.ResetFixture()
        for , id in MacroModel.IDs
            app.Bind(id, "")
    }
    Reset()
    app.Bind("4L", "key Ctrl+C", "Press", true)
    app.SideDown(4, true)
    app.Press("LButton")
    check.Call(!app.CycleProfile() && app.Held.Active, "Cycling one profile is a no-op during a hold")
    Reset()
    defaultID := app.Config.ActiveProfileID
    app.Bind("4L", "key A")
    app.SelectedMask := 1
    app.SelectedTrigger := "L"
    app.UpdateSelection()
    app.EditSelected()
    app.SourceEdit.Value := "key Z"
    otherID := app.CreateProfile("Second profile", true)
    check.Call(otherID && app.Config.ActiveProfileID = otherID && app.Config.Mappings["4L"].Source = "key A",
        "Duplicate copies saved mappings into the newly selected profile")
    check.Call(app.ProfileDrafts[defaultID]["4L"].Source = "key Z" && app.SourceEdit.Value = "key A",
        "Profile switch stashes old draft without silently saving it")
    app.SourceEdit.Value := "key Q"
    app.SwitchProfile(defaultID)
    check.Call(app.SourceEdit.Value = "key Z" && InStr(app.Editor.Title, "Default"), "Return restores profile-specific draft and editor identity")
    app.SwitchProfile(otherID)
    check.Call(app.SourceEdit.Value = "key Q" && app.Config.Mappings["4L"].Source = "key A", "Second profile has its own unsaved draft")
    app.CloseEditor()
    check.Call(app.RenameProfile("Gaming") && app.ProfileChoice.Text = "Gaming", "Renaming updates visible active profile")
    check.Call(!app.CreateProfile("gaming"), "Duplicate profile name is rejected without switching")
    app.Bind("4L", "key B")
    app.Config.Save()
    loaded := MapperSettings(app.Config.Path)
    check.Call(loaded.ActiveProfileID = otherID && loaded.Mappings["4L"].Source = "key B"
        && loaded.FindProfile(defaultID).Mappings["4L"].Source = "key A", "Profile selection and independent saved mappings reload")
    app.CycleProfile()
    check.Call(app.Config.ActiveProfileID = defaultID, "Cycle wraps in displayed order")

    Reset()
    app.Bind("4L", "key A")
    app.Bind("4LR", "key C")
    app.SideDown(4, true)
    app.Press("LButton")
    app.SwitchProfile(otherID)
    app.FakeNow += 1000
    app.Tick()
    check.Call(!app.Outputs.Length && app.BlockedPrimary("LButton") && app.State.Inhibited,
        "Profile change cancels old delayed action and keeps old mouse-up ownership")
    app.PrimaryUp("LButton")
    app.SideUp(4)
    app.SideDown(4, true)
    app.Press("LButton")
    app.Tick()
    check.Call(app.CountOutput("Tap") = 1 && app.Outputs[1].Key = "{b}", "Fresh gesture uses new profile after original buttons clear")
    Reset()
    app.Bind("4L", "key Ctrl+C", "Press", true)
    app.SideDown(4, true)
    app.Press("LButton")
    app.SwitchProfile(defaultID)
    check.Call(!app.Held.Active && app.CountOutput("Up") = 2 && app.BlockedPrimary("LButton"),
        "Profile switch releases old held keyboard output without losing mouse ownership")

    app.ResetFixture()
    app.CycleShortcutEdit.Value := "Ctrl+Alt+F10"
    check.Call(app.ApplyCycleShortcut() && MapperSettings(app.Config.Path).CycleShortcut = "Ctrl+Alt+F10",
        "Cycle shortcut persists without registering hooks in test mode")
    app.CycleShortcutEdit.Value := "Ctrl+Alt+F12"
    check.Call(!app.ApplyCycleShortcut() && app.Config.CycleShortcut = "Ctrl+Alt+F10", "Reserved shortcut keeps previous configured binding")
    app.CycleShortcutEdit.Value := ""
    check.Call(app.ApplyCycleShortcut() && app.Config.CycleShortcut = "", "Empty shortcut disables cycling key")
    check.Call(app.RemoveProfile() && app.Config.ActiveProfileID = otherID && app.Config.Profiles.Length = 1,
        "Removing active profile safely selects next and retains one profile")
    check.Call(!app.RemoveProfile() && app.Config.Profiles.Length = 1, "Last profile cannot be removed")
    check.Call(!DllCall("IsWindowVisible", "Ptr", app.Window.Hwnd) && !app.HasOwnProp("ForegroundHook"),
        "Profile checks remain hidden with no input hooks")
    app.OpenAppearance()
    check.Call(!DllCall("IsWindowVisible", "Ptr", app.Appearance.Window.Hwnd), "Appearance editor stays hidden in fixture")
    originalColor := app.Config.OverlayColor
    app.Appearance.OverlayColor := "12ABEF"
    app.Appearance.TransparencyEdit.Value := "101"
    check.Call(!app.Appearance.Save() && app.Config.OverlayColor = originalColor, "Invalid transparency cannot partly change appearance")
    app.Appearance.TransparencyEdit.Value := "60"
    app.Appearance.ThicknessEdit.Value := "0"
    check.Call(!app.Appearance.Save(), "Zero outline thickness rejected")
    app.Appearance.ThicknessEdit.Value := "5"
    app.Appearance.PinColor := "E122AA"
    check.Call(app.Appearance.Save() && !app.HasOwnProp("Appearance"), "Valid appearance saves and closes its editor")
    loaded := MapperSettings(app.Config.Path)
    check.Call(loaded.OverlayColor = "12ABEF" && loaded.OverlayTransparency = 60
        && loaded.PinOutlineColor = "E122AA" && loaded.PinOutlineThickness = 5, "Both independent appearance styles persist globally")
    check.Call(MapperAppearance.Blend("FFFFFF", 0) = "FFFFFF" && MapperAppearance.Blend("FFFFFF", 100) = "606060"
        && MapperAppearance.Blend("FFFFFF", 60) = "A0A0A0", "Preview uses transparency percentage rather than opacity")
    Reset()
}
