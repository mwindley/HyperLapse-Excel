# PREFERENCES.md — Build lessons 12 & 13

**Append to the "## Build lessons (carry forward)" numbered list,
after lesson 11.**

---

12. **Append new fields to a positional CSV surface; never insert.**
    `/status` is parsed by index in two places (Excel and the Cart
    Recon UI JS, `v[4]`, `v[6]`, `v[8]`…). Adding live RSSI + BNO cal
    status was done by appending them as idx 13/14 at the *end* of
    `buildStatusCSV()`, leaving every existing index untouched — so no
    consumer needed changing. Inserting a field mid-string would have
    silently shifted every later index and broken both parsers at once,
    with no compile error (it's all string splitting). Same discipline
    for the soak CSV: the rssi column already existed (HB-only), so
    populating it on every row changed the *data*, not the *schema* —
    `/soak/dump` archives and the summary parser stayed compatible.
    Rule: positional surfaces grow at the tail. (Day 24.)

13. **Giga free-heap: use `mallinfo().uordblks`, not
    `mbed_stats_heap_get()`.** For the #63 soak leak-watch, the obvious
    `mbed_stats_heap_get()` returns zero unless mbed heap-stats were
    enabled at core-build time (they aren't by default on the Arduino
    GIGA core) — it compiles and runs but reads 0, giving false
    reassurance. `mallinfo().uordblks` (newlib `<malloc.h>`, always
    linked) reports bytes-currently-allocated with no build flag, and
    is the reliable leak signal: flat in steady state, climbs on a
    leak. Caveat — mallinfo does NOT expose largest-free-block, so pure
    *fragmentation* (heap not growing, but no single chunk big enough)
    won't show as drift; it surfaces instead as an allocation-failure
    stall. So leak-watch (heap drift) and stall-watch (timestamp gap)
    are complementary, not redundant. First soak (2 h, close range)
    read drift = 0, dead-flat at 25,288 bytes. Always sanity-check the
    heap column shows a plausible nonzero (tens of KB) on the first
    tail before committing hours — a 0 means the call isn't live.
    (Day 24.)
