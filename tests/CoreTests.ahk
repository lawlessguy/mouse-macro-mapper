#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include ../lib/ChordState.ahk
#Include ../lib/MacroModel.ahk

; Isolated logic/persistence tests. This script never installs input hooks or sends input.
global TestStats := {Assertions: 0, Passed: 0, Failures: []}

RunTest("exact masks, target ownership, and paused/inhibited states", TestMasks)
RunTest("all 90 event orders for each primary button and preserve mode", TestEventOrders)
RunTest("cancellation at every event boundary retains release ownership", TestCancellationOrders)
RunTest("repeat presses, overlapping side gestures, and rearming", TestGestureEdges)
RunTest("duplicate primary downs cannot change original release ownership", TestDuplicatePrimaryOwnership)
RunTest("valid keyboard shortcuts and literal text", TestValidMacros)
RunTest("unsafe/invalid macro syntax and resource limits", TestInvalidMacros)
RunTest("Unicode settings round trip and replacement save", TestPersistence)
RunTest("corrupt settings remain untouched and cannot be overwritten", TestCorruptSettings)
RunTest("invalid UTF-8 and embedded NUL settings cannot silently truncate", TestCorruptEncoding)
RunTest("12,000 Chinese characters survive settings persistence", TestLargeUnicodePersistence)
RunTest("16,000-character ASCII source survives settings persistence", TestMaximumAsciiPersistence)
RunTest("write and replacement failures preserve the original settings", TestSaveFailures)
RunTest("view and selection preferences round trip with legacy defaults", TestNavigationPreferences)
RunTest("manual INI parser rejects ambiguous and malformed settings", TestIniStructure)

FileAppend("Passed groups: " TestStats.Passed "`nAssertions: " TestStats.Assertions "`n", "*")
for , failure in TestStats.Failures
    FileAppend("FAIL: " failure "`n", "*")
FileAppend(TestStats.Failures.Length ? "RESULT: FAIL`n" : "RESULT: PASS`n", "*")
ExitApp(TestStats.Failures.Length ? 1 : 0)

RunTest(name, callback) {
    global TestStats
    try {
        callback.Call()
        TestStats.Passed += 1
        FileAppend("PASS: " name "`n", "*")
    } catch Error as err {
        TestStats.Failures.Push(name ": " err.Message " (" err.File ":" err.Line ")")
    }
}

Assert(condition, message := "Assertion failed") {
    global TestStats
    TestStats.Assertions += 1
    if !condition
        throw Error(message)
}

Equal(actual, expected, message := "Values differ") {
    Assert(actual == expected, message " | expected=[" expected "] actual=[" actual "]")
}

Throws(callback, message := "Expected an error") {
    caught := false
    try callback.Call()
    catch Error
        caught := true
    Assert(caught, message)
}

NewActiveState() {
    state := ChordState()
    state.SetPaused(false)
    return state
}

TestMasks() {
    loop 4 {
        held := A_Index - 1
        loop 4 {
            captured := A_Index - 1
            loop 4 {
                rightTarget := A_Index - 1
                loop 4 {
                    mode := A_Index - 1
                    state := NewActiveState()
                    for id, bit in Map(4, 1, 5, 2)
                        if held & bit
                            state.SideDown(id, rightTarget & bit ? 111 : 222, !!(captured & bit))
                    state.Paused := !!(mode & 1)
                    state.Inhibited := !!(mode & 2)
                    expected := mode || (held & captured) != held || (held & rightTarget) != held ? 0 : held
                    Equal(state.Mask(111), expected, "Exact held/captured/target mask")
                }
            }
        }
    }
    state := NewActiveState()
    state.SideDown(4, 111)
    state.SideDown(5, 111)
    state.Sides[5].Epoch -= 1
    Equal(state.Mask(111), 0, "Any stale side invalidates the entire mask")
    Assert(!state.SideUp(5, 111, true), "Stale side must not replay")
    Equal(state.Mask(111), 1, "Removing stale side restores current valid mask")
}

EventOrders(prefix := "", remaining := "abcdef", output := unset) {
    if !IsSet(output)
        output := []
    if remaining = "" {
        ; a/b = side 4 down/up, c/d = side 5 down/up, e/f = primary down/up.
        if InStr(prefix, "a") < InStr(prefix, "b")
            && InStr(prefix, "c") < InStr(prefix, "d")
            && InStr(prefix, "e") < InStr(prefix, "f")
            output.Push(prefix)
        return output
    }
    loop StrLen(remaining) {
        index := A_Index
        EventOrders(prefix SubStr(remaining, index, 1),
            SubStr(remaining, 1, index - 1) SubStr(remaining, index + 1), output)
    }
    return output
}

