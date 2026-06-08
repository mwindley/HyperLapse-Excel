# PREFERENCES.md — build lesson to add (Day 22)

**Paste as item 12 in the "Build lessons (carry forward)" list.**

---

12. **Giga mbed Wire: an I²C read to an absent device on a bus with
    no pull-ups can hard-fault the board, not just return an error.**
    (Day 22, Step 3 CAN bench.) Running CAN-only with the Tic
    controllers unwired, the FIRST hit on `/status` hard-faulted the
    Giga (red flashing LED) — because `buildStatusCSV()` calls
    `ticRear.getCurrentPosition()`, an I²C transaction to a Tic that
    wasn't on the bus and had no external pull-ups. Recovery: double-
    tap reset landed on a DFU COM port that would NOT connect; a
    **power-cycle** recovered cleanly on the normal port (add power-
    cycle as the fallback to the Day-18 double-tap note). This is
    worse than the documented "mbed Wire err=1 on NACK" behaviour —
    a *read* (not just a probe) to a truly absent device with floating
    SDA/SCL didn't return an error code, it crashed. Lessons:
    (a) when isolating a subsystem on the bench, guard EVERY access to
    the absent peripheral, not just `setup()` — runtime paths
    (`/status`, voltage polls, plan ticks) reach the bus too;
    (b) confirmed by before/after: adding the guard made `/status`
    work, so the empty-bus read was the cause, not coincidence;
    (c) the `STUB_<SUBSYSTEM>` pattern (STUB_CAN/BNO/WIRED_ETHERNET,
    now STUB_CART) is the right tool — define it, guard every touch
    point, and the bench has zero traffic from the absent hardware so
    a crash means what you think it means.
