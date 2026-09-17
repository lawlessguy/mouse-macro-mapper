#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include ../lib/MacroModel.ahk

; Model/settings tests only: no hooks, input injection, windows, or live settings.
global OptionChecks := 0
global OptionFixture := A_ScriptDir "\artifacts\mapping-options-" ProcessExist() ".ini"
RunMappingOptionTests()
ExitApp(0)

RunMappingOptionTests() {
global OptionChecks, OptionFixture
try {
    DirCreate(A_ScriptDir "\artifacts")
    legacy := {Name: "Legacy", Source: "key Enter", Steps: MacroModel.Parse("key Enter")}
    OptionEqual(MacroModel.Action(legacy), "Macro", "Legacy objects use the Macro action")
    OptionCheck(MacroModel.Assigned(legacy), "Legacy parsed macro remains assigned")
    OptionCheck(!MacroModel.Assigned({Steps: []}), "Empty legacy macro remains unassigned")
    OptionEqual(MacroModel.Timing(legacy), "Press", "Legacy objects use Press")
    OptionEqual(MacroModel.IsHold(legacy), false, "Legacy objects do not hold")
    OptionReject(() => MacroModel.Timing({Timing: "release"}), "Timing is strict")
    OptionReject(() => MacroModel.IsHold({Hold: "yes"}), "Hold is strict")

    OptionWrite("[Settings]`nVersion=1`nPaused=0`n[4L]`nMacro=" MapperSettings.Encode("key Enter") "`n")
    config := MapperSettings(OptionFixture)
    OptionEqual(config.LoadError, "", "Legacy file loads")
    OptionEqual(config.Mappings["4L"].Action, "Macro", "Legacy file action defaults to Macro")
    OptionEqual(config.ChordDelayMs, 200, "Legacy file defaults to a 200 ms chord delay")
    OptionCheck(config.Mappings.Has("4LR") && config.Mappings.Has("5LR") && !MacroModel.Assigned(config.Mappings["4LR"]) && !MacroModel.Assigned(config.Mappings["5LR"]), "Legacy files gain empty overlapping-primary slots")
    OptionEqual(config.Mappings["4L"].Timing, "Press", "Legacy file timing defaults")
    OptionEqual(config.Mappings["4L"].Hold, false, "Legacy file hold defaults")
    config.Mappings["4L"] := {Name: "Hold shortcut", Source: "key Ctrl+Shift+C", Steps: MacroModel.Parse("key Ctrl+Shift+C"), Timing: "Release", Hold: true}
    config.Mappings["5R"] := legacy
    config.Save()
    restored := MapperSettings(OptionFixture)
    OptionEqual(restored.LoadError, "", "Options roundtrip loads")
    OptionEqual(restored.Mappings["4L"].Timing, "Release", "Hold retains one-shot timing choice")
    OptionEqual(restored.Mappings["4L"].Hold, true, "Hold roundtrips")
    OptionEqual(restored.Mappings["5R"].Timing, "Press", "Legacy object saves compatibly")
    OptionEqual(restored.Mappings["5R"].Source, "key Enter", "Unrelated mapping stays intact")
    OptionEqual(restored.Mappings["5R"].Action, "Macro", "Legacy objects save with the Macro action")
    OptionCheck(InStr(FileRead(OptionFixture), "Version=1`r`n"), "Only-macro configuration retains version 1")

    for , options in ["Timing=Later`nHold=0", "Timing=Press`nHold=true", "Timing=Press`nHold=2", "Action=Other", "Action=movewindow"] {
        OptionWrite("[Settings]`nVersion=1`nPaused=0`n[4L]`nMacro=" MapperSettings.Encode("key Enter") "`n" options "`n")
        broken := MapperSettings(OptionFixture)
        OptionCheck(broken.LoadError != "", "Invalid options rejected")
        OptionCheck(broken.Paused && broken.Mappings["4L"].Steps.Length = 0, "Invalid load fails closed")
    }
    OptionWrite("[Settings]`nVersion=1`nPaused=0`n[4L]`nMacro=" MapperSettings.Encode("text hello") "`nHold=1`n")
    broken := MapperSettings(OptionFixture)
    OptionCheck(broken.LoadError != "" && broken.Paused, "Invalid hold body fails closed on load")
    OptionWrite("[Settings]`nVersion=1`n")
    config := MapperSettings(OptionFixture)
    config.Mappings["4L"] := {Name: "Bad hold", Source: "text hello", Steps: [], Timing: "Press", Hold: true}
    before := FileRead(OptionFixture)
    OptionReject(() => config.Save(), "Invalid hold body rejected on save")
    OptionEqual(FileRead(OptionFixture), before, "Rejected save preserves original file")

    OptionCheck(MacroModel.ValidateBinding(MacroModel.Parse("text hello`ndelay 20`nkey Enter"), false), "One-shot macros retain all commands")
    for , source in ["", "; only a comment", "text hello", "delay 20", "key Enter`nkey Escape", "key Plus"]
        OptionReject(() => MacroModel.ValidateBinding(MacroModel.Parse(source), true), "Unsupported hold body rejected: " source)
    OptionCheck(MacroModel.ValidateBinding(MacroModel.Parse("; comment`nkey Ctrl+C`n; comment"), true), "Comments do not add hold steps")
    keys := MacroModel.HoldKeys(MacroModel.Parse("key Win+Shift+Alt+Ctrl+C"))
    OptionEqual(keys.Length, 5, "Shortcut has four modifiers and one key")
    for index, name in ["LControl", "LAlt", "LShift", "LWin", "c"]
        OptionEqual(keys[index], MacroModel.HoldKeyIdentity(name), "Canonical modifier-first order")
    OptionEqual(MacroModel.HoldKeys(MacroModel.Parse("key Return"))[1], MacroModel.HoldKeys(MacroModel.Parse("key Enter"))[1], "Return/Enter share identity")
    OptionEqual(MacroModel.HoldKeys(MacroModel.Parse("key Esc"))[1], MacroModel.HoldKeys(MacroModel.Parse("key Escape"))[1], "Escape aliases share identity")
    OptionEqual(MacroModel.HoldKeys(MacroModel.Parse("key C"))[1], MacroModel.HoldKeys(MacroModel.Parse("key c"))[1], "Letter case retains parser semantics")
    OptionCheck(MacroModel.HoldKeys(MacroModel.Parse("key NumpadEnter"))[1] != MacroModel.HoldKeys(MacroModel.Parse("key Enter"))[1], "Extended Enter is distinct")
    OptionEqual(MacroModel.HoldKeys(MacroModel.Parse("key Numpad0"))[1], MacroModel.HoldKeys(MacroModel.Parse("key NumpadIns"))[1], "Numpad physical aliases share identity")
    for modifier, canonical in Map("Win", "LWin", "Alt", "LAlt", "Ctrl", "LControl", "Control", "LControl", "Shift", "LShift",
        "LWin", "LWin", "RWin", "RWin", "LAlt", "LAlt", "RAlt", "RAlt", "LControl", "LControl", "RControl", "RControl",
        "LCtrl", "LControl", "RCtrl", "RControl", "LShift", "LShift", "RShift", "RShift") {
        steps := MacroModel.Parse("key " modifier)
        heldModifier := MacroModel.HoldKeys(steps)
        OptionCheck(steps[1].Value = "{" canonical "}" && heldModifier.Length = 1
            && heldModifier[1] = MacroModel.HoldKeyIdentity(canonical)
            && MacroModel.ValidateBinding(steps, true), "Standalone modifier parses and holds the intended key: " modifier)
    }
    OptionEqual(MacroModel.HoldKeys(MacroModel.Parse("key Win"))[1], MacroModel.HoldKeyIdentity("LWin"), "Standalone Win holds the left Windows key")
    arrowShortcut := MacroModel.Parse("key Win+Left")
    OptionEqual(arrowShortcut[1].Value, "#{Left}", "Win+Left remains Windows plus the keyboard left arrow")
    arrowKeys := MacroModel.HoldKeys(arrowShortcut)
    OptionCheck(arrowKeys.Length = 2 && arrowKeys[1] = MacroModel.HoldKeyIdentity("LWin") && arrowKeys[2] = MacroModel.HoldKeyIdentity("Left"), "Win+Left decomposes into Windows and arrow keys")
    OptionCheck(MacroModel.ValidateBinding(arrowShortcut, true), "Win+Left remains a valid shortcut hold")
    commentedModifier := MacroModel.Parse("; comment`nkey RAlt")
    OptionCheck(commentedModifier.Length = 1 && MacroModel.HoldKeys(commentedModifier)[1] = MacroModel.HoldKeyIdentity("RAlt"), "Comments do not alter standalone modifier holds")

    OptionReject(() => MacroModel.Action({Action: ""}), "Explicit empty action is invalid")
    OptionReject(() => MacroModel.MappingSteps("key Enter", "Other"), "MappingSteps rejects unknown actions")
    OptionEqual(MacroModel.MappingSteps("key Enter", "Macro").Length, 1, "Macro MappingSteps parses the body")
    OptionEqual(MacroModel.MappingSteps("not a macro", "MoveWindow").Length, 0, "Window MappingSteps ignores inactive macro syntax")
    OptionReject(() => MacroModel.ValidateMapping({Source: "", Action: "MoveWindow", Timing: "Later"}), "Window actions still validate stored timing")
    OptionReject(() => MacroModel.ValidateMapping({Source: "", Action: "ResizeWindow", Hold: "yes"}), "Window actions still validate stored Hold option")
    OptionWrite("[Settings]`nVersion=1`n")
    config := MapperSettings(OptionFixture)
    inactiveSource := "  invalid retained macro`r`nkey {Ctrl down}`r`n; preserve this exactly  "
    config.Mappings["4L"] := {Name: "Native move", Source: inactiveSource, Steps: [], Action: "MoveWindow", Timing: "Release", Hold: true}
    config.Mappings["5R"] := {Name: "Native resize", Source: "text retained`ndelay 25", Steps: [], Action: "ResizeWindow", Timing: "Press", Hold: true}
    OptionCheck(MacroModel.Assigned(config.Mappings["4L"]) && MacroModel.Assigned(config.Mappings["5R"]), "Both native actions are assigned without macro steps")
    OptionEqual(MacroModel.ValidateMapping(config.Mappings["4L"]).Length, 0, "Native action validates without parsing inactive source")
    config.Save()
    savedNative := FileRead(OptionFixture)
    OptionCheck(InStr(savedNative, "Version=2`r`n"), "Native-action settings require version 2 for older-app fail-closed behavior")
    restored := MapperSettings(OptionFixture)
    OptionEqual(restored.LoadError, "", "Both native actions reload successfully")
    OptionEqual(restored.Mappings["4L"].Action, "MoveWindow", "Move action persists")
    OptionEqual(restored.Mappings["5R"].Action, "ResizeWindow", "Resize action persists")
    OptionEqual(restored.Mappings["4L"].Source, inactiveSource, "Inactive invalid macro text is preserved exactly")
    OptionCheck(restored.Mappings["4L"].Timing = "Release" && restored.Mappings["4L"].Hold, "Inactive move timing and Hold are retained")
    OptionCheck(restored.Mappings["5R"].Source = "text retained`ndelay 25" && restored.Mappings["5R"].Hold, "Inactive resize body retains a script incompatible with Hold")
    OptionCheck(restored.Mappings["4L"].Steps.Length = 0 && restored.Mappings["5R"].Steps.Length = 0, "Native actions never expose retained macro steps for playback")
    restored.Mappings["4L"].Action := "Macro"
    OptionReject(() => MacroModel.ValidateMapping(restored.Mappings["4L"]), "Returning to Macro validates the retained invalid source")
    OptionReject(() => restored.Save(), "Saving a reactivated invalid macro is rejected")
    OptionEqual(FileRead(OptionFixture), savedNative, "Rejected action change leaves prior native settings intact")
    restored.Mappings["4L"].Source := "key Enter"
    restored.Mappings["4L"].Hold := false
    restored.Mappings["5R"].Action := "Macro"
    OptionReject(() => MacroModel.ValidateMapping(restored.Mappings["5R"]), "Returning to Macro restores Hold body validation")
    restored.Mappings["5R"].Hold := false
    restored.Save()
    OptionCheck(InStr(FileRead(OptionFixture), "Version=1`r`n"), "Removing all native actions restores compatible version 1")
    OptionWrite("[Settings]`nVersion=2`n")
    OptionEqual(MapperSettings(OptionFixture).LoadError, "", "Version 2 with default mappings is supported")
    OptionWrite("[Settings]`nVersion=99`nPaused=0`n")
    unsupported := MapperSettings(OptionFixture)
    OptionCheck(unsupported.LoadError != "" && unsupported.Paused, "Unknown settings version fails closed")

    OptionEqual(MacroModel.Chords.Length, 25, "Registry exposes twenty-one held chords and four double-click chords")
    legacyOrder := ["4L", "4R", "4M", "5L", "5R", "5M", "45L", "45R", "45M"]
    orderPreserved := true
    for index, id in legacyOrder
        orderPreserved := orderPreserved && MacroModel.IDs[index] = id
    OptionCheck(orderPreserved, "Registry preserves the original nine ordering")
    largerOrder := ["4LR", "4LM", "4RM", "4LRM", "5LR", "5LM", "5RM", "5LRM", "45LR", "45LM", "45RM", "45LRM"]
    for index, id in largerOrder
        orderPreserved := orderPreserved && MacroModel.IDs[index + 9] = id
    OptionCheck(orderPreserved, "Larger chords append in side-mask and LR/LM/RM/LRM order")
    OptionCheck(MacroModel.IDs[22] = "4DL" && MacroModel.IDs[23] = "4DR" && MacroModel.IDs[24] = "5DL" && MacroModel.IDs[25] = "5DR", "Double-click entries append after the held chords")
    leftRight := MacroModel.Chord("4LR")
    OptionCheck(leftRight.Mask = 1 && leftRight.Trigger = "LR" && leftRight.Buttons.Length = 2 && leftRight.Buttons[1] = "LButton" && leftRight.Buttons[2] = "RButton", "4LR descriptor names both held primaries")
    OptionCheck(MacroModel.Chord("5LR").Mask = 2 && MacroModel.Labels[14] = "Button 5 + Left + Right", "5LR descriptor and derived label use side 5")
    OptionEqual(MacroModel.Chord("4RL"), 0, "Unregistered chord lookup fails closed")
    OptionEqual(MacroModel.ChordID(1, "LR"), "4LR", "Side 4 plus both primaries resolves")
    OptionEqual(MacroModel.ChordID(2, "LR"), "5LR", "Side 5 plus both primaries resolves")
    OptionEqual(MacroModel.ChordID(3, "RButton"), "45R", "Single-primary button names retain old ID resolution")
    OptionEqual(MacroModel.ChordID(3, "LR"), "45LR", "Both-side larger chord resolves from its exact mask")
    OptionEqual(MacroModel.ChordID(0, "LR"), "", "Bare primary combinations remain unsupported")
    OptionEqual(MacroModel.ChordID(1, ""), "", "Side-only combinations remain unsupported")
    OptionEqual(MacroModel.PrimaryTrigger(Map("RButton", true, "LButton", true, "MButton", false)), "LR", "Primary trigger canonicalizes right-first map order")
    OptionEqual(MacroModel.PrimaryTrigger(Map("MButton", true, "RButton", true, "LButton", true)), "LRM", "Primary trigger includes every held primary in stable order")
    OptionEqual(MacroModel.PrimaryTrigger(Map()), "", "No held primaries produces an empty trigger")

    OptionWrite("[Settings]`nVersion=3`n")
    config := MapperSettings(OptionFixture)
    OptionEqual(config.LoadError, "", "Version 3 is supported")
    config.Selected := "4LR"
    config.ChordDelayMs := 350
    config.Mappings["4LR"] := {Name: "Both primary keys", Source: "key F8", Steps: [], Timing: "Release", Hold: false}
    config.Save()
    OptionCheck(InStr(FileRead(OptionFixture), "Version=3`r`n"), "Assigned larger macro requires version 3 even if its cached Steps are stale")
    restored := MapperSettings(OptionFixture)
    OptionCheck(restored.LoadError = "" && restored.Selected = "4LR" && restored.Mappings["4LR"].Steps.Length = 1 && restored.Mappings["4LR"].Timing = "Release", "Larger macro and selected navigation roundtrip")
    OptionEqual(restored.ChordDelayMs, 350, "Custom chord delay roundtrips")
    restored.Mappings["4LR"].Source := ""
    restored.Mappings["4LR"].Steps := []
    restored.Mappings["5LR"].Action := "MoveWindow"
    restored.Selected := "5LR"
    restored.Save()
    OptionCheck(InStr(FileRead(OptionFixture), "Version=3`r`n"), "Assigned larger native action requires version 3")
    restored := MapperSettings(OptionFixture)
    OptionCheck(restored.LoadError = "" && restored.Selected = "5LR" && restored.Mappings["5LR"].Action = "MoveWindow", "Side-5 larger native action and selection roundtrip")
    restored.Mappings["5LR"].Action := "Macro"
    restored.Selected := "4L"
    restored.Save()
    OptionCheck(InStr(FileRead(OptionFixture), "Version=1`r`n"), "Empty larger slots and a custom delay alone retain version 1")
    restored.Mappings["4L"].Action := "ResizeWindow"
    restored.Save()
    OptionCheck(InStr(FileRead(OptionFixture), "Version=2`r`n"), "Original native actions retain version 2 when larger slots are empty")
    for , delay in [0, 1000] {
        restored.ChordDelayMs := delay
        restored.Save()
        OptionEqual(MapperSettings(OptionFixture).ChordDelayMs, delay, "Chord-delay range endpoint roundtrips")
    }
    before := FileRead(OptionFixture)
    restored.ChordDelayMs := -1
    OptionReject(() => restored.Save(), "Invalid chord delay is rejected before saving")
    OptionEqual(FileRead(OptionFixture), before, "Invalid delay save preserves the isolated config")
    for , delay in ["-1", "1.5", "1001", "later", ""] {
        OptionWrite("[Settings]`nVersion=1`nPaused=0`nChordDelayMs=" delay "`n")
        broken := MapperSettings(OptionFixture)
        OptionCheck(broken.LoadError != "" && broken.Paused && broken.ChordDelayMs = 200, "Invalid saved chord delay fails closed")
    }
    OptionWrite("[Settings]`nVersion=1`n")
    config := MapperSettings(OptionFixture)
    for index, chord in MacroModel.Chords {
        source := "key F" (Mod(index - 1, 24) + 1)
        config.Mappings[chord.ID] := {Name: "Roundtrip " chord.ID, Source: source, Steps: MacroModel.Parse(source)}
    }
    config.Selected := "45LRM"
    config.Save()
    restored := MapperSettings(OptionFixture)
    OptionCheck(restored.LoadError = "" && restored.Mappings.Count = 25 && restored.Selected = "45LRM", "All twenty-five assigned slots and triple-primary navigation reload")
    for index, chord in MacroModel.Chords {
        mapping := restored.Mappings[chord.ID]
        primary := Map()
        for , button in chord.Buttons
            primary[button] := true
        trigger := chord.Kind = "Double" ? chord.Trigger : MacroModel.PrimaryTrigger(primary)
        OptionCheck(mapping.Name = "Roundtrip " chord.ID && mapping.Source = "key F" (Mod(index - 1, 24) + 1) && mapping.Steps.Length = 1
            && MacroModel.ChordID(chord.Mask, trigger) = chord.ID
            && MacroModel.Labels[index] = chord.Label, "Descriptor helpers and saved mapping roundtrip: " chord.ID)
    }
    FileAppend("PASS: mapping options / " OptionChecks " assertions`n", "*")
} catch Error as err {
    FileAppend("FAIL: " err.Message " (" err.File ":" err.Line ")`n", "*")
    ExitApp(1)
} finally {
    if FileExist(OptionFixture)
        FileDelete(OptionFixture)
}
}

OptionCheck(condition, message) {
    global OptionChecks
    OptionChecks += 1
    if !condition
        throw Error(message)
}

OptionEqual(actual, expected, message) => OptionCheck(actual == expected, message " | expected=[" expected "] actual=[" actual "]")

OptionReject(callback, message) {
    rejected := false
    try callback.Call()
    catch Error
        rejected := true
    OptionCheck(rejected, message)
}

OptionWrite(content) {
    global OptionFixture
    if FileExist(OptionFixture)
        FileDelete(OptionFixture)
    FileAppend(content, OptionFixture, "UTF-8-RAW")
}
