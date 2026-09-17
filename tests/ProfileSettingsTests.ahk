#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include ../lib/MacroModel.ahk

; Isolated model/settings tests only. No hooks, windows, input, or live config.
global ProfileChecks := 0
global ProfileFixture := A_ScriptDir "\artifacts\profile-settings-" ProcessExist() ".ini"
RunProfileSettingsTests()
ExitApp(0)

RunProfileSettingsTests() {
    global ProfileChecks, ProfileFixture
    try {
        DirCreate(A_ScriptDir "\artifacts")
        TestProfileMigration()
        TestProfileLifecycle()
        TestProfilePersistence()
        TestAppearanceAndTopmostSettings()
        FileAppend("PASS: profile settings / " ProfileChecks " assertions`n", "*")
    } catch Error as err {
        FileAppend("FAIL: " err.Message " (" err.File ":" err.Line ")`n", "*")
        ExitApp(1)
    } finally {
        if FileExist(ProfileFixture)
            FileDelete(ProfileFixture)
    }
}

TestAppearanceAndTopmostSettings() {
    global ProfileFixture
    ProfileWrite("[Settings]`nVersion=1`n")
    config := MapperSettings(ProfileFixture)
    ProfileCheck(config.OverlayColor = "FFFFFF" && config.OverlayTransparency = 60, "Legacy overlay defaults retain white at forty percent opacity")
    ProfileCheck(config.PinOutlineEnabled && config.PinOutlineColor = "0078D4" && config.PinOutlineThickness = 3, "Legacy pin outline defaults are enabled blue at three pixels")
    config.OverlayColor := "a1b2c3"
    config.OverlayTransparency := 37
    config.PinOutlineEnabled := false
    config.PinOutlineColor := "c0ffee"
    config.PinOutlineThickness := 7
    config.Save()
    restored := MapperSettings(ProfileFixture)
    ProfileCheck(restored.LoadError = "" && restored.OverlayColor = "A1B2C3" && restored.OverlayTransparency = 37, "Custom overlay appearance roundtrips with canonical color")
    ProfileCheck(!restored.PinOutlineEnabled && restored.PinOutlineColor = "C0FFEE" && restored.PinOutlineThickness = 7, "Custom pin outline appearance roundtrips globally")
    ProfileCheck(InStr(FileRead(ProfileFixture), "Version=1`r`n"), "Appearance changes alone preserve legacy version compatibility")
    for , bounds in [{Alpha: 0, Thickness: 1}, {Alpha: 100, Thickness: 12}] {
        restored.OverlayTransparency := bounds.Alpha
        restored.PinOutlineThickness := bounds.Thickness
        restored.Save()
        endpoints := MapperSettings(ProfileFixture)
        ProfileCheck(endpoints.OverlayTransparency = bounds.Alpha && endpoints.PinOutlineThickness = bounds.Thickness, "Appearance range endpoints roundtrip")
    }
    nativeProfile := restored.CreateProfile("Pins")
    restored.FindProfile(nativeProfile).Mappings["4L"] := ProfileMapping("invalid retained macro", "ToggleTopmost", true, "Release")
    restored.Mappings["5DR"] := ProfileMapping("key F8")
    restored.Save()
    ProfileCheck(InStr(FileRead(ProfileFixture), "Version=6`r`n"), "Inactive-profile topmost action requires version 6 even with a later double-click binding")
    saved := MapperSettings(ProfileFixture)
    topmost := saved.FindProfile(nativeProfile).Mappings["4L"]
    ProfileCheck(saved.LoadError = "" && topmost.Action = "ToggleTopmost" && topmost.Timing = "Release" && topmost.Hold
        && topmost.Source = "invalid retained macro" && topmost.Steps.Length = 0 && MacroModel.Assigned(topmost), "Always-on-top action and retained inactive macro options roundtrip")
    before := FileRead(ProfileFixture)
    saved.PinOutlineThickness := 13
    ProfileReject(() => saved.Save(), "Invalid outline thickness rejects saving")
    ProfileCheck(FileRead(ProfileFixture) = before, "Rejected appearance save preserves prior profile config")
    saved.PinOutlineThickness := 3
    saved.OverlayColor := "#FFFFFF"
    ProfileReject(() => saved.Save(), "Overlay color requires exactly six hexadecimal digits")
    saved.OverlayColor := "FFFFFF"
    saved.OverlayTransparency := -1
    ProfileReject(() => saved.Save(), "Negative overlay transparency is rejected")
    saved.OverlayTransparency := 60
    saved.PinOutlineEnabled := "yes"
    ProfileReject(() => saved.Save(), "Outline enable state must be boolean")
    for , invalid in ["OverlayColor=GGGGGG", "OverlayTransparency=101", "OverlayTransparency=1.5",
        "PinOutlineEnabled=true", "PinOutlineColor=12345", "PinOutlineThickness=0"] {
        ProfileWrite("[Settings]`nVersion=1`nPaused=0`n" invalid "`n")
        broken := MapperSettings(ProfileFixture)
        ProfileCheck(broken.LoadError != "" && broken.Paused, "Invalid persisted appearance setting fails closed")
    }
}

