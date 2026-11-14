/// Runs one async task at a time; callers that arrive while it runs get the same result.
/// Used for the token refresh: ten requests failing with 401 at once cause one refresh (Section 10.2).
class SingleFlight<T> {
  Future<T>? _running;

  bool get isRunning => _running != null;

  Future<T> run(Future<T> Function() task) {
    final current = _running;
    if (current != null) return current;
    final future = task().whenComplete(() => _running = null);
    _running = future;
    return future;
  }
}