ExpectedSideUse(order, id) {
    down := InStr(order, id = 4 ? "a" : "c")
    up := InStr(order, id = 4 ? "b" : "d")
    otherDown := InStr(order, id = 4 ? "c" : "a")
    otherUp := InStr(order, id = 4 ? "d" : "b")
    primaryDown := InStr(order, "e")
    primaryUp := InStr(order, "f")
    overlapsPrimary := down < primaryUp && up > primaryDown
    joinedUsedGesture := otherDown < primaryDown && primaryDown < down && down < otherUp
    return overlapsPrimary || joinedUsedGesture
}

TestEventOrders() {
    orders := EventOrders()
    Equal(orders.Length, 90, "Permutation coverage")
    for , button in ["LButton", "RButton", "MButton"] {
        for , preserve in [false, true] {
            for , order in orders {
                state := NewActiveState()
                blocked := false
                for index, event in StrSplit(order) {
                    context := order " / " button " / preserve=" preserve " / event=" event
                    switch event {
                        case "a": state.SideDown(4, 111)
                        case "c": state.SideDown(5, 111)
                        case "b", "d":
                            id := event = "b" ? 4 : 5
                            Equal(state.SideUp(id, 111, preserve), preserve && !ExpectedSideUse(order, id), context " replay")
                        case "e":
                            expectedMask := 0
                            if InStr(order, "a") < index && index < InStr(order, "b")
                                expectedMask |= 1
                            if InStr(order, "c") < index && index < InStr(order, "d")
                                expectedMask |= 2
                            Equal(state.Mask(111), expectedMask, context " dispatch mask")
                            blocked := expectedMask != 0
                            Assert(state.PrimaryDown(button, blocked), context " fresh down")
                        case "f":
                            Equal(state.PrimaryUp(button), blocked, context " matching up ownership")
                    }
                }
                Assert(state.AllReleased(), order " ends released")
                Equal(state.Mask(111), 0, order " ends without modifier")
                Assert(!state.Inhibited, order " ends rearmed")
            }
        }
    }
}

TestCancellationOrders() {
    for , button in ["LButton", "RButton", "MButton"] {
        for , order in EventOrders() {
            loop 7 {
                boundary := A_Index - 1
                state := NewActiveState()
                blocked := false
                if boundary = 0
                    state.Cancel()
                for index, event in StrSplit(order) {
                    context := order " / cancel after=" boundary " / " button
                    switch event {
                        case "a": state.SideDown(4, 111)
                        case "c": state.SideDown(5, 111)
                        case "b", "d":
                            id := event = "b" ? 4 : 5
                            wasCancelled := state.Sides[id].Epoch != state.Epoch
                            result := state.SideUp(id, 111, true)
                            if wasCancelled
                                Assert(!result, context " cancelled side cannot replay")
                        case "e":
                            blocked := state.Mask(111) != 0
                            state.PrimaryDown(button, blocked)
                        case "f":
                            Equal(state.PrimaryUp(button), blocked, context " retains original up disposition")
                    }
                    if index = boundary {
                        oldEpoch := state.Epoch
                        state.Cancel()
                        Equal(state.Epoch, oldEpoch + 1, context " generation advances")
                        Equal(state.Mask(111), 0, context " no chord after cancel")
                        Equal(state.Inhibited, !state.AllReleased(), context " held gesture waits for release")
                    }
                }
                Assert(state.AllReleased(), "Cancellation run ends released")
                Assert(!state.Inhibited, "Cancellation run rearms")
                state.SideDown(5, 111)
                Equal(state.Mask(111), 2, "Fresh gesture after cancellation works")
                Assert(state.SideUp(5, 111, true), "Fresh standalone after cancellation works")
            }
        }
    }
}

