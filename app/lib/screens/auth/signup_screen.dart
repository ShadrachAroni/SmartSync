import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../providers/auth_provider.dart';

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

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: Colors.orange.shade700,
              size: 28,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Email Already Registered',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'An account with the email',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _emailController.text.trim(),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF00BFA5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'already exists.',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Would you like to:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.edit),
            label: const Text('Use Different Email'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Go back to login screen
            },
            icon: const Icon(Icons.login, size: 18),
            label: const Text('Go to Login'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00BFA5),
              foregroundColor: Colors.white,
            ),
          ),
        ],
        actionsAlignment: MainAxisAlignment.spaceBetween,
      ),
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

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Sign-up Failed',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        content: Text(
          '$message\n\nWould you like to try again?',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _handleSignup(retrying: true);
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00BFA5),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: isError ? 4 : 3),
      ),
    );
  }

  Future<void> _showSuccessDialog() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.mark_email_read_outlined,
                size: 48,
                color: Colors.green.shade600,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Verify Your Email',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'We\'ve sent a verification link to',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _emailController.text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF00BFA5),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Please check your email and click the verification link to activate your account.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pop(); // Go back to login
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BFA5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Got it!',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                _buildHeader(),
                const SizedBox(height: 40),
                _buildTextField(
                  controller: _nameController,
                  label: 'Full Name',
                  hint: 'John Doe',
                  icon: Icons.person_outline_rounded,
                  validator: _validateName,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 20),
                _buildTextField(
                  controller: _emailController,
                  label: 'Email Address',
                  hint: 'john.doe@example.com',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: _validateEmail,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 20),
                _buildTextField(
                  controller: _passwordController,
                  label: 'Password',
                  hint: 'At least 6 characters',
                  icon: Icons.lock_outline_rounded,
                  obscureText: _obscurePassword,
                  validator: _validatePassword,
                  textInputAction: TextInputAction.next,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: Colors.grey.shade600,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
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
                      color: Colors.grey.shade600,
                    ),
                    onPressed: () {
                      setState(() =>
                          _obscureConfirmPassword = !_obscureConfirmPassword);
                    },
                  ),
                ),
                const SizedBox(height: 24),
                _buildTermsCheckbox(),
                const SizedBox(height: 32),
                _buildSignupButton(),
                const SizedBox(height: 24),
                _buildLoginLink(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Create Account',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Sign up to get started with SmartSync',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey.shade600,
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
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onFieldSubmitted: onFieldSubmitted,
          validator: validator,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 15,
            ),
            prefixIcon: Icon(icon, color: Colors.grey.shade600),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF00BFA5),
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.red.shade300),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.red.shade400, width: 2),
            ),
            errorStyle: TextStyle(
              color: Colors.red.shade600,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTermsCheckbox() {
    return InkWell(
      onTap: () => setState(() => _acceptTerms = !_acceptTerms),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
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
                activeColor: const Color(0xFF00BFA5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
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
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                    children: [
                      const TextSpan(text: 'I agree to the '),
                      TextSpan(
                        text: 'Terms & Conditions',
                        style: const TextStyle(
                          color: Color(0xFF00BFA5),
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            _showMessage('Terms & Conditions coming soon');
                          },
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: const TextStyle(
                          color: Color(0xFF00BFA5),
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            _showMessage('Privacy Policy coming soon');
                          },
                      ),
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

  Widget _buildSignupButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleSignup,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00BFA5),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        child: _isLoading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Create Account',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }

  Widget _buildLoginLink() {
    return Center(
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: 15,
            color: Colors.grey.shade700,
          ),
          children: [
            const TextSpan(text: 'Already have an account? '),
            TextSpan(
              text: 'Login',
              style: const TextStyle(
                color: Color(0xFF00BFA5),
                fontWeight: FontWeight.bold,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  Navigator.of(context).pop();
                },
            ),
          ],
        ),
      ),
    );
  }
}
