# On-device injection prototype — build & test

Goal: prove that GameAssistant can be injected **entirely on-device**
(no PC), using the wireless-debugging adb path that the wuyr tool
implements. If this works, we lift the mechanism into ClusterTune.

We do NOT write the adb/pairing/JDWP stack from scratch — we reuse
wuyr's proven, compiling implementation and change only the payload.

---

## What proves success

After injecting GameAssistant, the agent should start and write a status
file. Success = this shows up (readable over on-device terminal or adb):

```
/sdcard/ClusterTune/ct_status   ->   contains "idle" or "ok ..."
```

That file existing and updating = the agent is running as system,
launched fully on-device. That's the whole thing we're proving.

---

## Step 0 — First smoke test (zero build, optional but recommended)

Before building anything, sanity-check that wuyr's mechanism even sees
GameAssistant on your device:

1. Download wuyr's prebuilt demo: `app-debug.apk` from
   https://github.com/wuyr/jdwp-injector-for-android
2. Install it, open it, follow its wireless-pairing guide (this uses
   Android's built-in Wireless Debugging — no PC).
3. When the app list loads, look for **com.odin2.gameassistant**.
   - If GameAssistant appears and you can select it → the transport
     reaches it. (Their demo payload shows a dialog/toast, which GA may
     not render — so a missing toast isn't failure. The point is: does
     it appear and inject without a transport error.)

If GameAssistant shows up here, the on-device path is viable and the
tailored build below is worth doing.

---

## Step 1 — Fork and add our payload

1. Fork `wuyr/jdwp-injector-for-android`.
2. Find their demo payload class (the one containing `showDialog()` —
   per the README it's `app/src/main/java/com/wuyr/jdwp_injector_test/`,
   file `Drug.kt`).
3. Add `ClusterTunePayload.kt` (provided) alongside it, OR replace the
   body of their existing payload function with our `launchAgent()` body.

   **Match their injection entry point.** wuyr's injector invokes a
   specific class + method after loading the payload dex. Wherever their
   demo points the injector at `Drug` / `showDialog`, point it instead at
   `ClusterTunePayload` / `launchAgent` (look in their Activity for where
   the entry class/method names are passed to the injector — search the
   repo for `showDialog` and `Drug` and swap to our names).

   The `application` field: their demo injects a reference to the
   target's Application. Keep the same wiring for `ClusterTunePayload.application`.

## Step 2 — Add CI to build it

1. Add the provided `build-apk.yml` at `.github/workflows/build-apk.yml`.
2. Push. The Actions run produces `jdwp-injector-debug-apk` as an
   artifact. Download + install it on the Odin.

## Step 3 — Pre-place the agent (the bug fix)

The earlier failure was cramming the agent through JDWP as one huge
string. Instead, put the agent on /sdcard first, so injection only runs
a short launch command.

On the device (via any on-device terminal, or once via adb):

```
mkdir -p /sdcard/ClusterTune
# copy ct_agent.sh into /sdcard/ClusterTune/ct_agent.sh
chmod 644 /sdcard/ClusterTune/ct_agent.sh
```

(When we integrate into ClusterTune, the app writes this file itself.)

## Step 4 — Inject

1. Make sure GameAssistant is running (open it once).
2. In the forked injector app: pair wireless debugging (if not already),
   select **com.odin2.gameassistant**, run the injection.
3. The payload runs `nohup sh /sdcard/ClusterTune/ct_agent.sh &` as
   system inside GA.

## Step 5 — Verify

Check the status file:

```
cat /sdcard/ClusterTune/ct_status
```

- `idle (no request file)` → agent is running, waiting for a profile.
- Now drop a test profile and watch it apply:

```
printf 'P0=1555200\nP3=2188800\nP7=2342400\n' > /sdcard/ClusterTune/ct_profile
# wait ~3s
cat /sys/devices/system/cpu/cpufreq/policy7/scaling_max_freq   # expect 2342400
cat /sdcard/ClusterTune/ct_status                              # expect "ok ..."
```

If `ct_status` shows `ok` and the frequency changed — **the entire
on-device, no-root, no-PC path is proven.**

---

## If something fails

- **GameAssistant not in the injector's list:** it may need to be
  running first; also confirm wireless debugging is on and paired.
- **Injection connects but agent never starts (`ct_status` absent):**
  confirm the agent file is actually at `/sdcard/ClusterTune/ct_agent.sh`
  and readable; check `logcat -s CT_AGENT` for agent output.
- **Entry point mismatch / crash:** the payload class/method names must
  match what the injector invokes. Re-check Step 1's entry-point note.

Capture any error text and we'll adjust.

---

## After it's proven

Phase 2: lift wuyr's `jdwp-injector` module into ClusterTune, add the
3-profile UI + agent bridge + the file-writing of ct_agent.sh, so the
whole flow needs only ClusterTune + wireless debugging.
