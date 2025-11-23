import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../providers/auth_provider.dart';
import '../../core/widgets/app_notifications.dart';
import '../../core/widgets/lottie_loading.dart';
import '../home/home_screen.dart';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  Future<void> _handleLogin() async {
    // Validate form
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Start loading
    setState(() => _isLoading = true);

    try {
      final authService = ref.read(authServiceProvider);

      // Sign in with Firebase
      final credential = await authService.signInWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;

      // Check email verification
      if (credential.user != null && !credential.user!.emailVerified) {
        setState(() => _isLoading = false);
        _showEmailVerificationDialog();
        return;
      }

      // Navigate to home
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _handleFirebaseError(e);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showMessage('An unexpected error occurred. Please try again.',
          isError: true);
    }
  }

  void _handleFirebaseError(FirebaseAuthException e) {
    String message;

    switch (e.code) {
      case 'user-not-found':
        message = 'No account found with this email address.';
        break;
      case 'wrong-password':
        message = 'Incorrect password. Please try again.';
        break;
      case 'invalid-email':
        message = 'The email address is invalid.';
        break;
      case 'user-disabled':
        message = 'This account has been disabled.';
        break;
      case 'too-many-requests':
        message = 'Too many attempts. Please try again later.';
        break;
      case 'network-request-failed':
        message = 'Network error. Please check your connection.';
        break;
      case 'invalid-credential':
        message = 'Invalid email or password.';
        break;
      default:
        message = 'Login failed. Please check your credentials.';
    }

    _showMessage(message, isError: true);
  }

  void _showMessage(String message, {bool isError = false}) {
    AppNotifications.showSnackBar(
      context,
      message: message,
      type: isError ? AppNotificationType.error : AppNotificationType.success,
    );
  }

  Future<void> _showEmailVerificationDialog() async {
    await AppNotifications.showDialog(
      context,
      title: 'Email Not Verified',
      message:
          'Please verify your email address before logging in. Check your inbox for the verification link we sent you.',
      type: AppNotificationType.warning,
      primaryLabel: 'Resend Email',
      onPrimaryPressed: () async {
        try {
          await FirebaseAuth.instance.currentUser?.sendEmailVerification();
          if (mounted) {
            _showMessage('Verification email sent!');
          }
        } catch (_) {
          if (mounted) {
            _showMessage(
              'Failed to send email. Please try again later.',
              isError: true,
            );
          }
        }
      },
      secondaryLabel: 'OK',
      onSecondaryPressed: () async {},
    );
  }

  Future<void> _handleGoogleLogin() async {
    setState(() => _isGoogleLoading = true);
    try {
      final authService = ref.read(authServiceProvider);
      await authService.signInWithGoogle();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showMessage(e.message ?? 'Google sign-in failed.', isError: true);
    } catch (_) {
      if (!mounted) return;
      _showMessage('Google sign-in failed. Please try again.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
      }
    }
  }

  void _navigateToSignup() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const SignupScreen()),
    );
  }

  void _navigateToForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ForgotPasswordScreen()),
    );
  }

  static const LinearGradient _backgroundGradient = LinearGradient(
    colors: [
      Color(0xFF050A1A),
      Color(0xFF060A16),
      Color(0xFF02040A),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient _fieldBorderGradient = LinearGradient(
    colors: [
      Color(0xFF4B7CFF),
      Color(0xFF8B5BFF),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient _buttonGradient = LinearGradient(
    colors: [
      Color(0xFF3D5CFF),
      Color(0xFF9A3DFF),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  Color get _cardColor => const Color(0x660C1224);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(gradient: _backgroundGradient),
        child: Stack(
          children: [
            _buildNeonCircle(
              top: -120,
              right: -40,
              size: 220,
              color: const Color(0x553D5CFF),
            ),
            _buildNeonCircle(
              bottom: -100,
              left: -60,
              size: 260,
              color: const Color(0x559A3DFF),
            ),
            SafeArea(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopRow(),
                      const SizedBox(height: 32),
                      _buildHeader(),
                      const SizedBox(height: 36),
                      _buildTextField(
                        controller: _emailController,
                        label: 'Email',
                        hint: 'john.doe@email.com',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        validator: _validateEmail,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 20),
                      _buildTextField(
                        controller: _passwordController,
                        label: 'Password',
                        hint: 'Enter your password',
                        icon: Icons.lock_outline_rounded,
                        obscureText: _obscurePassword,
                        validator: _validatePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _handleLogin(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: Colors.white70,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildRememberMeAndForgotPassword(),
                      const SizedBox(height: 28),
                      _buildLoginButton(),
                      const SizedBox(height: 26),
                      _buildDivider(),
                      const SizedBox(height: 26),
                      _buildSocialRow(),
                      const SizedBox(height: 32),
                      _buildSignupLink(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white70,
          ),
        ),
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.more_horiz_rounded, color: Colors.white38),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: _buttonGradient,
            boxShadow: [
              BoxShadow(
                color: Color(0x553D5CFF),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.directions_car_filled,
                color: Colors.white, size: 38),
          ),
        ),
        const SizedBox(height: 24),
        RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'Login ',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              TextSpan(
                text: 'To Your\nAccount',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8A9BFF),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Welcome back to SmartSync. Enter your details\nto access your smart mobility hub.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: Colors.white.withOpacity(0.7),
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    TextInputAction? textInputAction,
    Function(String)? onFieldSubmitted,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 13,
            letterSpacing: 0.5,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: _fieldBorderGradient,
          ),
          padding: const EdgeInsets.all(1.5),
          child: Container(
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: TextFormField(
              controller: controller,
              obscureText: obscureText,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              onFieldSubmitted: onFieldSubmitted,
              validator: validator,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  color: Colors.white54,
                  fontSize: 15,
                ),
                prefixIcon: Icon(icon, color: Colors.white70),
                suffixIcon: suffixIcon,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRememberMeAndForgotPassword() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        InkWell(
          onTap: () => setState(() => _rememberMe = !_rememberMe),
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: _rememberMe,
                  onChanged: (value) {
                    setState(() => _rememberMe = value ?? false);
                  },
                  activeColor: const Color(0xFF5E82FF),
                  checkColor: Colors.white,
                  side: const BorderSide(color: Colors.white30, width: 1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Remember me',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: _navigateToForgotPassword,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF66A2FF),
          ),
          child: const Text(
            'Forgot Password?',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: _buttonGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x553D5CFF),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Center(
            child: _isLoading
                ? const LottieLoading.small()
                : const Text(
                    'Login',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.4,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Color(0xFF4F5DFF)],
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'OR',
            style: TextStyle(
              color: Colors.white54,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF9E4CFF), Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSocialRow() {
    // Only show Google sign-in as it's the only implemented social auth
    return Center(
      child: _SocialIcon(
        icon: Icons.g_mobiledata,
        label: _isGoogleLoading ? 'Loading' : 'Continue with Google',
        onTap: _isGoogleLoading ? null : _handleGoogleLogin,
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6A6A), Color(0xFFFAB57A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        isLoading: _isGoogleLoading,
      ),
    );
  }

  Widget _buildSignupLink() {
    return Center(
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 15,
            color: Colors.white70,
          ),
          children: [
            const TextSpan(text: 'Don\'t have an account? '),
            TextSpan(
              text: 'Sign Up',
              style: const TextStyle(
                color: Color(0xFF7AA5FF),
                fontWeight: FontWeight.bold,
              ),
              recognizer: TapGestureRecognizer()..onTap = _navigateToSignup,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNeonCircle({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required double size,
    required Color color,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withOpacity(0.8), Colors.transparent],
            stops: const [0.0, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.6),
              blurRadius: 140,
              spreadRadius: 40,
            ),
          ],
        ),
      ),
    );
  }
}

class _SocialIcon extends StatelessWidget {
  const _SocialIcon({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.gradient,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final LinearGradient gradient;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final bool isDisabled = onTap == null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: isDisabled ? 0.55 : 1,
          child: AbsorbPointer(
            absorbing: isDisabled,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap ?? () {},
                borderRadius: BorderRadius.circular(40),
                child: Ink(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: gradient,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x442E3AFF),
                        blurRadius: 16,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Center(
                    child: isLoading
                        ? const LottieLoading.small()
                        : Icon(icon, color: Colors.white, size: 28),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