TestProfileMigration() {
    global ProfileFixture
    fixtures := [
        {Version: 1, ID: "4L", Source: "key Win", Action: "Macro", Hold: true},
        {Version: 2, ID: "5R", Source: "invalid inactive macro", Action: "ResizeWindow", Hold: true},
        {Version: 3, ID: "4LR", Source: "key F8", Action: "Macro", Hold: false}]
    for , fixture in fixtures {
        ProfileWrite("[Settings]`nVersion=" fixture.Version "`nPaused=0`nPreserve=0`nView=List`nSelected=" fixture.ID
            . "`nChordDelayMs=375`n[" fixture.ID "]`nName=" MapperSettings.Encode("Existing")
            . "`nMacro=" MapperSettings.Encode(fixture.Source) "`nAction=" fixture.Action "`nTiming=Release`nHold=" Integer(fixture.Hold) "`n")
        config := MapperSettings(ProfileFixture)
        ProfileCheck(config.LoadError = "" && config.Profiles.Length = 1 && config.ActiveProfileID = "default" && config.ActiveProfile().Name = "Default", "Legacy version " fixture.Version " migrates to Default")
        ProfileCheck(ObjPtr(config.Mappings) = ObjPtr(config.ActiveProfile().Mappings) && config.Mappings.Count = 25, "Legacy mappings alias the active profile and include empty new slots")
        mapping := config.Mappings[fixture.ID]
        ProfileCheck(mapping.Source = fixture.Source && mapping.Action = fixture.Action && mapping.Hold = fixture.Hold && mapping.Timing = "Release", "Legacy mapping data is retained")
        ProfileCheck(!config.Paused && !config.Preserve && config.View = "List" && config.Selected = fixture.ID && config.ChordDelayMs = 375 && config.CycleShortcut = "", "Migration preserves global preferences")
        config.Save()
        ProfileCheck(InStr(FileRead(ProfileFixture), "Version=" fixture.Version "`r`n"), "Unchanged Default profile retains the legacy version")
    }
}

TestProfileLifecycle() {
    global ProfileFixture
    ProfileWrite("[Settings]`nVersion=1`nPaused=0`n")
    config := MapperSettings(ProfileFixture)
    config.Mappings["4L"] := ProfileMapping("key Ctrl+S", "Macro", true)
    ProfileReject(() => config.CreateProfile("  "), "Empty profile names are rejected")
    ProfileReject(() => config.CreateProfile("DEFAULT"), "Profile names are unique without case sensitivity")
    longName := ""
    loop 81
        longName .= "x"
    ProfileReject(() => config.CreateProfile(longName), "Names longer than 80 characters are rejected")
    work := config.CreateProfile("  Work  ")
    play := config.CreateProfile("Play")
    copy := config.CreateProfile("Copy", "default")
    ProfileCheck(config.ActiveProfileID = "default" && config.Profiles[2].Name = "Work", "Creating a profile trims its name without switching active profile")
    ProfileCheck(ProfileTestOrder(config) = "default," work "," play "," copy, "Creation appends to a stable cycle order")
    ProfileCheck(!MacroModel.Assigned(config.FindProfile(work).Mappings["4L"]), "New profiles start with empty mappings")
    duplicate := config.FindProfile(copy).Mappings["4L"]
    ProfileCheck(duplicate.Source = "key Ctrl+S" && duplicate.Hold && ObjPtr(duplicate) != ObjPtr(config.Mappings["4L"])
        && ObjPtr(duplicate.Steps[1]) != ObjPtr(config.Mappings["4L"].Steps[1]), "Duplicated mappings and parsed steps are independent copies")
    duplicate.Name := "Edited copy"
    ProfileCheck(config.Mappings["4L"].Name != duplicate.Name, "Editing a copied mapping leaves its source profile intact")
    config.RenameProfile(work, "  Editing  ")
    ProfileCheck(config.Profiles[2].ID = work && config.Profiles[2].Name = "Editing", "Rename preserves stable ID and position")
    ProfileReject(() => config.RenameProfile(work, "copy"), "Rename rejects another profile's name")
    ProfileReject(() => config.SelectProfile("missing"), "Unknown profiles cannot be selected")
    ProfileReject(() => config.CreateProfile("Missing source", "missing"), "Duplication rejects unknown source profiles")
    ProfileCheck(config.Profiles.Length = 4, "Failed duplication does not add a partial profile")
    config.SelectProfile(work)
    config.Mappings["5M"] := ProfileMapping("key F7")
    ProfileCheck(ObjPtr(config.Mappings) = ObjPtr(config.ActiveProfile().Mappings) && config.FindProfile(work).Mappings["5M"].Source = "key F7", "Selecting profiles updates the writable active-map alias")
    config.DeleteProfile(work)
    ProfileCheck(config.ActiveProfileID = play && ProfileTestOrder(config) = "default," play "," copy, "Deleting active profile selects the following profile in stable order")
    config.DeleteProfile("default")
    ProfileCheck(config.ActiveProfileID = play && ObjPtr(config.Mappings) = ObjPtr(config.ActiveProfile().Mappings), "Deleting an inactive profile preserves active selection and alias")
    config.SelectProfile(copy)
    config.DeleteProfile(copy)
    ProfileCheck(config.ActiveProfileID = play && config.Profiles.Length = 1, "Deleting the final ordered profile wraps to the first remaining profile")
    ProfileReject(() => config.DeleteProfile(play), "The last profile cannot be deleted")
    ProfileCheck(!config.Paused, "Profile management does not change global pause state")
    config.Save()
    ProfileCheck(InStr(FileRead(ProfileFixture), "Version=4`r`n"), "A single non-default profile retains profile-format version 4")
}

