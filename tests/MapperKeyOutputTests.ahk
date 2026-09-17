#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include ../lib/MapperKeyOutput.ahk
#Include ../lib/HeldKeyOutput.ahk
#Include ../lib/MacroModel.ahk

; All sender effects and physical-state reads are injected. No hooks, windows,
; Send calls, settings access, or real keyboard/microphone changes occur.
global MapperOutputChecks := 0
global MapperOutputFailures := []
MapperOutputTest("held DOWN/UP use event output at level 1 and restore caller level", TestMapperOutputLevels)
MapperOutputTest("failed output and failed setup restore caller level", TestMapperOutputFailures)
MapperOutputTest("Shift+F9 preserves modifiers, shared ownership and reverse release", TestMapperOutputChord)
MapperOutputTest("failed UP stays retryable at correct level on every attempt", TestMapperOutputRetry)
FileAppend("Assertions: " MapperOutputChecks "`n", "*")
for , mapperOutputFailure in MapperOutputFailures
    FileAppend("FAIL: " mapperOutputFailure "`n", "*")
FileAppend(MapperOutputFailures.Length ? "RESULT: FAIL`n" : "RESULT: PASS`n", "*")
ExitApp(MapperOutputFailures.Length ? 1 : 0)

MapperOutputTest(label, callback) {
    global MapperOutputFailures
    try {
        callback.Call()
        FileAppend("PASS: " label "`n", "*")
    } catch Error as err {
        MapperOutputFailures.Push(label ": " err.Message " (line " err.Line ")")
    }
}

MapperOutputCheck(condition, message) {
    global MapperOutputChecks
    MapperOutputChecks += 1
    if !condition
        throw Error(message)
}

MapperOutputThrows(callback, expected) {
    actual := ""
    try callback.Call()
    catch Error as err {
        actual := err.Message
        if actual != expected
            FileAppend("Unexpected error at " err.File ":" err.Line ": " err.Extra "`n" err.Stack "`n", "*")
    }
    MapperOutputCheck(actual = expected, "Expected error '" expected "', got '" actual "'")
}

class MapperOutputSpy {
    __New(level := 0) {
        this.Level := level
        this.Events := []
        this.Writes := []
        this.FailEventOnce := ""
        this.FailSetupOnce := false
        this.Physical := Map()
        this.Sender := MapperKeyOutput(ObjBindMethod(this, "Event"),
            ObjBindMethod(this, "ReadLevel"), ObjBindMethod(this, "WriteLevel"))
        this.Held := HeldKeyOutput(ObjBindMethod(this.Sender, "SendHeldKey"),
            (key) => this.Physical.Has(key))
    }

    ReadLevel() => this.Level

    WriteLevel(level) {
        this.Level := level
        this.Writes.Push(level)
        if this.FailSetupOnce {
            this.FailSetupOnce := false
            throw Error("setup failed")
        }
    }

    Event(keys) {
        this.Events.Push({Keys: keys, Level: this.Level})
        if this.FailEventOnce = keys {
            this.FailEventOnce := ""
            throw Error("output failed")
        }
    }

    ExpectEvents(expected) {
        actual := ""
        for , event in this.Events {
            MapperOutputCheck(event.Level = 1, "Every held event uses SendLevel 1")
            actual .= event.Keys " "
        }
        MapperOutputCheck(actual = expected, "Expected '" expected "', got '" actual "'")
    }
}

TestMapperOutputLevels() {
    for , originalLevel in [0, 5] {
        spy := MapperOutputSpy(originalLevel)
        spy.Sender.SendHeldKey("F9", true)
        MapperOutputCheck(spy.Level = originalLevel, "DOWN restores original level")
        spy.Sender.SendHeldKey("F9", false)
        MapperOutputCheck(spy.Level = originalLevel, "UP restores original level")
        spy.ExpectEvents("{Blind}{F9 down} {Blind}{F9 up} ")
        MapperOutputCheck(spy.Writes.Length = 4 && spy.Writes[1] = 1
            && spy.Writes[2] = originalLevel && spy.Writes[3] = 1
            && spy.Writes[4] = originalLevel, "Each send has a scoped level change")
    }
    MapperOutputCheck(MapperKeyOutput.HeldSendLevel > 0, "Held output can reach default input-level hooks")
    MapperOutputCheck(MapperKeyOutput.ControlInputLevel >= MapperKeyOutput.HeldSendLevel,
        "Mapper keyboard controls exclude its own held output")
}

TestMapperOutputFailures() {
    for , down in [true, false] {
        spy := MapperOutputSpy(4)
        spy.FailEventOnce := "{Blind}{F9" (down ? " down}" : " up}")
        MapperOutputThrows(ObjBindMethod(spy.Sender, "SendHeldKey", "F9", down), "output failed")
        MapperOutputCheck(spy.Level = 4 && spy.Writes.Length = 2,
            "Failed keyboard output restores caller level")
        MapperOutputCheck(spy.Events.Length = 1 && spy.Events[1].Level = 1,
            "Failed event still uses intended send level")
    }
    spy := MapperOutputSpy(3)
    spy.FailSetupOnce := true
    MapperOutputThrows(() => spy.Sender.SendHeldKey("F9", true), "setup failed")
    MapperOutputCheck(spy.Level = 3 && !spy.Events.Length,
        "Partially failed level setup restores prior level without output")
}

TestMapperOutputChord() {
    spy := MapperOutputSpy(6)
    keys := MacroModel.HoldKeys(MacroModel.Parse("key Shift+F9"))
    MapperOutputCheck(keys.Length = 2 && keys[1] = "sc02A" && keys[2] = "sc043", "Shift+F9 canonical scan codes")
    MapperOutputCheck(spy.Held.Acquire("first", keys), "Shift+F9 hold begins")
    MapperOutputCheck(!spy.Held.Acquire("first", keys), "Duplicate DOWN does not repeat")
    MapperOutputCheck(spy.Held.Acquire("second", keys), "Another owner can share shortcut")
    spy.Held.Release("first")
    MapperOutputCheck(spy.Events.Length = 2 && spy.Held.Active, "One owner cannot release shared shortcut")
    spy.Held.Release("second")
    spy.ExpectEvents("{Blind}{sc02A down} {Blind}{sc043 down} {Blind}{sc043 up} {Blind}{sc02A up} ")
    MapperOutputCheck(!spy.Held.Active && spy.Level = 6, "Final release clears ownership and level")
    spy.Physical["sc043"] := true
    MapperOutputCheck(!spy.Held.Acquire("physical conflict", keys), "Physical key prevents synthetic takeover")
    MapperOutputCheck(spy.Events.Length = 4, "Physical conflict emits no extra key events")
}

TestMapperOutputRetry() {
    spy := MapperOutputSpy(2)
    keys := MacroModel.HoldKeys(MacroModel.Parse("key Shift+F9"))
    spy.Held.Acquire("hold", keys)
    spy.FailEventOnce := "{Blind}{sc043 up}"
    MapperOutputThrows(() => spy.Held.Release("hold"), "output failed")
    MapperOutputCheck(spy.Held.Active && spy.Level = 2, "Failed UP stays owned and restores caller level")
    spy.Held.ReleaseAll()
    spy.ExpectEvents("{Blind}{sc02A down} {Blind}{sc043 down} {Blind}{sc043 up} {Blind}{sc02A up} {Blind}{sc043 up} ")
    MapperOutputCheck(!spy.Held.Active && spy.Level = 2, "Retried cleanup releases remaining base key")
}
