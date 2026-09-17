; Pure gesture state. No input is emitted here; matching releases retain ownership.
class ChordState {
    __New() {
        this.Sides := Map(4, this.NewSide(), 5, this.NewSide())
        this.Primary := Map("LButton", false, "RButton", false, "MButton", false)
        this.Blocked := Map("LButton", false, "RButton", false, "MButton", false)
        this.Paused := true
        this.Inhibited := false
        this.Epoch := 0
        this.GestureUsed := false
    }

    NewSide() => {Down: false, Captured: false, Used: false, Target: 0, Epoch: -1}

    AnySide() => this.Sides[4].Down || this.Sides[5].Down

    AllReleased() {
        for , down in this.Primary
            if down
                return false
        return !this.AnySide()
    }

    SideDown(id, target, captured := true) {
        if this.Sides[id].Down
            return
        if !this.AnySide()
            this.GestureUsed := false
        used := this.GestureUsed
        for , down in this.Primary
            used := used || down
        this.Sides[id] := {Down: true, Captured: captured, Used: used,
            Target: target, Epoch: this.Epoch}
    }

    SideUp(id, target, preserve) {
        side := this.Sides[id]
        replay := side.Down && side.Captured && !side.Used && preserve
            && !this.Paused && !this.Inhibited && side.Target = target
            && side.Epoch = this.Epoch
        this.Sides[id] := this.NewSide()
        this.Rearm()
        return replay
    }

    Mask(target) {
        if this.Paused || this.Inhibited
            return 0
        mask := 0
        for id, side in this.Sides {
            if !side.Down
                continue
            if !side.Captured || side.Target != target || side.Epoch != this.Epoch
                return 0
            mask |= id = 4 ? 1 : 2
        }
        return mask
    }

    UseSides() {
        if this.AnySide()
            this.GestureUsed := true
        for , side in this.Sides
            if side.Down
                side.Used := true
    }

    PrimaryDown(button, blocked := false) {
        fresh := !this.Primary[button]
        this.Primary[button] := true
        if fresh
            this.Blocked[button] := blocked
        this.UseSides()
        return fresh
    }

    PrimaryUp(button) {
        blocked := this.Blocked[button]
        this.Primary[button] := false
        this.Blocked[button] := false
        this.Rearm()
        return blocked
    }

    Cancel() {
        this.Epoch += 1
        this.UseSides()
        this.Inhibited := !this.AllReleased()
    }

    SetPaused(value) {
        this.Paused := !!value
        this.Cancel()
    }

    Rearm() {
        if this.AllReleased() {
            this.Inhibited := false
            this.GestureUsed := false
        }
    }
}
