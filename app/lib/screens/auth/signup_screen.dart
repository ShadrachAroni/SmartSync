import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../providers/auth_provider.dart';
import '../../core/widgets/app_notifications.dart';
import '../../core/widgets/lottie_loading.dart';
import '../home/home_screen.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptTerms = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your full name';
    }
    if (value.length < 3) {
      return 'Name must be at least 3 characters';
    }
    return null;
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
      return 'Please enter a password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    if (!value.contains(RegExp(r'[A-Za-z]'))) {
      return 'Password must contain at least one letter';
    }
    if (!value.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != _passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  Future<void> _handleSignup({bool retrying = false}) async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptTerms) {
      _showMessage('Please accept the Terms and Conditions to continue',
          isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authService = ref.read(authServiceProvider);
      await authService.signUpWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
        _nameController.text.trim(),
      );
      await authService.signOut();
      if (!mounted) return;
      await _showSuccessDialog();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      // Special handling for email-already-in-use
      if (e.code == 'email-already-in-use') {
        await _showEmailExistsDialog();
      } else {
        final errorMessage = _getFirebaseErrorMessage(e);
        _showMessage(errorMessage, isError: true);

        // If app check or network issue, show retry option
        if (_isRetryableError(e)) {
          await _showRetryDialog(errorMessage);
        }
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage('An unexpected error occurred. Please try again.',
          isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

// Add this new method to show dialog for existing email
  Future<void> _showEmailExistsDialog() async {
    if (!mounted) return;

    await AppNotifications.showDialog(
      context,
      title: 'Email Already Registered',
      message:
          'An account with ${_emailController.text.trim()} already exists. Would you like to login instead?',
      type: AppNotificationType.warning,
      primaryLabel: 'Use Different Email',
      onPrimaryPressed: () async {},
      secondaryLabel: 'Go to Login',
      onSecondaryPressed: () async => Navigator.of(context).pop(),
    );
  }

  String _getFirebaseErrorMessage(FirebaseAuthException e) {
    // Map Firebase error codes to user-friendly messages
    switch (e.code) {
      case 'weak-password':
        return 'The password provided is too weak.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'invalid-email':
        return 'The email address is invalid.';
      case 'operation-not-allowed':
        return 'Email/password accounts are not enabled.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      case 'app-check-failed':
      case 'app-not-authorized':
      case 'invalid-app-credential':
      case 'internal-error':
        return 'Sign-up failed: Please check your internet or Firebase setup.';
      default:
        return e.message ?? 'Failed to create account. Please try again.';
    }
  }

  bool _isRetryableError(FirebaseAuthException e) {
    const retryableCodes = [
      'network-request-failed',
      'app-check-failed',
      'app-not-authorized',
      'invalid-app-credential',
      'internal-error',
    ];
    return retryableCodes.contains(e.code);
  }

  Future<void> _showRetryDialog(String message) async {
    if (!mounted) return;

    await AppNotifications.showDialog(
      context,
      title: 'Sign-up Failed',
      message: '$message\n\nWould you like to try again?',
      type: AppNotificationType.warning,
      primaryLabel: 'Retry',
      onPrimaryPressed: () async => _handleSignup(retrying: true),
      secondaryLabel: 'Cancel',
      onSecondaryPressed: () async {},
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    AppNotifications.showSnackBar(
      context,
      message: message,
      type: isError ? AppNotificationType.error : AppNotificationType.success,
    );
  }

  Future<void> _showSuccessDialog() async {
    await AppNotifications.showDialog(
      context,
      title: 'Verify Your Email',
      message:
          'We\'ve sent a verification link to ${_emailController.text}. Please verify your email, then login to continue.',
      type: AppNotificationType.success,
      primaryLabel: 'Go to Login',
      onPrimaryPressed: () async => Navigator.of(context).pop(),
    );
  }

  static const LinearGradient _backgroundGradient = LinearGradient(
    colors: [
      Color(0xFF050A1A),
      Color(0xFF080D20),
      Color(0xFF010308),
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
      Color(0xFF4D60FF),
      Color(0xFF974DFF),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  Color get _cardColor => const Color(0x6610172B);

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
              left: -40,
              size: 240,
              color: const Color(0x553D5CFF),
            ),
            _buildNeonCircle(
              bottom: -120,
              right: -50,
              size: 260,
              color: const Color(0x559A3DFF),
            ),
            SafeArea(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopRow(),
                      const SizedBox(height: 24),
                      _buildHeader(),
                      const SizedBox(height: 32),
                      _buildTextField(
                        controller: _nameController,
                        label: 'Full Name',
                        hint: 'Jaxon Justice',
                        icon: Icons.person_outline_rounded,
                        validator: _validateName,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 20),
                      _buildTextField(
                        controller: _emailController,
                        label: 'Email',
                        hint: 'jaxonjustice12@gmail.com',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        validator: _validateEmail,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 20),
                      _buildTextField(
                        controller: _passwordController,
                        label: 'Password',
                        hint: 'Create a password',
                        icon: Icons.lock_outline_rounded,
                        obscureText: _obscurePassword,
                        validator: _validatePassword,
                        textInputAction: TextInputAction.next,
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
                      const SizedBox(height: 20),
                      _buildTextField(
                        controller: _confirmPasswordController,
                        label: 'Confirm Password',
                        hint: 'Re-enter your password',
                        icon: Icons.lock_outline_rounded,
                        obscureText: _obscureConfirmPassword,
                        validator: _validateConfirmPassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _handleSignup(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: Colors.white70,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 26),
                      _buildTermsCheckbox(),
                      const SizedBox(height: 28),
                      _buildSignupButton(),
                      const SizedBox(height: 26),
                      _buildDivider(),
                      const SizedBox(height: 26),
                      _buildSocialRow(),
                      const SizedBox(height: 28),
                      _buildLoginLink(),
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
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white70),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.08),
          ),
          child: const Icon(Icons.lock_outline, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: _buttonGradient,
            boxShadow: [
              BoxShadow(
                color: Color(0x553D5CFF),
                blurRadius: 28,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.shield_moon, color: Colors.white, size: 40),
          ),
        ),
        const SizedBox(height: 22),
        RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'Create ',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              TextSpan(
                text: 'Your Account',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8BA5FF),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Sign up to unlock personalized smart mobility\nand stay synced across every device.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: Colors.white.withOpacity(0.72),
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
            color: Colors.white.withOpacity(0.68),
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
              style: const TextStyle(color: Colors.white, fontSize: 16),
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

  Widget _buildTermsCheckbox() {
    return InkWell(
      onTap: () => setState(() => _acceptTerms = !_acceptTerms),
      borderRadius: BorderRadius.circular(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: _acceptTerms,
              onChanged: (value) {
                setState(() => _acceptTerms = value ?? false);
              },
              activeColor: const Color(0xFF60C4FF),
              checkColor: Colors.black,
              side: const BorderSide(color: Colors.white24, width: 1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.75),
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(text: 'Agree to the '),
                    TextSpan(
                      text: 'Term of Use',
                      style: const TextStyle(
                        color: Color(0xFF4DD0FF),
                        fontWeight: FontWeight.w600,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap =
                            () => _showMessage('Terms of Use coming soon'),
                    ),
                    const TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: const TextStyle(
                        color: Color(0xFF9C7CFF),
                        fontWeight: FontWeight.w600,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap =
                            () => _showMessage('Privacy Policy coming soon'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignupButton() {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleSignup,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                blurRadius: 26,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Center(
            child: _isLoading
                ? const LottieLoading.small()
                : const Text(
                    'Sign Up',
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

  Widget _buildLoginLink() {
    return Center(
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 15,
            color: Colors.white70,
          ),
          children: [
            const TextSpan(text: 'Already have an account? '),
            TextSpan(
              text: 'Login',
              style: const TextStyle(
                color: Color(0xFF7AA5FF),
                fontWeight: FontWeight.bold,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: const [
        Expanded(
          child: SizedBox(
            height: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Color(0xFF4F5DFF)],
                ),
              ),
            ),
          ),
        ),
        Padding(
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
          child: SizedBox(
            height: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF9E4CFF), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSocialRow() {
    return Row(
      children: [
        _AuthSocialIcon(
          icon: Icons.facebook_rounded,
          label: 'Facebook',
          onTap: () => _showMessage('Facebook sign-up coming soon'),
          gradient: const LinearGradient(
            colors: [Color(0xFF2E7EFF), Color(0xFF465CFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        const SizedBox(width: 16),
        _AuthSocialIcon(
          icon: Icons.g_mobiledata,
          label: _isGoogleLoading ? 'Loading' : 'Google',
          onTap: _isGoogleLoading ? null : _handleGoogleSignup,
          gradient: const LinearGradient(
            colors: [Color(0xFFFF6A6A), Color(0xFFFAB57A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          isLoading: _isGoogleLoading,
        ),
        const SizedBox(width: 16),
        _AuthSocialIcon(
          icon: Icons.apple,
          label: 'Apple',
          onTap: () => _showMessage('Apple sign-up coming soon'),
          gradient: const LinearGradient(
            colors: [Color(0xFF3B3B3B), Color(0xFF000000)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ],
    );
  }

  Future<void> _handleGoogleSignup() async {
    setState(() => _isGoogleLoading = true);
    try {
      final authService = ref.read(authServiceProvider);
      await authService.signInWithGoogle();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
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

class _AuthSocialIcon extends StatelessWidget {
  const _AuthSocialIcon({
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
    return Expanded(
      child: Column(
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
      ),
    );
  }
}
