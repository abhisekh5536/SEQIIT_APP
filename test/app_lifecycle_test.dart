import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/services/app_lifecycle_service.dart';

void main() {
  testWidgets('pause/resume drive the realtime re-sync signal',
      (tester) async {
    final service = AppLifecycleService.instance..init();
    var paused = 0;
    var resumed = 0;
    final pausedSub = service.onPaused.listen((_) => paused++);
    final resumedSub = service.onResumed.listen((_) => resumed++);
    addTearDown(() {
      pausedSub.cancel();
      resumedSub.cancel();
    });

    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    // Pulling down the notification shade: inactive and back. The socket
    // never closed, so no re-sync.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(resumed, 0);
    expect(service.isForeground, isTrue);

    // Home button: into the background.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(paused, 1);
    expect(service.isForeground, isFalse);

    // Back to the app: exactly one re-sync.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(resumed, 1);
    expect(service.isForeground, isTrue);

    // A later shade pull does not re-fire it.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(resumed, 1);
  });
}
