# WORKFRONTS.md — Day 24 (part A) addendum

**Append to the Day-24 (part A) update block, under its "New
workfront" area (after #70). The decision record below pastes into the
resolved-architecture region near the top, in the style of "Comms-outage
fallback architecture (Day 15 — resolved)".**

---

## New workfront (continues Day-24 part A list)

- **NEW #71 Firing-hold for manual camera LAN reconnect (Execution
  UI).** The Canon R3 does not auto-reconnect to the AP when WiFi
  returns — recovery is a manual menu sequence on the camera body
  (~3 clicks), and Canon's own networking docs warn against operating
  the camera during connection setup. Real-world: a LAN drop far out
  can leave the camera offline for the rest of the night, and the
  operator cannot complete the manual reconnect while the cart is
  actively firing at the camera. **Requirement:** an operator-asserted
  **firing hold** in the Execution UI that idles EVERY active firing
  path — CCAPI traffic (Tv/ISO PUTs, GETs, photo POSTs), pin-D7
  pulses, and any running plan's frame pushes — for the duration of
  the manual reconnect, then resumes firing by whatever transport is
  live in that build. Single global hold, transport-agnostic (it
  pauses everything live, doesn't special-case a transport).
  - **In direct tension with the "always fire" objective by design:**
    the hold is a deliberate, operator-chosen firing gap. Accepted as
    the cost of recovering a camera that is otherwise lost for the
    night (a short gap beats an indefinite one). Kept honest only by
    making the gap short and operator-controlled.
  - **Open (defer detail):** manual-only vs also auto-detect (a run of
    failed CCAPI calls auto-asserts the hold); resume manual vs gentle
    auto-probe; plan interaction (does a mid-execution plan hold or
    keep moving while firing is idled).
  - **Dependency:** definition-of-done waits on the #63 edge-finding
    soak verdict. If WiFi at real field range drops often, that bears
    on whether WiFi CCAPI can be the production transport at all,
    which reshapes this feature. **Scaffold now, finalise after soak.**
  - Lives with #70 (soak run protocol) and the transport ladder
    decision below.

---

## Camera-loss recovery + transport ladder (Day 24 — recorded)

**For the resolved-architecture region near the top of WORKFRONTS.md.**

**Objective:** always fire; minimum cables.

**Transport ladder — soak-adjudicated, ship one:** The firing-transport
options form a priority ladder. Each rung stays built in the codebase
as a compile/runtime option; soak results decide which one ships.
Lower rungs are retired (archived, not deleted) if a higher rung
passes its soak.

1. **WiFi CCAPI over AX6000 (no cables) — preferred.** Currently in
   soak (#63). If it passes the field edge-finding soak, it ships and
   the rungs below are archived.
2. **Wired HTTP CCAPI — archived.** Promoted to a full soak only if
   WiFi CCAPI fails its soak. If it then passes, it ships.
3. **Pin-D7 hardware shutter — archived.** Reaches production only if
   BOTH CCAPI transports fail their soaks.

This is a single-transport production ship, not a runtime-layered
stack — the rungs are competing candidates for one production slot.
(Consistent with the Day-23 note: "production ships one transport;
soak each, then pick.")

**R3 reconnect behaviour — established (Day 24, from Canon docs +
field experience):** The EOS R3 does not auto-rejoin the AP after a
WiFi drop. Across the EOS R line (R1/R5/R6 III siblings), Canon's
documented reconnect is always a manual menu action — select
Connection settings → saved SET → Connect — with connection settings
*retained* (fast) but not *automatic*. The WFT-R10 (pro networking
accessory) guide explicitly states operating the shutter/controls
during connection configuration closes the wizard and is not allowed
— documenting the same camera-input vs firing-activity collision seen
in the field. Conclusion: recovery is manual and cannot proceed while
the cart fires → motivates the #71 firing hold.

**Implication captured:** because the production build may ship as
CCAPI-only (if WiFi CCAPI wins), the firing hold cannot assume a D7
path is firing underneath to keep frames alive during the hold — in a
CCAPI-only build the hold is a true firing gap. In a build where D7 is
still present, the hold idles that too (the camera's UI fights ALL
firing activity, not just network traffic). Hence the hold is defined
as transport-agnostic: idle whatever is live.
