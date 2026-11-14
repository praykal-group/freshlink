import 'dart:math' as math;

/// Exponential backoff with full jitter. Attempt 1 waits up to `base`, attempt n up to
/// `base × factor^(n-1)`, never more than `max` (Section 10.2: sync retries cap at 30 min).
class Backoff {
  const Backoff({this.base = const Duration(seconds: 5), this.factor = 2, this.max = const Duration(minutes: 30), this.jitter = true});

  final Duration base;
  final double factor;
  final Duration max;
  final bool jitter;

  /// The delay before retry number [attempt] (1-based). [random] in [0, 1) for jitter (tests pass a fixed value).
  Duration delay(int attempt, {double? random}) {
    if (attempt < 1) return Duration.zero;
    final raw = base.inMilliseconds * math.pow(factor, attempt - 1);
    final capped = math.min(raw, max.inMilliseconds.toDouble());
    if (!jitter) return Duration(milliseconds: capped.round());
    // "Equal jitter": at least half the delay, so retries never bunch at zero.
    final r = random ?? math.Random().nextDouble();
    return Duration(milliseconds: (capped / 2 + r * capped / 2).round());
  }
}

/// GET retries in the API client: 3 tries in total, short waits (Section 10.2).
const apiGetBackoff = Backoff(base: Duration(milliseconds: 400), max: Duration(seconds: 4));
const apiGetMaxTries = 3;

/// Outbox ops and file uploads: 5 s doubling up to 30 min.
const syncBackoff = Backoff();
