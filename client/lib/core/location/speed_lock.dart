import 'gps_fix.dart';

/// DA-NFR-08: typing and non-essential actions are blocked while the truck moves faster than
/// 10 km/h. Only Acknowledge, Accept reroute, SOS and Navigate stay active.
///
/// Locks on the first fix above [lockAboveKmh]. Unlocks only after the truck has been at or below
/// it for [unlockAfter] (a stop at a junction must not flicker the overlay); a fix that is too
/// inaccurate does not count as stopped. No fix at all keeps the state: losing GPS in motion must
/// not unlock the keyboard.
class SpeedLock {
  SpeedLock({this.lockAboveKmh = 10, this.unlockAfter = const Duration(seconds: 8), this.maxAccuracyM = 50});

  final double lockAboveKmh;
  final Duration unlockAfter;
  final double maxAccuracyM;

  bool _locked = false;
  DateTime? _slowSince;

  bool get locked => _locked;

  /// Feeds one fix; returns the new state.
  bool update(GpsFix fix) {
    final speed = fix.speedKmh;
    if (speed == null) return _locked; // no speed: no change
    if (speed > lockAboveKmh) {
      _locked = true;
      _slowSince = null;
      return _locked;
    }
    if (!_locked) return false;
    if (fix.accuracyM != null && fix.accuracyM! > maxAccuracyM) return _locked;
    _slowSince ??= fix.at;
    if (fix.at.difference(_slowSince!) >= unlockAfter) {
      _locked = false;
      _slowSince = null;
    }
    return _locked;
  }

  /// The trip ended (or the driver stopped tracking): never stay locked without a trip.
  void reset() {
    _locked = false;
    _slowSince = null;
  }
}
