#Requires AutoHotkey v2.0

; Output ownership only: callers supply canonical, unique keys in press order.
; Callbacks make this model usable with either real or fully mocked output.
class HeldKeyOutput {
    __New(emitCallback, physicalCallback) {
        this.Emit := emitCallback
        this.Physical := physicalCallback
        this.Owners := Map()
        this.References := Map()
    }

    Active => this.Owners.Count > 0

    Acquire(owner, keys) {
        if this.Owners.Has(owner) || !keys.Length
            return false
        unique := Map()
        for , key in keys {
            if Type(key) != "String" || key = "" || unique.Has(key)
                throw ValueError("Held keys must be unique canonical key names.")
            unique[key] := true
            if this.Physical.Call(key)
                return false
        }

        this.Owners[owner] := []
        try {
            for , key in keys {
                ; Own each potentially emitted DOWN before calling external code.
                this.Owners[owner].Push(key)
                count := this.References.Has(key) ? this.References[key] : 0
                this.References[key] := count + 1
                if !count
                    this.Emit.Call(key, true)
            }
        } catch Error as err {
            ; A DOWN may have succeeded before the callback raised. Try every UP.
            ; Failed cleanup remains owned, so ReleaseAll can retry it later.
            try this.Release(owner)
            catch Error {
            }
            throw err
        }
        return true
    }

    Release(owner) {
        if !this.Owners.Has(owner)
            return false
        keys := this.Owners[owner]
        failure := 0
        index := keys.Length
        while index > 0 {
            key := keys[index]
            count := this.References[key]
            try {
                ; Never release another owner's key or a currently physical key.
                if count = 1 && !this.Physical.Call(key)
                    this.Emit.Call(key, false)
                if count = 1
                    this.References.Delete(key)
                else
                    this.References[key] := count - 1
                keys.RemoveAt(index)
            } catch Error as err {
                if !failure
                    failure := err
            }
            index -= 1
        }
        if !keys.Length
            this.Owners.Delete(owner)
        if failure
            throw failure
        return true
    }

    ReleaseAll() {
        owners := []
        for owner in this.Owners
            owners.Push(owner)
        failure := 0
        for , owner in owners {
            try this.Release(owner)
            catch Error as err {
                if !failure
                    failure := err
            }
        }
        if failure
            throw failure
        return !this.Active
    }
}
