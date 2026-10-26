import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/app_scope.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/auth/validators.dart';
import '../../../shared/widgets/paird_widgets.dart';
import 'forgot_password_screen.dart';
import 'sign_up_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _errorMessage;
  String? _pendingError;

  @override
  void initState() {
    super.initState();
    // e.g. "Your session has expired. Please sign in again."
    _errorMessage = AppScope.read(context).auth.takeNotice();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121816), // Dark Teal / Charcoal
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                // 1. Paird Logo / Name
                Center(
                  child: Text(
                    'Paird',
                    style: GoogleFonts.instrumentSerif(
                      fontSize: 36,
                      color: const Color(0xFFE2C078), // Elegant Gold
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // 2. Welcome Heading
                Text(
                  'Welcome back',
                  style: GoogleFonts.instrumentSerif(
                    fontSize: 32,
                    color: const Color(0xFFF5F5F0),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),

                // 3. Subtitle
                Text(
                  'Your next meaningful connection starts here.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: const Color(0xFF9CA3AF),
                  ),
                ),
                const SizedBox(height: 32),

                // Error message banner if any
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade800.withValues(alpha: 0.2),
                      border: Border.all(color: Colors.red.shade800),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.red.shade200,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 4. Email or Phone Input Field
                Text(
                  'Email or Phone Number',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: const Color(0xFFD1D5DB),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  style: GoogleFonts.plusJakartaSans(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'name@example.com',
                    hintStyle: GoogleFonts.plusJakartaSans(color: Colors.grey.shade600),
                    filled: true,
                    fillColor: const Color(0xFF1A2321),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2A3835)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2A3835)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFC9A24A), width: 1.5),
                    ),
                  ),
                  validator: validateIdentifier,
                ),
                const SizedBox(height: 20),

                // 5. Password Input Field
                Text(
                  'Password',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: const Color(0xFFD1D5DB),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: GoogleFonts.plusJakartaSans(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Enter your password',
                    hintStyle: GoogleFonts.plusJakartaSans(color: Colors.grey.shade600),
                    filled: true,
                    fillColor: const Color(0xFF1A2321),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2A3835)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2A3835)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFC9A24A), width: 1.5),
                    ),
                    suffixIcon: IconButton(
                      tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: Colors.grey.shade400,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // 6. “Forgot password?” link
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ForgotPasswordScreen(initialIdentifier: _emailController.text.trim()),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: Text(
                      'Forgot password?',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: const Color(0xFFE2C078),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 7. Interactive Slide-to-Sign-In Widget
                SlideToSignInWidget(
                  onAuthAction: () async {
                    _pendingError = null;
                    if (!(_formKey.currentState?.validate() ?? false)) {
                      _pendingError = 'Please fix the highlighted fields.';
                      return false;
                    }
                    try {
                      await AppScope.read(context).auth.signIn(
                            _emailController.text,
                            _passwordController.text,
                          );
                      return true;
                    } on ApiException catch (e) {
                      _pendingError = e.message;
                      return false;
                    }
                  },
                  onSuccess: () {
                    // AuthGate switches to onboarding or home once signed in.
                    if (mounted) setState(() { _errorMessage = null; });
                  },
                  onError: (message) {
                    if (!mounted) return;
                    setState(() {
                      _errorMessage = _pendingError ?? message;
                    });
                  },
                ),
                const SizedBox(height: 24),

                // 8. Subtle “OR” Divider
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade800)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'OR',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey.shade800)),
                  ],
                ),
                const SizedBox(height: 24),

                // 9. Google Sign-In Button
                OutlinedButton.icon(
                  onPressed: () {
                    showSnack(context, "Google sign-in isn't available yet. Please use email or phone.");
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    backgroundColor: const Color(0xFF1A2321),
                    side: const BorderSide(color: Color(0xFF2A3835)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.g_mobiledata, color: Colors.white, size: 28),
                  label: Text(
                    'Continue with Google',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // 10. Bottom text: “New to Paird? Create account”
                Center(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const SignUpScreen()),
                      );
                    },
                    child: RichText(
                      text: TextSpan(
                        text: "New to Paird? ",
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          color: Colors.grey.shade400,
                        ),
                        children: [
                          TextSpan(
                            text: "Create account",
                            style: GoogleFonts.plusJakartaSans(
                              color: const Color(0xFFE2C078),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Modern Slide-to-Sign-In Control Widget
class SlideToSignInWidget extends StatefulWidget {
  final Future<bool> Function()? onAuthAction;
  final VoidCallback? onSuccess;
  final ValueChanged<String>? onError;

  const SlideToSignInWidget({
    super.key,
    this.onAuthAction,
    this.onSuccess,
    this.onError,
  });

  @override
  State<SlideToSignInWidget> createState() => _SlideToSignInWidgetState();
}

class _SlideToSignInWidgetState extends State<SlideToSignInWidget>
    with SingleTickerProviderStateMixin {
  double _dragPosition = 0.0;
  bool _isLoading = false;
  bool _isSuccess = false;

  late AnimationController _controller;
  late Animation<double> _animation;

  final double _height = 56.0;
  final double _thumbSize = 48.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    )..addListener(() {
      setState(() {
        _dragPosition = _animation.value;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _runSnapBack(double maxDrag) {
    _animation = Tween<double>(begin: _dragPosition, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward(from: 0.0);
  }

  void _completeSlide(double maxDrag) async {
    setState(() {
      _dragPosition = maxDrag;
      _isLoading = true;
    });

    try {
      final success = widget.onAuthAction != null ? await widget.onAuthAction!() : true;
      // The screen may be replaced as soon as the session starts.
      if (!mounted) return;
      if (success) {
        setState(() {
          _isLoading = false;
          _isSuccess = true;
        });
        if (widget.onSuccess != null) widget.onSuccess!();
      } else {
        setState(() {
          _isLoading = false;
        });
        if (widget.onError != null) widget.onError!('Sign in failed. Please try again.');
        _runSnapBack(maxDrag);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      if (widget.onError != null) widget.onError!('An error occurred. Please try again.');
      _runSnapBack(maxDrag);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxDrag = maxWidth - _thumbSize - 8.0; // 8px padding offset

        return Container(
          height: _height,
          decoration: BoxDecoration(
            color: const Color(0xFF1A2321),
            borderRadius: BorderRadius.circular(_height / 2),
            border: Border.all(color: const Color(0xFF2A3835)),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Sliding and Fading Text Track
              Center(
                child: Padding(
                  padding: EdgeInsets.only(left: _thumbSize),
                  child: Opacity(
                    opacity: (1.0 - (_dragPosition / (maxDrag == 0 ? 1 : maxDrag)))
                        .clamp(0.0, 1.0),
                    child: Text(
                      _isSuccess ? 'Signed In' : 'Slide to Sign In',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: _isSuccess ? Colors.teal.shade300 : Colors.grey.shade400,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),

              // Draggable Gold Thumb with Arrow / Checkmark / Loader
              Positioned(
                left: 4.0 + _dragPosition,
                // Screen readers cannot drag: expose the slide as a button.
                child: Semantics(
                  button: true,
                  label: _isSuccess ? 'Signed in' : 'Sign in',
                  hint: 'Double tap to sign in',
                  onTap: (_isLoading || _isSuccess) ? null : () => _completeSlide(maxDrag),
                  excludeSemantics: true,
                  child: GestureDetector(
                  onHorizontalDragStart: (_isLoading || _isSuccess)
                      ? null
                      : (_) {
                    _controller.stop();
                  },
                  onHorizontalDragUpdate: (_isLoading || _isSuccess)
                      ? null
                      : (details) {
                    setState(() {
                      _dragPosition += details.delta.dx;
                      if (_dragPosition < 0.0) {
                        _dragPosition = 0.0;
                      } else if (_dragPosition > maxDrag) {
                        _dragPosition = maxDrag;
                      }
                    });
                  },
                  onHorizontalDragEnd: (_isLoading || _isSuccess)
                      ? null
                      : (_) {
                    if (_dragPosition >= maxDrag * 0.9) {
                      _completeSlide(maxDrag);
                    } else {
                      _runSnapBack(maxDrag);
                    }
                  },
                  child: Container(
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: _isSuccess
                            ? [Colors.teal.shade400, Colors.teal.shade700]
                            : [const Color(0xFFE2C078), const Color(0xFFC9A24A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isLoading
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                          : Icon(
                        _isSuccess
                            ? Icons.check_circle_rounded
                            : Icons.arrow_forward_rounded,
                        color: _isSuccess
                            ? Colors.white
                            : const Color(0xFF121816),
                        size: 20,
                      ),
                    ),
                  ),
                ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}