TestGestureEdges() {
    state := ChordState()
    Assert(state.Paused, "Starts paused")
    state.SideDown(4, 111, false)
    state.SetPaused(false)
    Equal(state.Mask(111), 0, "Resume while held is inhibited")
    Assert(!state.SideUp(4, 111, true), "Uncaptured held side cannot replay on resume")
    Assert(!state.Inhibited, "Resume rearms on final release")
    state.SideDown(4, 111)
    state.SideDown(4, 222, false)
    Equal(state.Sides[4].Target, 111, "Duplicate side down retains original target")
    for , button in ["LButton", "RButton", "MButton"] {
        Assert(state.PrimaryDown(button, true), "Each fresh primary down is accepted")
        Assert(!state.PrimaryDown(button, true), "Held primary does not repeat")
        Assert(state.PrimaryUp(button), "Suppressed click keeps suppressed release")
    }
    state.SideDown(5, 111)
    Assert(state.Sides[5].Used, "New side inherits already-used overlapping gesture")
    Assert(!state.SideUp(4, 111, true), "Used first side has no standalone action")
    Assert(!state.SideUp(5, 111, true), "Used joining side has no standalone action")

    state.SideDown(4, 111)
    state.PrimaryDown("LButton", false)
    Assert(!state.PrimaryUp("LButton"), "Unassigned combo preserves primary release")
    Assert(!state.SideUp(4, 111, true), "Unassigned combo still consumes standalone")
    state.SideDown(4, 111)
    Assert(!state.SideUp(4, 222, true), "Release in a different target cannot replay")
    state.SideDown(5, 111)
    state.PrimaryDown("RButton", true)
    state.SetPaused(true)
    Assert(!state.SideUp(5, 111, true), "Pause cancels standalone replay")
    Assert(state.PrimaryUp("RButton"), "Pause retains swallowed primary release")
    Equal(state.Mask(111), 0, "Paused state remains inactive")
    state.SetPaused(false)
    state.SideDown(5, 111)
    Assert(state.SideUp(5, 111, true), "Resumed fresh side works")
}

TestDuplicatePrimaryOwnership() {
    state := NewActiveState()
    state.PrimaryDown("LButton", false)
    state.SideDown(4, 111)
    Assert(!state.PrimaryDown("LButton", true), "Duplicate down rejected")
    Assert(!state.PrimaryUp("LButton"), "Passthrough down must retain passthrough up despite duplicate down")
}

TestValidMacros() {
    Equal(MacroModel.IDs.Length, 9, "Exactly nine mapping IDs")
    Equal(MacroModel.Parse("`n `; comment`r`n").Length, 0, "Blank and comments are unassigned")
    shortcuts := Map("a", "{a}", "A", "{a}", "F24", "{F24}", "Ctrl+Shift+S", "^+{s}",
        " control + alt + Delete ", "^!{Delete}", "Escape", "{Esc}",
        "Ctrl+Plus", "^{+}", "Backslash", "{\}", "Win+Left", "#{Left}",
        "Media_Play_Pause", "{Media_Play_Pause}", "NumpadEnter", "{NumpadEnter}")
    for source, expected in shortcuts
        Equal(MacroModel.Key(source), expected, "Shortcut " source)
    Equal(MacroModel.Key("Ctrl+C"), MacroModel.Key("ctrl+c"), "Letter capitalization must not add an implicit Shift")
    Equal(MacroModel.Key("Ctrl+V"), "^{v}", "Paste example must be Ctrl+V without implicit Shift")
    Equal(MacroModel.Key("Ctrl+S"), "^{s}", "Save must not silently become Save As")
    literal := "Café 日本語 🐭 ^!+#{Enter} `; literal"
    steps := MacroModel.Parse("; heading`r`nKEY Ctrl+C`r`nDeLaY 0`r`ntext " literal "`r`ndelay 60000")
    Equal(steps.Length, 4, "Case-insensitive operations and CRLF")
    Equal(steps[1].Kind, "key", "Key kind")
    Equal(steps[1].Value, "^{c}", "Key normalization")
    Equal(steps[2].Value, 0, "Zero delay supported")
    Equal(steps[3].Value, literal, "Unicode and raw-looking text remain literal")
    Equal(steps[4].Value, 60000, "Maximum step delay accepted")
    Equal(MacroModel.Summary(" `; comment`n`nkey F9`ntext later"), "key F9", "Summary skips comments")
    Equal(MacroModel.Summary(""), "Unassigned - normal click", "Unassigned summary")
    Equal(StrLen(MacroModel.Summary("text " RepeatText("x", 100))), 52, "Long summary truncation")
    Equal(MacroModel.Parse(RepeatText("key a`n", 200)).Length, 200, "200-step limit boundary")
    Equal(MacroModel.Parse(RepeatText("delay 60000`n", 5)).Length, 5, "Five-minute boundary")
}

