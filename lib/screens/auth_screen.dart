import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../widgets/auth_illustration.dart';
import 'otp_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLogin = true;
  bool _loading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // ── actions ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final client = Supabase.instance.client;

    try {
      if (_isLogin) {
        await client.auth.signInWithPassword(email: email, password: password);
      } else {
        final response =
            await client.auth.signUp(email: email, password: password);
        if (response.session == null) {
          if (!mounted) return;
          setState(() => _loading = false);
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => OtpScreen(email: email)),
          );
          return;
        }
      }
    } on AuthApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        final msg = e.message.toLowerCase();
        if (msg.contains('not confirmed') || msg.contains("isn't confirmed")) {
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => OtpScreen(email: email)),
          );
          return;
        }
        setState(() => _errorMessage = _friendlyError(e.message));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage =
              'Something went wrong. Check your connection and try again.';
        });
      }
    } finally {
      if (mounted && _loading) {
        Future.delayed(const Duration(milliseconds: 1400), () {
          if (mounted && _loading) setState(() => _loading = false);
        });
      }
    }
  }

  String _friendlyError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('invalid login credentials')) {
      return 'Wrong email or password. Please try again.';
    }
    if (lower.contains('already registered') ||
        lower.contains('already been registered')) {
      return 'This email already has an account. Try signing in instead.';
    }
    if (lower.contains('password should be at least')) {
      return 'Password must be at least 6 characters.';
    }
    if (lower.contains('rate limit')) {
      return 'Too many attempts. Try again in a moment.';
    }
    if (lower.contains('valid email')) {
      return 'Please enter a valid email address.';
    }
    return message;
  }

  void _toggleMode(bool toLogin) {
    if (_isLogin == toLogin) return;
    HapticFeedback.selectionClick();
    setState(() {
      _isLogin = toLogin;
      _errorMessage = null;
      _confirmController.clear();
      _passwordController.clear();
    });
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(
          () => _errorMessage = 'Enter your email first, then tap Forgot password.');
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reset link sent to $email'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not send reset link. Try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _googleSignIn() async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithOAuth(OAuthProvider.google);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not sign in with Google. Try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── layout ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: p.canvas,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) return _wide(context, p);
          return _narrow(context, p);
        },
      ),
    );
  }

  Widget _narrow(BuildContext context, AppPaletteData p) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Opacity(
            opacity: Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.6,
            child: const AuthIllustration(
              stretch: false,
              borderRadius: BorderRadius.zero,
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(32.0, 24.0, 32.0, 24.0 + bottomInset),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _brandHeader(p),
                    const SizedBox(height: 48),
                    _headline(p),
                    const SizedBox(height: 36),
                    _form(context, p),
                    const SizedBox(height: 24),
                    _toggleModeButton(p),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _wide(BuildContext context, AppPaletteData p) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Row(
      children: [
        Expanded(
          flex: 1,
          child: Container(
            color: p.cardMuted,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Opacity(
                    opacity: Theme.of(context).brightness == Brightness.dark ? 0.4 : 0.8,
                    child: const AuthIllustration(
                      stretch: false,
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.apartment_rounded,
                          size: 48, color: p.primary.withValues(alpha: 0.5)),
                      const SizedBox(height: 24),
                      Text(
                        'SAQIIT',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 12,
                          color: p.textPrimary.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(48.0, 48.0, 48.0, 48.0 + bottomInset),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _brandHeader(p),
                    const SizedBox(height: 48),
                    _headline(p),
                    const SizedBox(height: 36),
                    _form(context, p),
                    const SizedBox(height: 24),
                    _toggleModeButton(p),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _brandHeader(AppPaletteData p) {
    return Row(
      children: [
        Icon(Icons.apartment_rounded, size: 24, color: p.primary),
        const SizedBox(width: 12),
        Text(
          'SAQIIT',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: p.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _headline(AppPaletteData p) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Column(
        key: ValueKey(_isLogin),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isLogin ? 'Welcome back' : 'Create an account',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w300,
              letterSpacing: -1,
              color: p.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isLogin
                ? 'Sign in to continue to your dashboard.'
                : 'Enter your details to get started.',
            style: TextStyle(
              fontSize: 14,
              color: p.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _minimalInputDeco(AppPaletteData p, String hint, {Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: p.textTertiary, fontWeight: FontWeight.w400),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16),
      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.hairline)),
      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.primary, width: 1.5)),
      errorBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.danger)),
      focusedErrorBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.danger, width: 1.5)),
    );
  }

  Widget _form(BuildContext context, AppPaletteData p) {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.disabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            textInputAction: TextInputAction.next,
            style: TextStyle(color: p.textPrimary, fontSize: 16),
            decoration: _minimalInputDeco(p, 'Email address'),
            validator: (v) {
              final s = v?.trim() ?? '';
              if (s.isEmpty) return 'Please enter your email';
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
                return 'Please enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: TextFormField(
              key: ValueKey('pwd-$_isLogin'),
              controller: _passwordController,
              obscureText: _obscurePassword,
              autofillHints: _isLogin
                  ? const [AutofillHints.password]
                  : const [AutofillHints.newPassword],
              textInputAction:
                  _isLogin ? TextInputAction.done : TextInputAction.next,
              onFieldSubmitted: _isLogin ? (_) => _submit() : null,
              style: TextStyle(color: p.textPrimary, fontSize: 16),
              decoration: _minimalInputDeco(
                p,
                'Password',
                suffix: IconButton(
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: p.textTertiary,
                  ),
                ),
              ),
              validator: (v) {
                if ((v ?? '').isEmpty) return 'Please enter your password';
                if ((v ?? '').length < 6) return 'Password must be at least 6 characters';
                return null;
              },
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: !_isLogin
                ? Padding(
                    key: const ValueKey('confirm'),
                    padding: const EdgeInsets.only(top: 24),
                    child: TextFormField(
                      controller: _confirmController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      style: TextStyle(color: p.textPrimary, fontSize: 16),
                      decoration: _minimalInputDeco(p, 'Confirm password'),
                      validator: (v) =>
                          (v ?? '') != _passwordController.text
                              ? 'Passwords do not match'
                              : null,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _isLogin
                ? Align(
                    key: const ValueKey('forgot'),
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextButton(
                        onPressed: _loading ? null : _forgotPassword,
                        style: TextButton.styleFrom(
                          foregroundColor: p.textSecondary,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Forgot password?',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _errorMessage != null
                ? Container(
                    key: ValueKey(_errorMessage),
                    margin: const EdgeInsets.only(top: 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: p.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, size: 20, color: p.danger),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: p.danger, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 36),
          _ctaButton(p),
          _orDivider(p),
          _googleSignInButton(p),
        ],
      ),
    );
  }

  Widget _orDivider(AppPaletteData p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        children: [
          Expanded(child: Divider(color: p.hairline)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'OR',
              style: TextStyle(
                color: p.textTertiary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Expanded(child: Divider(color: p.hairline)),
        ],
      ),
    );
  }

  Widget _googleSignInButton(AppPaletteData p) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        boxShadow: [
          BoxShadow(
            color: p.shadow.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: CustomPaint(
            painter: _LiquidGlassPainter(isDark: isDark),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: isDark ? 0.14 : 0.55),
                    Colors.white.withValues(alpha: isDark ? 0.03 : 0.20),
                  ],
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _loading ? null : _googleSignIn,
                  borderRadius: BorderRadius.circular(100),
                  splashColor: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.06),
                  highlightColor: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.03),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CustomPaint(painter: _GoogleLogoPainter()),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Continue with Google',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          color: p.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ctaButton(AppPaletteData p) {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: _loading ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: _loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(
                _isLogin ? 'Sign In' : 'Create Account',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5),
              ),
      ),
    );
  }

  Widget _toggleModeButton(AppPaletteData p) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: p.shadow.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: p.hairline),
        ),
        child: TextButton(
          onPressed: () => _toggleMode(!_isLogin),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w500, color: p.textPrimary),
              children: [
                TextSpan(
                    text: _isLogin
                        ? "Don't have an account? "
                        : "Already have an account? "),
                TextSpan(
                  text: _isLogin ? "Sign up" : "Sign in",
                  style: TextStyle(color: p.primary, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Advanced CustomPainter for genuine Apple/VisionOS-style Liquid Glass effects.
/// Replicates specular highlights, convex lens sheen, edge refraction, and inner lighting.
class _LiquidGlassPainter extends CustomPainter {
  final bool isDark;

  _LiquidGlassPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2));

    // 1. Top Specular Lens Highlight (Curved light reflection on the upper dome)
    final sheenRect = Rect.fromLTWH(1, 1, size.width - 2, size.height * 0.52);
    final sheenRRect = RRect.fromRectAndCorners(
      sheenRect,
      topLeft: Radius.circular(size.height / 2),
      topRight: Radius.circular(size.height / 2),
      bottomLeft: const Radius.circular(10),
      bottomRight: const Radius.circular(10),
    );

    final sheenPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: isDark ? 0.32 : 0.68),
          Colors.white.withValues(alpha: isDark ? 0.08 : 0.22),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(sheenRect);

    canvas.drawRRect(sheenRRect, sheenPaint);

    // 2. Liquid Glass Prismatic Rim (Specular Border Highlight)
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: isDark ? 0.70 : 0.95), // Crisp top-left light catch
          Colors.white.withValues(alpha: isDark ? 0.15 : 0.35),
          Colors.white.withValues(alpha: isDark ? 0.05 : 0.15),
          Colors.white.withValues(alpha: isDark ? 0.40 : 0.70), // Bottom-right refraction bounce
        ],
        stops: const [0.0, 0.35, 0.65, 1.0],
      ).createShader(rect);

    canvas.drawRRect(rrect, borderPaint);

    // 3. Inner Glass Depth Stroke (simulating refraction index)
    final innerRRect = rrect.deflate(1.2);
    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: isDark ? 0.25 : 0.50),
          Colors.transparent,
        ],
      ).createShader(rect);

    canvas.drawRRect(innerRRect, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// Official 4-color Google G icon painter with pixel-perfect official vector geometry
class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 48.0;
    canvas.save();
    canvas.scale(scale, scale);

    final fillPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;

    // 1. Blue segment (#4285F4)
    fillPaint.color = const Color(0xFF4285F4);
    final bluePath = Path()
      ..moveTo(46.98, 24.55)
      ..cubicTo(46.98, 22.98, 46.83, 21.46, 46.60, 20.00)
      ..lineTo(24.0, 20.00)
      ..lineTo(24.0, 29.02)
      ..lineTo(36.94, 29.02)
      ..cubicTo(36.36, 31.98, 34.68, 34.50, 32.16, 36.20)
      ..lineTo(39.89, 42.20)
      ..cubicTo(44.40, 38.02, 46.98, 31.84, 46.98, 24.55)
      ..close();
    canvas.drawPath(bluePath, fillPaint);

    // 2. Green segment (#34A853)
    fillPaint.color = const Color(0xFF34A853);
    final greenPath = Path()
      ..moveTo(24.0, 48.0)
      ..cubicTo(30.48, 48.0, 35.93, 45.87, 39.89, 42.19)
      ..lineTo(32.16, 36.19)
      ..cubicTo(30.01, 37.64, 27.24, 38.49, 24.0, 38.49)
      ..cubicTo(17.74, 38.49, 12.43, 34.27, 10.53, 28.59)
      ..lineTo(2.56, 34.78)
      ..cubicTo(6.51, 42.62, 14.62, 48.0, 24.0, 48.0)
      ..close();
    canvas.drawPath(greenPath, fillPaint);

    // 3. Yellow segment (#FBBC05)
    fillPaint.color = const Color(0xFFFBBC05);
    final yellowPath = Path()
      ..moveTo(10.53, 28.59)
      ..cubicTo(10.05, 27.14, 9.77, 25.60, 9.77, 24.00)
      ..cubicTo(9.77, 22.40, 10.04, 20.86, 10.53, 19.41)
      ..lineTo(2.56, 13.22)
      ..cubicTo(0.92, 16.46, 0.0, 20.12, 0.0, 24.00)
      ..cubicTo(0.0, 27.88, 0.92, 31.54, 2.56, 34.78)
      ..lineTo(10.53, 28.59)
      ..close();
    canvas.drawPath(yellowPath, fillPaint);

    // 4. Red segment (#EA4335)
    fillPaint.color = const Color(0xFFEA4335);
    final redPath = Path()
      ..moveTo(24.0, 9.50)
      ..cubicTo(27.54, 9.50, 30.71, 10.72, 33.21, 13.10)
      ..lineTo(40.06, 6.25)
      ..cubicTo(35.90, 2.38, 30.47, 0.0, 24.0, 0.0)
      ..cubicTo(14.62, 0.0, 6.51, 5.38, 2.56, 13.22)
      ..lineTo(10.54, 19.41)
      ..cubicTo(12.43, 13.72, 17.74, 9.50, 24.0, 9.50)
      ..close();
    canvas.drawPath(redPath, fillPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
