#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include ../lib/HeldKeyOutput.ahk

; Pure output spies: no Send, hooks, windows, physical input, or settings access.
global HoldChecks := 0
global HoldFailures := []
HoldTest("shared modifier and base references", HoldSharedKeys)
HoldTest("reverse release order and duplicate owners", HoldReleaseOrder)
HoldTest("physical conflicts and physical takeover", HoldPhysicalKeys)
HoldTest("failed down rolls back only its owner", HoldFailedDown)
HoldTest("failed up remains owned and retries", HoldFailedUp)
HoldTest("ReleaseAll attempts other owners after failure", HoldReleaseAllFailure)
HoldTest("failed down and rollback up stay retryable", HoldFailedRollback)
FileAppend("Assertions: " HoldChecks "`n", "*")
for , holdTestFailure in HoldFailures
    FileAppend("FAIL: " holdTestFailure "`n", "*")
FileAppend(HoldFailures.Length ? "RESULT: FAIL`n" : "RESULT: PASS`n", "*")
ExitApp(HoldFailures.Length ? 1 : 0)

HoldTest(label, callback) {
    global HoldFailures
    try {
        callback.Call()
        FileAppend("PASS: " label "`n", "*")
    } catch Error as err {
        HoldFailures.Push(label ": " err.Message " (line " err.Line ")")
    }
}

HoldCheck(condition, message) {
    global HoldChecks
    HoldChecks += 1
    if !condition
        throw Error(message)
}

HoldThrows(callback, expected) {
    caught := ""
    try callback.Call()
    catch Error as err
        caught := err.Message
    HoldCheck(caught = expected, "Expected error '" expected "', got '" caught "'")
}

class HoldOutputSpy {
    __New() {
        this.Events := ""
        this.PhysicallyDown := Map()
        this.FailOnce := Map()
        this.Output := HeldKeyOutput(ObjBindMethod(this, "Emit"), ObjBindMethod(this, "Physical"))
    }

    Emit(key, down) {
        event := key (down ? "+" : "-")
        this.Events .= event " "
        if this.FailOnce.Has(event) {
            this.FailOnce.Delete(event)
            throw Error(event " failed")
        }
    }

    Physical(key) => this.PhysicallyDown.Has(key)

    Expect(events) {
        HoldCheck(this.Events = events, "Expected output '" events "', got '" this.Events "'")
    }
}

HoldSharedKeys() {
    spy := HoldOutputSpy(), output := spy.Output
    HoldCheck(output.Acquire("first", ["LCtrl", "K"]), "First hold starts")
    HoldCheck(output.Acquire("second", ["LCtrl", "K"]), "Identical shortcut overlaps")
    HoldCheck(output.Acquire("third", ["LCtrl", "J"]), "Modifier shared across shortcuts")
    spy.Expect("LCtrl+ K+ J+ ")
    output.Release("first")
    spy.Expect("LCtrl+ K+ J+ ")
    output.Release("third")
    spy.Expect("LCtrl+ K+ J+ J- ")
    HoldCheck(output.Active, "Shared base remains held")
    output.Release("second")
    spy.Expect("LCtrl+ K+ J+ J- K- LCtrl- ")
    HoldCheck(!output.Active, "Final owner fully releases shortcut")
}

HoldReleaseOrder() {
    spy := HoldOutputSpy(), output := spy.Output
    output.Acquire(1, ["LCtrl", "LShift", "K"])
    HoldCheck(!output.Acquire(1, ["J"]), "Duplicate owner does not change hold")
    output.Release(1)
    spy.Expect("LCtrl+ LShift+ K+ K- LShift- LCtrl- ")
    HoldCheck(!output.Release(1), "Repeated release is inert")
    HoldCheck(output.ReleaseAll(), "Empty release-all succeeds")
    spy.Expect("LCtrl+ LShift+ K+ K- LShift- LCtrl- ")
}

HoldPhysicalKeys() {
    spy := HoldOutputSpy(), output := spy.Output
    spy.PhysicallyDown["K"] := true
    HoldCheck(!output.Acquire(1, ["LCtrl", "K"]), "Physical base rejects whole shortcut")
    HoldCheck(!output.Active, "Rejected shortcut owns nothing")
    spy.Expect("")
    spy.PhysicallyDown.Delete("K")
    output.Acquire(1, ["LCtrl", "K"])
    spy.PhysicallyDown["LCtrl"] := true
    HoldCheck(!output.Acquire(2, ["LCtrl", "J"]), "Physical modifier also rejects overlap")
    output.Release(1)
    spy.Expect("LCtrl+ K+ K- ")
    HoldCheck(!output.Active, "Physical modifier takeover relinquishes injected ownership")
    output.ReleaseAll()
    spy.Expect("LCtrl+ K+ K- ")
}

HoldFailedDown() {
    spy := HoldOutputSpy(), output := spy.Output
    output.Acquire("existing", ["LCtrl", "J"])
    spy.FailOnce["K+"] := true
    HoldThrows(() => output.Acquire("failing", ["LCtrl", "K"]), "K+ failed")
    spy.Expect("LCtrl+ J+ K+ K- ")
    HoldCheck(output.Active && !output.Owners.Has("failing"), "Rollback preserves only prior owner")
    HoldCheck(output.References["LCtrl"] = 1, "Rollback restores shared reference count")
    output.ReleaseAll()
    spy.Expect("LCtrl+ J+ K+ K- J- LCtrl- ")
    HoldCheck(!output.Active, "Existing owner releases normally")
}

HoldFailedUp() {
    spy := HoldOutputSpy(), output := spy.Output
    output.Acquire(1, ["LCtrl", "K"])
    spy.FailOnce["K-"] := true
    HoldThrows(() => output.Release(1), "K- failed")
    spy.Expect("LCtrl+ K+ K- LCtrl- ")
    HoldCheck(output.Active && output.Owners[1].Length = 1, "Only failed key remains owned")
    HoldCheck(output.References.Has("K") && !output.References.Has("LCtrl"), "Successful cleanup is forgotten")
    output.ReleaseAll()
    spy.Expect("LCtrl+ K+ K- LCtrl- K- ")
    HoldCheck(!output.Active, "Retry releases failed key")
}

HoldReleaseAllFailure() {
    spy := HoldOutputSpy(), output := spy.Output
    output.Acquire(1, ["LCtrl", "K"])
    output.Acquire(2, ["LAlt", "J"])
    spy.FailOnce["K-"] := true
    HoldThrows(() => output.ReleaseAll(), "K- failed")
    spy.Expect("LCtrl+ K+ LAlt+ J+ K- LCtrl- J- LAlt- ")
    HoldCheck(output.Active && output.Owners.Count = 1, "Failure does not prevent second owner cleanup")
    output.ReleaseAll()
    spy.Expect("LCtrl+ K+ LAlt+ J+ K- LCtrl- J- LAlt- K- ")
    HoldCheck(!output.Active, "Release-all retry clears retained key")
}

HoldFailedRollback() {
    spy := HoldOutputSpy(), output := spy.Output
    spy.FailOnce["K+"] := true
    spy.FailOnce["K-"] := true
    HoldThrows(() => output.Acquire(1, ["LCtrl", "K"]), "K+ failed")
    spy.Expect("LCtrl+ K+ K- LCtrl- ")
    HoldCheck(output.Active && output.References["K"] = 1, "Failed rollback preserves retryable ownership")
    output.ReleaseAll()
    spy.Expect("LCtrl+ K+ K- LCtrl- K- ")
    HoldCheck(!output.Active, "Final retry cleans failed rollback")
}