RepeatText(value, count) {
    output := ""
    loop count
        output .= value
    return output
}

TestInvalidMacros() {
    invalidKeys := ["", "Ctrl", "Shift", "LWin", "F0", "F25", "Ctrl+", "Ctrl++", "+a",
        "Ctrl+Ctrl+A", "Ctrl+Control+A", "Ctrl+Alt+F12", "Alt+Ctrl+Shift+F12",
        "{a}", "{Ctrl down}", "a down", "a up", "a 10", "LButton", "XButton1", "WheelUp",
        "vk41", "sc01E", "U+0041", "Ctrl+{a}", "Ctrl+A+B", "A & B", "Run calc.exe"]
    for , value in invalidKeys
        Throws(() => MacroModel.Key(value), "Unsafe/invalid key accepted: " value)
    invalidSources := ["run calc.exe", "send ^c", "key", "text", "delay", "delay -1", "delay 1.5",
        "delay 1e3", "delay 0x10", "delay 60001", "delay 1 `; comment", "key a`nunknown step",
        "text " RepeatText("x", 1001), RepeatText("key a`n", 201), RepeatText("delay 60000`n", 6),
        RepeatText(";", 16001)]
    for , value in invalidSources
        Throws(() => MacroModel.Parse(value), "Invalid source accepted: " SubStr(value, 1, 60))
    try MacroModel.Parse("; first`n`nkey {a}")
    catch Error as err
        Assert(InStr(err.Message, "Line 3:"), "Validation reports original source line")
}

WithTempFolder(callback) {
    folder := A_Temp "\MouseMacroMapper-CoreTests-" ProcessExist() "-" A_TickCount
    DirCreate(folder)
    try callback.Call(folder)
    finally {
        ; This exact directory is created above solely for this test process.
        if !InStr(folder, A_Temp "\MouseMacroMapper-CoreTests-" ProcessExist() "-")
            throw Error("Refusing cleanup outside the test directory")
        DirDelete(folder, true)
    }
}

TestPersistence() => WithTempFolder(CheckPersistence)

CheckPersistence(folder) {
    path := folder "\mappings.ini"
    settings := MapperSettings(path)
    Assert(settings.Preserve && settings.Paused, "New settings default to preserved and paused")
    Equal(settings.Mappings.Count, 9, "New settings contain all mappings")
    for index, id in MacroModel.IDs {
        name := "映射 " id " — Café 🐭 é [x]=;"
        source := "; " name "`r`ntext Ελληνικά 日本語 🐭 ^!+#{Enter}`r`nkey Ctrl+Shift+S`r`ndelay " index
        settings.Mappings[id] := {Name: name, Source: source, Steps: MacroModel.Parse(source)}
    }
    settings.Preserve := false
    settings.Paused := false
    settings.Save()
    originalBytes := FileRead(path, "RAW")
    reloaded := MapperSettings(path)
    Equal(reloaded.LoadError, "", "Saved Unicode settings load")
    Assert(!reloaded.Preserve && !reloaded.Paused, "Preferences persisted")
    for , id in MacroModel.IDs {
        Equal(reloaded.Mappings[id].Name, settings.Mappings[id].Name, id " Unicode name")
        Equal(reloaded.Mappings[id].Source, settings.Mappings[id].Source, id " source byte meaning and CRLF")
        Equal(reloaded.Mappings[id].Steps.Length, 3, id " parsed steps reconstructed")
    }
    reloaded.Save()
    Equal(FileHex(path), BufferHex(originalBytes), "No-op save has identical bytes")
    reloaded.Mappings["45M"] := {Name: "", Source: "", Steps: []}
    reloaded.Preserve := true
    reloaded.Paused := true
    reloaded.Save()
    afterEdit := MapperSettings(path)
    Assert(afterEdit.Preserve && afterEdit.Paused, "Updated preferences replace old values")
    Equal(afterEdit.Mappings["45M"].Source, "", "Clearing one mapping persists")
    Equal(afterEdit.Mappings["4L"].Source, settings.Mappings["4L"].Source, "Unchanged mapping survives edit")
    Assert(!FileExist(path "." ProcessExist() ".tmp"), "Atomic save leaves no temporary file")
    for , value in ["", "plain", "Café 日本語 🐭", "`r`n`t=;[]", Chr(0x1F680)]
        Equal(MapperSettings.Decode(MapperSettings.Encode(value)), value, "Encoding round trip")
}