TestProfilePersistence() {
    global ProfileFixture
    ProfileWrite("[Settings]`nVersion=1`n")
    config := MapperSettings(ProfileFixture)
    config.Mappings["4L"] := ProfileMapping("key Ctrl+Shift+C", "Macro", true, "Release")
    config.Mappings["4R"] := ProfileMapping("invalid retained source", "MoveWindow", true, "Release")
    studio := config.CreateProfile("Studio")
    gaming := config.CreateProfile("Gaming", "default")
    config.SelectProfile(studio)
    config.Mappings["4L"] := ProfileMapping("key Enter")
    config.Mappings["5LR"] := ProfileMapping("text retained", "ResizeWindow", true)
    config.CycleShortcut := "Ctrl+Alt+F9"
    config.Paused := false
    config.Preserve := false
    config.ChordDelayMs := 777
    config.View := "List"
    config.Selected := "5LR"
    config.Save()
    ProfileCheck(InStr(FileRead(ProfileFixture), "Version=4`r`n"), "Multiple profiles persist with version 4")
    restored := MapperSettings(ProfileFixture)
    ProfileCheck(restored.LoadError = "" && ProfileTestOrder(restored) = "default," studio "," gaming && restored.ActiveProfileID = studio, "Profile IDs, order, and active selection roundtrip")
    ProfileCheck(ObjPtr(restored.Mappings) = ObjPtr(restored.ActiveProfile().Mappings) && restored.Mappings["4L"].Source = "key Enter", "Loaded active alias points to the selected profile's mappings")
    ProfileCheck(restored.FindProfile("default").Mappings["4L"].Source = "key Ctrl+Shift+C" && restored.FindProfile(gaming).Mappings["4L"].Hold, "Each profile retains different macro and hold bindings")
    ProfileCheck(restored.FindProfile("default").Mappings["4R"].Action = "MoveWindow" && restored.FindProfile("default").Mappings["4R"].Source = "invalid retained source"
        && restored.Mappings["5LR"].Action = "ResizeWindow", "Native actions and inactive macro sources survive per profile")
    ProfileCheck(!restored.Paused && !restored.Preserve && restored.ChordDelayMs = 777 && restored.View = "List" && restored.Selected = "5LR" && restored.CycleShortcut = "Ctrl+Alt+F9", "Global preferences and cycle shortcut roundtrip independently of mappings")
    restored.SelectProfile("default")
    ProfileCheck(!restored.Paused && restored.Mappings["4L"].Hold && restored.Mappings["4L"].Timing = "Release", "Selecting a restored profile preserves global pause and its binding options")
    restored.FindProfile(gaming).Mappings["5DR"] := ProfileMapping("key F8")
    restored.Save()
    ProfileCheck(InStr(FileRead(ProfileFixture), "Version=5`r`n"), "A double-click binding in an inactive profile requires version 5")
    restored := MapperSettings(ProfileFixture)
    ProfileCheck(restored.LoadError = "" && restored.ActiveProfileID = "default" && restored.FindProfile(gaming).Mappings["5DR"].Steps.Length = 1, "Version-5 profile settings preserve inactive double-click mappings")
    before := FileRead(ProfileFixture)
    restored.CycleShortcut := "Ctrl+F8`nkey F9"
    ProfileReject(() => restored.Save(), "Multiline cycle shortcuts are rejected without registering anything")
    ProfileCheck(FileRead(ProfileFixture) = before, "Invalid shortcut save leaves the prior file intact")
    restored.CycleShortcut := "Ctrl+Alt+F9"
    restored.FindProfile(studio).Mappings["4L"] := {Name: "Invalid", Source: "text hello", Steps: [], Hold: true}
    ProfileReject(() => restored.Save(), "Inactive profiles receive the same binding validation")
    ProfileCheck(FileRead(ProfileFixture) = before, "Invalid inactive mapping leaves the prior file intact")

    ProfileWrite("[Settings]`nVersion=1`n")
    renamed := MapperSettings(ProfileFixture)
    renamed.RenameProfile("default", "Personal")
    renamed.Save()
    ProfileCheck(InStr(FileRead(ProfileFixture), "Version=4`r`n") && MapperSettings(ProfileFixture).ActiveProfile().Name = "Personal", "Renaming Default alone persists using profile format")
    renamed.RenameProfile("default", "Default")
    renamed.CycleShortcut := "Ctrl+F9"
    renamed.Save()
    ProfileCheck(InStr(FileRead(ProfileFixture), "Version=4`r`n") && MapperSettings(ProfileFixture).CycleShortcut = "Ctrl+F9", "Cycle shortcut alone persists using profile format")
    renamed.CycleShortcut := ""
    renamed.Mappings["4DL"] := ProfileMapping("key F7")
    renamed.Save()
    ProfileCheck(InStr(FileRead(ProfileFixture), "Version=5`r`n") && MapperSettings(ProfileFixture).Mappings["4DL"].Steps.Length = 1, "A lone Default profile with a double-click binding uses version-5 profile schema")

    invalidConfigs := [
        "[Settings]`nVersion=4`nProfileOrder=default,default`nActiveProfile=default`n[Profile:default]`nName=" MapperSettings.Encode("Default"),
        "[Settings]`nVersion=4`nProfileOrder=a,b`nActiveProfile=a`n[Profile:a]`nName=" MapperSettings.Encode("Name") "`n[Profile:b]`nName=" MapperSettings.Encode("NAME"),
        "[Settings]`nVersion=4`nProfileOrder=default`nActiveProfile=missing`n[Profile:default]`nName=" MapperSettings.Encode("Default"),
        "[Settings]`nVersion=4`nProfileOrder=default`nActiveProfile=default`nCycleShortcut=" MapperSettings.Encode("Ctrl+F8`r`nF9") "`n[Profile:default]`nName=" MapperSettings.Encode("Default"),
        "[Settings]`nVersion=4`nProfileOrder=bad:id`nActiveProfile=bad:id",
        "[Settings]`nVersion=4"]
    for , invalid in invalidConfigs {
        ProfileWrite(invalid)
        broken := MapperSettings(ProfileFixture)
        ProfileCheck(broken.LoadError != "" && broken.Paused && broken.ActiveProfileID = "default" && !MacroModel.Assigned(broken.Mappings["4L"]), "Invalid profile config fails closed with a blank default alias")
    }
}

ProfileMapping(source, action := "Macro", hold := false, timing := "Press") {
    mapping := {Name: "Test mapping", Source: source, Action: action, Hold: hold, Timing: timing}
    mapping.Steps := MacroModel.ValidateMapping(mapping)
    return mapping
}

ProfileTestOrder(config) {
    order := ""
    for , profile in config.Profiles
        order .= (order = "" ? "" : ",") profile.ID
    return order
}

ProfileCheck(condition, message) {
    global ProfileChecks
    ProfileChecks += 1
    if !condition
        throw Error(message)
}

ProfileReject(callback, message) {
    rejected := false
    try callback.Call()
    catch Error
        rejected := true
    ProfileCheck(rejected, message)
}

ProfileWrite(content) {
    global ProfileFixture
    if FileExist(ProfileFixture)
        FileDelete(ProfileFixture)
    FileAppend(content, ProfileFixture, "UTF-8-RAW")
}
