import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The device-activity seam for the Today dashboard: today's step count as a
/// live stream. An interface so widget tests can inject a fake without
/// touching CoreMotion/Google's step sensor, mirroring how every other
/// hardware seam in ZIVO (camera, mic, music) is behind a plain interface.
///
/// Hosts without a step sensor (macOS, Windows, web) simply have no service —
/// `AppScope.stepCounter` is null and the dashboard hides its Move ring.
abstract interface class StepCounterService {
  /// Today's steps, re-emitted live as the counter advances. The first value
  /// may take until the sensor produces an event; errors on this stream are
  /// transient (sensor busy, permission revoked mid-session) and safe to
  /// retry by re-subscribing.
  Stream<int> watchStepsToday();
}

/// Whether THIS device can provide step data at all — used to decide whether
/// the dashboard mounts its Move ring. Step sensors exist on iOS (CoreMotion)
/// and most Android phones; desktop/web hosts have none.
bool get deviceHasStepSensor => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

/// [pedometer]-backed [StepCounterService].
///
/// The OS exposes a CUMULATIVE step count since last boot/reboot — not "today"
/// — so this impl maintains a per-day baseline: `today = cumulative − baseline`
/// where the baseline is captured from the day's first event (or carried over
/// across app restarts via shared_preferences). A reboot resets the cumulative
/// value below the baseline; that is detected and absorbed by shifting the
/// baseline so the user's walked-so-far number never goes backwards.
class PedometerStepCounterService implements StepCounterService {
  PedometerStepCounterService({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  static const _baselinePrefix = 'steps.baseline.';

  final SharedPreferencesAsync _prefs;

  StreamController<int>? _controller;
  StreamSubscription<StepCount>? _sub;
  int? _baseline;
  String _dayKey = '';

  @override
  Stream<int> watchStepsToday() {
    final existing = _controller;
    if (existing != null) return existing.stream;
    final controller = StreamController<int>.broadcast();
    controller.onListen = () {
      _sub ??= Pedometer.stepCountStream.listen(
        (event) => _onSample(event.steps),
        // Sensor hiccups (busy, permission revoked mid-session) are not
        // data — swallowing them keeps the last good value on screen
        // rather than flashing a false zero.
        onError: (Object _) {},
        cancelOnError: false,
      );
    };
    controller.onCancel = () async {
      await _sub?.cancel();
      _sub = null;
    };
    _controller = controller;
    return controller.stream;
  }

  /// Maps one raw cumulative sample to today's count.
  Future<void> _onSample(int cumulative) async {
    final c = _controller;
    if (c == null || c.isClosed) return;

    final key = _todayKey();
    // Midnight rolled over while subscribed: start a fresh baseline.
    if (key != _dayKey) {
      _dayKey = key;
      _baseline = null;
    }

    var baseline = _baseline;
    if (baseline == null) {
      baseline = await _loadBaseline(key);
      _baseline = baseline = _rebaseForReboot(cumulative, baseline);
      await _saveBaseline(key, baseline);
      c.add(_clampToday(cumulative - baseline));
      return;
    }

    // Reboot detection: the cumulative counter restarted below where we were
    // counting from. Shift the baseline down by the same amount so today's
    // already-shown steps survive the reboot.
    if (cumulative < baseline) {
      baseline = _rebaseForReboot(cumulative, baseline);
      _baseline = baseline;
      await _saveBaseline(key, baseline);
    }
    c.add(_clampToday(cumulative - baseline));
  }

  /// On a fresh day the baseline is simply the current cumulative value.
  /// After a reboot (cumulative < stored baseline) it shifts so the delta
  /// stays identical to what was last shown.
  int _rebaseForReboot(int cumulative, int? storedBaseline) {
    if (storedBaseline == null) return cumulative;
    if (cumulative < storedBaseline) return cumulative;
    return storedBaseline;
  }

  int _clampToday(int value) => value < 0 ? 0 : value;

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<int?> _loadBaseline(String key) =>
      _prefs.getInt('$_baselinePrefix$key');

  Future<void> _saveBaseline(String key, int baseline) async {
    try {
      await _prefs.setInt('$_baselinePrefix$key', baseline);
    } catch (_) {
      // Persistence is best-effort — losing it only means today's count
      // restarts from the next sensor event after a restart.
    }
  }
}