BufferHex(buffer) {
    output := ""
    loop buffer.Size
        output .= Format("{:02X}", NumGet(buffer, A_Index - 1, "UChar"))
    return output
}

FileHex(path) => BufferHex(FileRead(path, "RAW"))

TestCorruptSettings() => WithTempFolder(CheckCorruptSettings)

CheckCorruptSettings(folder) {
    corruptFiles := ["", "not an ini", "[Settings]`nVersion=99", "[Settings]`nVersion=1`nPreserve=yes",
        "[Settings]`nVersion=1`nPaused=-1", "[Settings]`nVersion=1`n[4L]`nName=0",
        "[Settings]`nVersion=1`n[4L]`nName=ZZ", "[Settings]`nVersion=1`n[4L]`nMacro=" MapperSettings.Encode("key {Ctrl down}"),
        "[Settings]`nVersion=1`n[4L]`nMacro=" MapperSettings.Encode("key F8") "`n[45M]`nMacro=" MapperSettings.Encode("delay 60001")]
    for index, content in corruptFiles {
        path := folder "\corrupt-" index ".ini"
        FileAppend(content, path, "UTF-8-RAW")
        before := FileHex(path)
        settings := MapperSettings(path)
        Assert(settings.LoadError != "", "Corrupt input produces a load error " index)
        Assert(settings.Paused, "Corrupt settings fail paused " index)
        Equal(settings.Mappings.Count, 9, "Safe defaults retained " index)
        for , mapping in settings.Mappings
            Equal(mapping.Source, "", "No partially loaded mappings " index)
        Equal(FileHex(path), before, "Load preserves corrupt original " index)
        Throws(() => settings.Save(), "Saving must refuse to overwrite corrupt original " index)
        Equal(FileHex(path), before, "Failed save preserves corrupt original " index)
        Assert(!FileExist(path "." ProcessExist() ".tmp"), "Refused save has no temporary file " index)
    }
    for , value in ["0", "GG", "01 02", RepeatText("00", 64001)]
        Throws(() => MapperSettings.Decode(value), "Invalid encoded mapping rejected")
}

TestCorruptEncoding() => WithTempFolder(CheckCorruptEncoding)

CheckCorruptEncoding(folder) {
    ; These bytes are valid hex, but not a lossless UTF-8 encoding of an AHK string.
    corruptBytes := ["FF", "C328", "F09F", "00", "6B6579206100746578742062"]
    for index, encoded in corruptBytes {
        path := folder "\encoding-" index ".ini"
        FileAppend("[Settings]`nVersion=1`n[4L]`nName=" encoded, path, "UTF-8-RAW")
        before := FileHex(path)
        settings := MapperSettings(path)
        Assert(settings.LoadError != "", "Lossy or truncated UTF-8 must fail load: " encoded)
        Assert(settings.Paused, "Invalid UTF-8 stays paused")
        Throws(() => settings.Save(), "Invalid UTF-8 cannot be replaced by altered decoded data")
        Equal(FileHex(path), before, "Invalid UTF-8 original preserved")
    }
}

TestLargeUnicodePersistence() => WithTempFolder(CheckLargeUnicodePersistence)

CheckLargeUnicodePersistence(folder) {
    source := ""
    loop 20
        source .= "text " RepeatText(Chr(0x4E00 + A_Index), 600) "`r`n"
    Equal(StrLen(source), 12140, "20 lines contain exactly 12,000 Chinese BMP characters plus syntax")
    Assert(StrLen(MapperSettings.Encode(source)) > 65535, "Fixture crosses Win32 profile value boundary")
    CheckBoundaryPersistence(folder, source, 20, "Chinese")
}

TestMaximumAsciiPersistence() => WithTempFolder(CheckMaximumAsciiPersistence)

CheckMaximumAsciiPersistence(folder) {
    source := ""
    loop 16
        source .= "text " RepeatText(Chr(96 + A_Index), 993) "`r`n"
    Equal(StrLen(source), 16000, "Fixture reaches exact supported source limit")
    CheckBoundaryPersistence(folder, source, 16, "ASCII")
}

