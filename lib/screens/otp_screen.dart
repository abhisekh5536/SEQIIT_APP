import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../widgets/auth_illustration.dart';

class OtpScreen extends StatefulWidget {
  final String email;
  const OtpScreen({super.key, required this.email});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const _codeLength = 6;
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  Timer? _cooldownTimer;
  bool _loading = false;
  bool _resending = false;
  int _resendIn = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_codeLength, (_) => TextEditingController());
    _focusNodes = List.generate(
      _codeLength,
      (i) => FocusNode(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace && _controllers[i].text.isEmpty && i > 0) {
            _controllers[i - 1].clear();
            _focusNodes[i - 1].requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
      ),
    );
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _resendIn = 30);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendIn = (_resendIn - 1).clamp(0, 30));
      if (_resendIn == 0) timer.cancel();
    });
  }

  String get _code => _controllers.map((c) => c.text).join();

  void _onChanged(String value, int index) {
    final digits = value.replaceAll(RegExp(r'\D'), '').characters.toList();
    if (digits.isEmpty) {
      setState(() {});
      return;
    }
    if (digits.length > 1 || _controllers[index].text.isNotEmpty) {
      for (var j = 0; j < digits.length && index + j < _codeLength; j++) {
        _controllers[index + j].text = digits[j];
      }
      final next = (index + digits.length).clamp(0, _codeLength - 1);
      _focusNodes[next].requestFocus();
      setState(() {});
      if (_code.length == _codeLength) _verify();
      return;
    }
    _controllers[index].text = digits.first;
    if (index < _codeLength - 1) {
      _focusNodes[index + 1].requestFocus();
    } else {
      _focusNodes[index].unfocus();
      if (_code.length == _codeLength) _verify();
    }
    setState(() {});
  }

  Future<void> _verify() async {
    if (_code.length != _codeLength || _loading) return;
    HapticFeedback.lightImpact();
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      await Supabase.instance.client.auth.verifyOTP(email: widget.email, token: _code, type: OtpType.signup);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthApiException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      HapticFeedback.heavyImpact();
      setState(() {
        _loading = false;
        if (msg.contains('expired')) {
          _errorMessage = 'This code has expired. Please request a new one.';
        } else if (msg.contains('invalid')) {
          _errorMessage = 'Incorrect code. Please check and try again.';
        } else {
          _errorMessage = e.message;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Something went wrong. Check your connection and try again.';
      });
    }
  }

  Future<void> _resend() async {
    if (_resendIn > 0 || _resending) return;
    HapticFeedback.selectionClick();
    setState(() => _resending = true);
    try {
      await Supabase.instance.client.auth.resend(email: widget.email, type: OtpType.signup);
      if (!mounted) return;
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('New code sent to ${widget.email}'), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not resend. Try again.'), behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: p.canvas,
      body: LayoutBuilder(builder: (context, c) {
        final isWide = c.maxWidth >= 860;
        if (isWide) return _buildWide(context, p, t);
        return _buildNarrow(context, p, t);
      }),
    );
  }

  Widget _buildNarrow(BuildContext context, AppPaletteData p, TextTheme t) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: inset),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: _loading ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: p.card,
                    side: BorderSide(color: p.hairline),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: AuthIllustration(
              aspectRatio: 2.7,
              borderRadius: BorderRadius.all(Radius.circular(22)),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _Card(p: p, t: t, controllers: _controllers, focusNodes: _focusNodes, loading: _loading, resending: _resending, resendIn: _resendIn, errorMessage: _errorMessage, onChanged: _onChanged, onVerify: _verify, onResend: _resend, code: _code),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Text('Paste the full code — it auto-fills.', textAlign: TextAlign.center, style: t.labelSmall?.copyWith(color: p.textTertiary, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildWide(BuildContext context, AppPaletteData p, TextTheme t) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Row(
      children: [
        Expanded(
          flex: 11,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const AuthIllustration(stretch: true, borderRadius: BorderRadius.zero),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.5, 1.0],
                    colors: [
                      Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.35 : 0.18),
                      Colors.transparent,
                      Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.55 : 0.42),
                    ],
                  ),
                ),
              ),
              SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(36, 24, 36, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: _loading ? null : () => Navigator.pop(context),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white.withValues(alpha: 0.16))),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.arrow_back_rounded, size: 14, color: Colors.white), SizedBox(width: 6), Text('Back', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))]),
                          ),
                        ),
                        const Spacer(),
                        Text('ALMOST THERE', style: t.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                        const SizedBox(height: 10),
                        Text('Check your\ninbox.', style: t.headlineLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, height: 0.95, letterSpacing: -1.0, fontSize: 40)),
                        const SizedBox(height: 10),
                        Text('Code sent to\n${widget.email}', style: t.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.84), height: 1.5)),
                        const Spacer(),
                        Text('SAQIIT • Society OS', style: t.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.55), letterSpacing: 0.5)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          flex: 13,
          child: Container(
            color: p.canvas,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(32, 24, 32, 24 + inset),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: _Card(p: p, t: t, controllers: _controllers, focusNodes: _focusNodes, loading: _loading, resending: _resending, resendIn: _resendIn, errorMessage: _errorMessage, onChanged: _onChanged, onVerify: _verify, onResend: _resend, code: _code, isWide: true),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final AppPaletteData p;
  final TextTheme t;
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final bool loading;
  final bool resending;
  final int resendIn;
  final String? errorMessage;
  final void Function(String, int) onChanged;
  final Future<void> Function() onVerify;
  final Future<void> Function() onResend;
  final String code;
  final bool isWide;
  const _Card({required this.p, required this.t, required this.controllers, required this.focusNodes, required this.loading, required this.resending, required this.resendIn, required this.errorMessage, required this.onChanged, required this.onVerify, required this.onResend, required this.code, this.isWide = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: p.hairline), boxShadow: [BoxShadow(color: p.shadow.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 6))]),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Enter code', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Type or paste the 6 digits', style: t.bodySmall?.copyWith(color: p.textSecondary)),
          const SizedBox(height: 14),
          Row(
            children: List.generate(6, (i) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 4, right: i == 5 ? 0 : 4),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([controllers[i], focusNodes[i]]),
                    builder: (context, _) {
                      final focused = focusNodes[i].hasFocus;
                      final filled = controllers[i].text.isNotEmpty;
                      return TextField(
                        controller: controllers[i],
                        focusNode: focusNodes[i],
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        textAlign: TextAlign.center,
                        style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: p.card,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: filled && !focused ? p.primary.withValues(alpha: 0.45) : p.hairline)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.primary, width: 1.6)),
                        ),
                        onChanged: (v) => onChanged(v, i),
                      );
                    },
                  ),
                ),
              );
            }),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: p.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: p.danger.withValues(alpha: 0.18))),
              child: Row(children: [Icon(Icons.error_outline_rounded, size: 16, color: p.danger), const SizedBox(width: 8), Expanded(child: Text(errorMessage!, style: t.bodySmall?.copyWith(color: p.danger, fontWeight: FontWeight.w600)))]),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: code.length == 6 && !loading ? onVerify : null,
              style: FilledButton.styleFrom(backgroundColor: p.primary, foregroundColor: p.onPrimary, disabledBackgroundColor: p.primary.withValues(alpha: 0.4), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: loading ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: p.onPrimary)) : const Text('Verify', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("Didn't get it?", style: t.bodySmall?.copyWith(color: p.textSecondary)),
              TextButton(
                onPressed: resendIn > 0 || resending ? null : onResend,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: resending
                    ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: p.primary))
                    : Text(resendIn > 0 ? 'Resend in ${resendIn}s' : 'Resend code', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: resendIn > 0 ? p.textTertiary : p.primary)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
