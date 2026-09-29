import 'dart:async';

import 'package:flutter/widgets.dart';

/// Foreground / background signal for realtime features.
///
/// supabase_flutter already closes the Realtime socket when the app is
/// paused and reconnects + rejoins channels on resume, so a backgrounded
/// phone does not count against the project's concurrent-connection limit.
/// What it cannot do is replay the changes made while the socket was down.
///
/// Services use this to:
///   * stop their own polling / retry timers in the background — a retry
///     that re-subscribes would reopen the socket and undo the disconnect;
///   * re-fetch on [onResumed], so screens catch up on what they missed.
class AppLifecycleService {
  AppLifecycleService._();
  static final AppLifecycleService instance = AppLifecycleService._();

  AppLifecycleListener? _listener;
  bool _foreground = true;
  bool _wasPaused = false;

  final _paused = StreamController<void>.broadcast();
  final _resumed = StreamController<void>.broadcast();

  bool get isForeground => _foreground;

  /// App moved to the background (socket about to close).
  Stream<void> get onPaused => _paused.stream;

  /// App is back after having been paused — time to re-sync. Not fired for
  /// brief `inactive` blips (notification shade, permission dialogs), where
  /// the socket never closed and nothing was missed.
  Stream<void> get onResumed => _resumed.stream;

  void init() {
    _listener ??= AppLifecycleListener(
      onPause: () {
        _foreground = false;
        _wasPaused = true;
        _paused.add(null);
      },
      onResume: () {
        _foreground = true;
        if (!_wasPaused) return;
        _wasPaused = false;
        _resumed.add(null);
      },
    );
  }
}