CheckBoundaryPersistence(folder, source, expectedSteps, label) {
    path := folder "\boundary.ini"
    steps := MacroModel.Parse(source)
    Equal(steps.Length, expectedSteps, label " fixture parses")
    settings := MapperSettings(path)
    settings.Mappings["4L"] := {Name: label " boundary", Source: source, Steps: steps}
    settings.Save()
    original := FileHex(path)
    nativeValueLength := StrLen(IniRead(path, "4L", "Macro", ""))
    encodedLength := StrLen(MapperSettings.Encode(source))
    loaded := MapperSettings(path)
    FileAppend("INFO: " label " persistence source=" StrLen(source) " encoded=" encodedLength
        " native IniRead=" nativeValueLength " loaded source=" StrLen(loaded.Mappings["4L"].Source)
        " loaded steps=" loaded.Mappings["4L"].Steps.Length "`n", "*")
    Equal(loaded.LoadError, "", label " boundary load; source chars=" StrLen(source)
        " encoded chars=" encodedLength " native IniRead chars=" nativeValueLength)
    Equal(StrLen(loaded.Mappings["4L"].Source), StrLen(source), label " full source length retained; native IniRead=" nativeValueLength)
    Assert(loaded.Mappings["4L"].Source == source, label " source matches exactly")
    Equal(loaded.Mappings["4L"].Steps.Length, expectedSteps, label " all steps retained")
    loaded.Save()
    Equal(FileHex(path), original, label " no-op save preserves exact bytes")
}

TestSaveFailures() => WithTempFolder(CheckSaveFailures)

CheckSaveFailures(folder) {
    path := folder "\failure.ini"
    settings := MapperSettings(path)
    settings.Mappings["4L"] := {Name: "Original", Source: "key F8", Steps: MacroModel.Parse("key F8")}
    settings.Save()
    original := FileHex(path)
    settings.Mappings["4L"] := {Name: "Replacement", Source: "key F9", Steps: MacroModel.Parse("key F9")}
    temp := path "." ProcessExist() ".tmp"

    ; Deny sharing on the test-owned temporary output file to force FileOpen failure.
    tempHandle := DllCall("CreateFileW", "Str", temp, "UInt", 0xC0000000, "UInt", 0,
        "Ptr", 0, "UInt", 2, "UInt", 0x80, "Ptr", 0, "Ptr")
    Assert(tempHandle != -1, "Created exclusively held temporary-file fixture")
    try {
        Throws(() => settings.Save(), "Unwritable temporary output must report failure")
        Equal(FileHex(path), original, "Failed temporary write preserves original")
    } finally {
        DllCall("CloseHandle", "Ptr", tempHandle)
        if FileExist(temp)
            FileDelete(temp)
    }

    ; Permit reading the original but forbid deletion/replacement while this handle is open.
    originalHandle := DllCall("CreateFileW", "Str", path, "UInt", 0x80000000, "UInt", 1,
        "Ptr", 0, "UInt", 3, "UInt", 0x80, "Ptr", 0, "Ptr")
    Assert(originalHandle != -1, "Opened original with replacement denied")
    try {
        Throws(() => settings.Save(), "Failed atomic replacement must report failure")
        Equal(FileHex(path), original, "Failed replacement preserves original")
        Assert(!FileExist(temp), "Failed replacement cleans temporary output")
    } finally {
        DllCall("CloseHandle", "Ptr", originalHandle)
    }
    loaded := MapperSettings(path)
    Equal(loaded.Mappings["4L"].Source, "key F8", "Original still loads after failed writes")
    settings.Save()
    loaded := MapperSettings(path)
    Equal(loaded.Mappings["4L"].Source, "key F9", "Save succeeds after access restored")
    Assert(!FileExist(temp), "Recovered save leaves no temporary output")
}

TestNavigationPreferences() => WithTempFolder(CheckNavigationPreferences)

