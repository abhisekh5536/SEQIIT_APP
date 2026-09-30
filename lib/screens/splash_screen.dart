import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Brand purple shared with the native launch screen (`flutter_native_splash`
/// in pubspec.yaml). Keep the two in sync or the hand-off will flash.
const kSplashColor = Color(0xFF5E38D6);

/// Same image, drawn at the same logical size (1152 px @4x = 288), as the
/// native splash — so the logo stays put when Flutter takes over.
const _kLogoAsset = 'assets/icon/splash_logo.png';
const double _kLogoBox = 288;

/// Runs [initialize] behind a branded loading screen, then cross-fades into
/// whatever [builder] returns. Failures show a retry instead of hanging on a
/// blank screen.
class AppBootstrap<T> extends StatefulWidget {
  final Future<T> Function() initialize;
  final Widget Function(T result) builder;

  const AppBootstrap({
    super.key,
    required this.initialize,
    required this.builder,
  });

  @override
  State<AppBootstrap<T>> createState() => _AppBootstrapState<T>();
}

class _AppBootstrapState<T> extends State<AppBootstrap<T>> {
  T? _result;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _failed = false);
    try {
      final result = await widget.initialize();
      if (!mounted) return;
      setState(() {
        _result = result;
        _ready = true;
      });
    } catch (e, st) {
      debugPrint('App start-up failed: $e\n$st');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: _ready
          ? KeyedSubtree(
              key: const ValueKey('app'),
              child: widget.builder(_result as T),
            )
          : MaterialApp(
              key: const ValueKey('splash'),
              debugShowCheckedModeBanner: false,
              home: SplashView(onRetry: _failed ? _run : null),
            ),
    );
  }
}

/// Minimal launch screen: centred logo, wordmark and a quiet progress
/// indicator. With [onRetry] set it shows a start-up error instead.
class SplashView extends StatelessWidget {
  final VoidCallback? onRetry;

  const SplashView({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final failed = onRetry != null;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: kSplashColor,
      ),
      child: Scaffold(
        backgroundColor: kSplashColor,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final centerY = constraints.maxHeight / 2;
            return Stack(
              children: [
                // Exactly centred on the full window, like the native splash.
                Center(
                  child: Image.asset(
                    _kLogoAsset,
                    width: _kLogoBox,
                    height: _kLogoBox,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                Positioned(
                  left: 32,
                  right: 32,
                  top: centerY + 96,
                  child: _DelayedFadeIn(
                    // Fast starts never flash the wordmark; slow ones get
                    // feedback that something is happening.
                    delay: failed
                        ? Duration.zero
                        : const Duration(milliseconds: 250),
                    child: Column(
                      children: [
                        const Text(
                          'SAQIIT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 8,
                          ),
                        ),
                        const SizedBox(height: 28),
                        if (failed)
                          _StartupError(onRetry: onRetry!)
                        else
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white70,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  final VoidCallback onRetry;

  const _StartupError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          "Couldn't start the app",
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Check your internet connection and try again.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Try again'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
        ),
      ],
    );
  }
}

class _DelayedFadeIn extends StatefulWidget {
  final Duration delay;
  final Widget child;

  const _DelayedFadeIn({required this.delay, required this.child});

  @override
  State<_DelayedFadeIn> createState() => _DelayedFadeInState();
}

class _DelayedFadeInState extends State<_DelayedFadeIn> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      child: widget.child,
    );
  }
}
