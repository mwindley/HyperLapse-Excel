# Canon CCAPI v1.4.0 - shutterbutton / AF / metering / drive (SOURCE OF TRUTH)

Read from the Canon Camera Control API Reference v1.4.0 Rev1.3 (the ref250/500/
750/920 PDFs). These are the camera-side facts behind the FIRE-STALL clue: the
POST shutterbutton intermittently stalls (recv times out ~2s, status 0, next
fire 503) while the GET flipdetail meter NEVER stalls.

## 4.8.1 Still image shooting  POST /shooting/control/shutterbutton
Body: { "af": boolean }   (AF enable/disable). Response 200 = empty JSON object.
This is the call we fire. The body {"af":false} is valid (12 bytes).

### Its error responses (THE CLUE):
400 Invalid parameter - af is illegal/non-boolean.
503 with one of these messages:
  - "Device busy"                 function temporarily unavailable
  - "During shooting or recording" shooting/recording in progress
  - "Mode not supported"          request invalid in current mode
  - "Taken in preparation"        Service preparation in progress. "When the API
                                  first called in the connection standby state
                                  was this API (the connection is NOT yet
                                  complete, so the process cannot be accepted)."
  - "Out of focus"               AF focusing FAILED during shooting.
  - "Can not write to card"      Data could not be recorded on the media during
                                  shooting.

### Why this explains the stall (measured signature: connect OK, recv=1999, st=0,
### close slow, next fire 503):
The shutterbutton POST triggers a PHYSICAL shooting operation. The camera accepts
the TCP connection and the request, then must ACTUATE + AF + EXPOSE + WRITE TO
CARD before it can answer. While it is mid-operation it holds the HTTP response.
If that exceeds our 2s recv timeout we see recv=1999/status 0 (a stall), and the
NEXT fire that lands while the camera is still busy gets 503 "During shooting or
recording". The meter (GET flipdetail) reads live-view info and triggers NO
shooting operation, so it NEVER blocks - exactly what the trace shows.
Two named conditions map directly to the recurring stalls:
  - "Can not write to card" -> a card write (periodic, ~every few seconds at
    0.5s exposure) blocks the response = the ~5-frame-spaced recv stalls.
  - "Taken in preparation" -> the FIRST call on a fresh connection can be
    rejected/blocked = the cold-start stall (the ISO setup call, and #50).

## 4.8.2 Still image shutter button control  POST .../shutterbutton/manual
Body: { "action": string, "af": boolean }
  action: "release" | "half_press" | "full_press"
This is the SPLIT-PHASE alternative: half_press (AF + meter, no exposure) then
full_press (expose) then release. Lets AF/metering happen in a SEPARATE call from
the exposure - so the exposure call no longer carries the AF/focus delay.

## 4.9.14 AF operation  /shooting/settings/afoperation  (GET/PUT)
Values: oneshot (One-shot AF), servo (Servo AF), aifocus (AI Focus AF),
        manual (Manual focus).
With af:true the shutterbutton does AF before exposing; oneshot waits for focus
lock, which can add delay or fail ("Out of focus"). manual = no AF attempt.

## 4.9.23 Metering mode  /shooting/settings/metering  (GET/PUT)
Values: evaluative (Evaluative metering), partial, spot,
        center_weighted_average.

## 4.9.24 Continuous shooting mode (DRIVE)  /shooting/settings/drive  (GET/PUT)
Values include: single (Single shooting), highspeed, continuous, lowspeed,
        silent variants, self_10sec, self_2sec, self_continuous.
single = one frame per shutterbutton press (what a timelapse wants).

## WHAT THIS MEANS FOR THE FIRE PATH (the lever, not yet a fix)
The fire stalls because the single shutterbutton POST bundles AF + exposure +
card write and the camera holds the HTTP response until all are done. To make the
fire return fast and predictably:
  1. af:false + Manual focus (afoperation=manual) -> the POST does NO AF, removing
     the AF/"Out of focus" delay. (We already send af:false; confirm focus mode.)
  2. drive=single, oneshot off -> no continuous/servo overhead per frame.
  3. The card-write block ("Can not write to card" path) is the camera writing
     the RAW/JPEG; at 0.5s exposure every 2s the write can collide with the next
     fire. This is the periodic recv stall. Levers: image quality/size (smaller
     write), faster card, or split-phase (4.8.2) so the exposure call returns
     before the write completes.
The meter never stalls because it touches none of this - it is the control.