CheckNavigationPreferences(folder) {
    path := folder "\navigation.ini"
    settings := MapperSettings(path)
    Equal(settings.View, "Mouse", "New settings use mouse view")
    Equal(settings.Selected, "4L", "New settings select first mapping")
    for , view in ["Mouse", "List"] {
        for , selected in MacroModel.IDs {
            settings.View := view
            settings.Selected := selected
            settings.Save()
            loaded := MapperSettings(path)
            Equal(loaded.LoadError, "", "Navigation settings load")
            Equal(loaded.View, view, "View preference round trip")
            Equal(loaded.Selected, selected, "Mapping selection round trip")
        }
    }
    original := FileHex(path)
    settings.View := "Grid"
    Throws(() => settings.Save(), "Invalid in-memory view cannot be saved")
    Equal(FileHex(path), original, "Invalid view leaves existing file unchanged")
    settings.View := "List"
    settings.Selected := "invalid"
    Throws(() => settings.Save(), "Invalid in-memory selection cannot be saved")
    Equal(FileHex(path), original, "Invalid selection leaves existing file unchanged")

    legacyPath := folder "\legacy.ini"
    FileAppend("; Legacy generated settings with optional navigation fields absent`r`n"
        "[settings]`r`nversion = 1`r`npreserve=0`r`npaused=0`r`n[4l]`r`nname=" MapperSettings.Encode("旧配置")
        "`r`nmacro=" MapperSettings.Encode("key Ctrl+C"), legacyPath, "UTF-8")
    legacy := MapperSettings(legacyPath)
    Equal(legacy.LoadError, "", "Legacy case-insensitive sections and keys, whitespace, BOM, comments accepted")
    Equal(legacy.View, "Mouse", "Missing legacy View gets default")
    Equal(legacy.Selected, "4L", "Missing legacy Selected gets default")
    Assert(!legacy.Preserve && !legacy.Paused, "Legacy preferences retained")
    Equal(legacy.Mappings["4L"].Name, "旧配置", "Legacy Unicode label retained")
    Equal(legacy.Mappings["4L"].Source, "key Ctrl+C", "Legacy mapping retained")
    legacy.View := "List"
    legacy.Selected := "45M"
    legacy.Save()
    loaded := MapperSettings(legacyPath)
    Equal(loaded.View, "List", "Legacy file upgrades to explicit view")
    Equal(loaded.Selected, "45M", "Legacy file upgrades to explicit selection")
    Equal(loaded.Mappings["4L"].Name, "旧配置", "Legacy mapping survives upgrade")
}

TestIniStructure() => WithTempFolder(CheckIniStructure)

CheckIniStructure(folder) {
    invalidFiles := ["[Settings]`nVersion=1`nVersion=1", "[Settings]`nVersion=1`nversion=1",
        "[Settings]`nVersion=1`n[Settings]`nPreserve=1", "[Settings]`nVersion=1`n[4L]`nName=`n[4l]`nMacro=",
        "Version=1`n[Settings]", "[Settings`nVersion=1", "[ ]`nVersion=1", "[Settings]`nVersion=1`nmissing equals",
        "[Settings]`nVersion=1`n=emptykey", "[Settings]`nVersion=1`nPause`rd=0",
        "[Settings]`nVersion=1`nView=Grid", "[Settings]`nVersion=1`nView=", "[Settings]`nVersion=1`nView=mouse",
        "[Settings]`nVersion=1`nSelected=4X", "[Settings]`nVersion=1`nSelected=", "[Settings]`nVersion=1`nSelected=4l",
        "[Settings]`nVersion=1`n[4L]`nName=" RepeatText("A", 128011)]
    for index, content in invalidFiles {
        path := folder "\structure-" index ".ini"
        FileAppend(content, path, "UTF-8-RAW")
        original := FileHex(path)
        settings := MapperSettings(path)
        Assert(settings.LoadError != "", "Malformed/ambiguous INI must report failure " index)
        Assert(settings.Paused, "Malformed INI starts paused " index)
        Equal(settings.View, "Mouse", "Malformed INI retains safe default view " index)
        Equal(settings.Selected, "4L", "Malformed INI retains safe default selection " index)
        Throws(() => settings.Save(), "Malformed INI cannot overwrite original " index)
        Equal(FileHex(path), original, "Malformed INI bytes retained " index)
    }
    path := folder "\oversized.ini"
    stream := FileOpen(path, "w", "UTF-8-RAW")
    try stream.RawWrite(Buffer(4 * 1024 * 1024 + 1, 65))
    finally stream.Close()
    originalSize := FileGetSize(path)
    settings := MapperSettings(path)
    Assert(InStr(settings.LoadError, "4 MiB"), "Oversized settings rejected before parsing")
    Throws(() => settings.Save(), "Oversized settings cannot be overwritten")
    Equal(FileGetSize(path), originalSize, "Oversized original is retained")
}
