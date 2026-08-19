# M7 — Performance profiling playbook

**Why this exists:** performance can only be measured on a real device in a
`--profile` build (debug builds are meaninglessly slow; the simulator/emulator
misrepresents GPU and startup). Claude can't run this headlessly, so **you run
the three passes below on your phone/iPad and send back the artifacts**, then we
delegate measured fixes from the traces. This is hypothesis-driven: each pass
lists what we already suspect so we confirm/deny rather than guess.

- **App:** ZIVO (`com.ziadelsewedy.zivo`), Flutter 3.44.2
- **Device:** any physical device (iPhone/iPad or Android). **Not** the
  simulator/emulator. Unlock it and plug in via cable.
- **Configuration: Profile.** Everything below runs the **Profile** build config
  (`--profile` + `config/profile.json`), never Development or Release. See
  [../build_configurations.md](../build_configurations.md) for why Profile is
  the correct M7 config. In Profile, App Check runs **real attestation** (App
  Attest / Play Integrity) — production-like on purpose, so startup isn't
  misleading. The easiest launch is `make profile` or the **ZIVO · Profile (M7)**
  entry in `.vscode/launch.json`.

Find your device id once:

```bash
flutter devices
```

Then use it as `-d <id>` below (e.g. `-d 00008030-XXXX` for an iPhone).

---

## Pass 1 — Cold start (time to first frame)

**Hypothesis:** `lib/main.dart` `await`s **both** `Firebase.initializeApp` and
`FirebaseAppCheck.instance.activate` before `runApp` — two serial network-ish
init calls blocking the first frame. We expect this to dominate cold start.

Run (or use the helper `scripts/perf/trace_startup.sh <device-id>`):

```bash
flutter run --profile --trace-startup --dart-define-from-file=config/profile.json -d <device-id>
```

Let the app reach the home screen, then press `q` to quit. Flutter writes
`build/start_up_info.json`. **Send that file.** The numbers that matter:

- `timeToFrameworkInitMicros` — Dart/framework boot
- `timeToFirstFrameMicros` — until the first frame is on screen (the headline)
- `timeToFirstFrameRasterizedMicros`

Do this **3 times** (first launch after install is worst; then warm launches)
and send all three JSONs so we see cold vs warm.

---

## Pass 2 — Scroll / interaction jank

**Hypothesis:** the list surfaces rebuild and lay out grouped lists on every
stream emit; Today composes several streams. Look for dropped frames while
scrolling and while data updates.

1. Launch in profile with the DevTools URL printed:
   ```bash
   flutter run --profile --dart-define-from-file=config/profile.json -d <device-id>
   ```
   Copy the **"A Dart VM Service is available at: …"** URL and open DevTools:
   ```bash
   dart devtools
   ```
   (paste the URL), or open the link the run prints.
2. In DevTools → **Performance** tab, tick **"Track layouts"** if offered, press
   **Record**, then on the device:
   - Scroll **Expenses** and **Schedule** hard (they group by day + subtotals).
   - Scroll **Moments** (image cards) and **Workout history**.
   - Open **Today** and pull-to-refresh / let data settle.
3. Press **Stop**, then **Export** the timeline (the ⬇ / "Save" button →
   `.json`). **Send that export.**
4. Turn on the on-device overlay too — in the `flutter run` console press **`P`**
   (performance overlay). Screenshot any surface where the **top (UI) or bottom
   (raster) bar spikes past the green line**. Note: 60fps budget = 16ms/frame;
   on a ProMotion iPad it's 120fps = **8ms**.

**Send:** the timeline `.json` export + screenshots of the worst frames /
overlay spikes, with a note of which screen + gesture caused each.

---

## Pass 3 — Rebuild audit

**Hypothesis:** Today's nested `StreamBuilder`s (profile + tasks + university +
schedule) and the per-row list widgets rebuild more than necessary on each emit.

1. With the profile build + DevTools open, go to **Flutter Inspector**.
2. Enable **"Track widget rebuild counts"** (a.k.a. "Highlight repaints" /
   "Track Widget Builds" depending on DevTools version).
3. Interact for ~30s: toggle a task done, add an expense, open Today.
4. Screenshot the rebuild-count panel (the widgets with the highest counts) and
   note anything rebuilding that visually didn't change.

**Send:** the rebuild-count screenshots.

---

## What to send back (checklist)

Drop everything in a reply (or into `docs/performance/traces/` and mention it):

- [ ] 3× `build/start_up_info.json` (cold + warm)
- [ ] DevTools Performance timeline `.json` export (Pass 2)
- [ ] Worst-frame / overlay-spike screenshots, labelled by screen + gesture
- [ ] Rebuild-count screenshots (Pass 3)
- [ ] Device model + OS version, and whether ProMotion (120Hz)

Fill the headline numbers into `M7_results_template.md` as you go — that's what
we'll turn into a prioritized fix list.

---

## What happens next

From the artifacts we'll: confirm/deny the cold-start hypothesis (and if
confirmed, move App Check activation off the critical path / parallelize init),
fix the top rebuild offenders (e.g. split/`const` widgets, narrow `StreamBuilder`
scopes, add keys), and address any raster-heavy frames. Each fix lands as its
own reviewed, gated commit — same as every milestone.
