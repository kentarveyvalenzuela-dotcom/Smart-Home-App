import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/google_signin_2fa_service.dart';
import '../services/notification_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'home_screen.dart';
import 'forgot_password_page.dart';
import 'google_signin_2fa_page.dart';
import '../main.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with TickerProviderStateMixin {
  bool isLogin = true;
  bool isLoading = false;

  // Create separate form keys to avoid duplicate GlobalKey error
  late GlobalKey<FormState> _formKey;
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPassController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    // Initialize form key
    _formKey = GlobalKey<FormState>();

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPassController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _handleEmailAuth() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      Map<String, dynamic>? result;

      if (isLogin) {
        result = await _authService.signInWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
        );
      } else {
        result = await _authService.signUpWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
          _nameController.text.trim(),
        );
      }

      if (result != null && result['success']) {
        if (isLogin) {
          _showSnackBar('Welcome back!');
          // Add notification for email sign-in
          NotificationService()
              .addEmailSignInNotification(_emailController.text.trim());
          // Navigate to home screen only on login
          if (mounted) {
            Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (_) => const HomeScreen()));
          }
        } else {
          // Registration success - show message and switch to login
          _showSnackBar(
            result['message'] ?? 'Account created successfully! Please login.',
            isError: false,
          );
          setState(() {
            isLogin = true;
            _passwordController.clear();
            _confirmPassController.clear();
          });
        }
      } else {
        _showSnackBar(
          result?['error'] ?? 'Authentication failed',
          isError: true,
        );
      }
    } catch (e) {
      String errorMsg = e.toString();
      if (e.toString().contains('timed out') ||
          e.toString().contains('SocketException') ||
          e.toString().contains('ClientException') ||
          e.toString().contains('Failed to fetch')) {
        errorMsg =
            'Backend server is unavailable or the API URL is incorrect. Please check the backend configuration or start the backend service.';
      }
      _showSnackBar('Error: $errorMsg', isError: true);
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.darkBg,
              AppColors.darkBgSecondary,
              Color(0xFF1a3a5c),
              AppColors.primaryBlueDark,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.3, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated Logo
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _pulseAnimation.value,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primaryBlue,
                                AppColors.electricPurple
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(25),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryBlue
                                    .withValues(alpha: 0.4),
                                blurRadius: 25,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(20),
                          child: const Icon(
                            Icons.bolt_rounded,
                            size: 70,
                            color: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // Title
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [AppColors.primaryBlue, AppColors.electricGreen],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ).createShader(bounds),
                    child: const Text(
                      "SMART HOME IOT",
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    "Control your home with intelligence",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w300,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Auth Form Card
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.1, 0.0),
                            end: Offset.zero,
                          ).animate(CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeInOut,
                          )),
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      key: ValueKey<bool>(isLogin),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.98),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color:
                                AppColors.primaryBlue.withValues(alpha: 0.15),
                            blurRadius: 25,
                            spreadRadius: 5,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(30),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Form Title
                            Text(
                              isLogin ? "Welcome Back!" : "Create Account",
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkBg,
                              ),
                            ),

                            Text(
                              isLogin
                                  ? "Sign in to continue"
                                  : "Join the smart home revolution",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),

                            const SizedBox(height: 30),

                            // Name field (registration only)
                            if (!isLogin) ...[
                              _buildTextField(
                                controller: _nameController,
                                label: "Full Name",
                                icon: Icons.person_outline,
                                validator: (value) =>
                                    value!.isEmpty ? "Enter your name" : null,
                              ),
                              const SizedBox(height: 16),
                            ],

                            // Email field
                            _buildTextField(
                              controller: _emailController,
                              label: "Email Address",
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (value!.isEmpty) return "Enter your email";
                                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+')
                                    .hasMatch(value)) {
                                  return "Enter a valid email";
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: 16),

                            // Password field
                            _buildTextField(
                              controller: _passwordController,
                              label: "Password",
                              icon: Icons.lock_outline,
                              obscureText: _obscurePassword,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: AppColors.primaryBlueDark,
                                ),
                                onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword),
                              ),
                              validator: (value) =>
                                  value!.length < 6 ? "Min 6 characters" : null,
                            ),

                            // Confirm password (registration only)
                            if (!isLogin) ...[
                              const SizedBox(height: 16),
                              _buildTextField(
                                controller: _confirmPassController,
                                label: "Confirm Password",
                                icon: Icons.lock,
                                obscureText: _obscureConfirm,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirm
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: AppColors.primaryBlueDark,
                                  ),
                                  onPressed: () => setState(
                                      () => _obscureConfirm = !_obscureConfirm),
                                ),
                                validator: (value) =>
                                    value != _passwordController.text
                                        ? "Passwords don't match"
                                        : null,
                              ),
                            ],

                            const SizedBox(height: 12),

                            // Forgot Password Link (only show in login mode)
                            if (isLogin)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const ForgotPasswordPage(),
                                      ),
                                    );
                                  },
                                  child: const Text(
                                    'Forgot Password?',
                                    style: TextStyle(
                                      color: AppColors.primaryBlue,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),

                            const SizedBox(height: 30),

                            // Submit Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryBlue,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  elevation: 5,
                                ),
                                onPressed: isLoading ? null : _handleEmailAuth,
                                child: isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation(
                                              Colors.white),
                                        ),
                                      )
                                    : Text(
                                        isLogin ? "Sign In" : "Create Account",
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Divider
                            Row(
                              children: [
                                Expanded(
                                  child: Divider(color: Colors.grey.shade400),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: Text(
                                    "OR",
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Divider(color: Colors.grey.shade400),
                                ),
                              ],
                            ),

                            const SizedBox(height: 20),

                            // Google Sign In Button
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  side: BorderSide(color: Colors.grey.shade300),
                                  backgroundColor: Colors.grey.shade50,
                                ),
                                onPressed: isLoading
                                    ? null
                                    : () async {
                                        setState(() => isLoading = true);
                                        try {
                                          if (kIsWeb) {
                                            // Web: redirect via backend OAuth endpoint
                                            final result = await _authService
                                                .signInWithGoogle();
                                            if (result != null &&
                                                result['success'] == true) {
                                              // Check if 2FA is required
                                              if (result['requires2FA'] ==
                                                  true) {
                                                // TODO: Navigate to 2FA page
                                                _showSnackBar(
                                                    '2FA required - redirecting...',
                                                    isError: false);
                                                // Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GoogleSignIn2FAPage()));
                                              } else {
                                                _showSnackBar(
                                                    'Google sign-in successful!');
                                                // Add notification for Google sign-in
                                                final userEmail = result['user']
                                                        ?['email'] ??
                                                    'Google User';
                                                NotificationService()
                                                    .addGoogleSignInNotification(
                                                        userEmail);
                                                if (mounted) {
                                                  Navigator.pushReplacement(
                                                      context,
                                                      MaterialPageRoute(
                                                          builder: (_) =>
                                                              const HomeScreen()));
                                                }
                                              }
                                            } else {
                                              _showSnackBar(
                                                  result?['error'] ??
                                                      'Google sign-in failed',
                                                  isError: true);
                                            }
                                          } else {
                                            // Mobile: use GoogleSignIn2FAService which signs in with Firebase and informs backend
                                            final mobileRes =
                                                await GoogleSignIn2FAService()
                                                    .signInWithGoogle();
                                            if (mobileRes['success'] == true) {
                                              if (mobileRes['requires2FA'] ==
                                                  true) {
                                                // navigate to 2FA page
                                                Navigator.of(context).push(
                                                    MaterialPageRoute(
                                                        builder: (_) =>
                                                            const GoogleSignIn2FAPage()));
                                              } else {
                                                _showSnackBar(
                                                    'Google sign-in successful!');
                                                // Add notification for Google sign-in
                                                final userEmail =
                                                    mobileRes['email'] ??
                                                        'Google User';
                                                NotificationService()
                                                    .addGoogleSignInNotification(
                                                        userEmail);
                                                if (mounted) {
                                                  Navigator.pushReplacement(
                                                      context,
                                                      MaterialPageRoute(
                                                          builder: (_) =>
                                                              const HomeScreen()));
                                                }
                                              }
                                            } else {
                                              _showSnackBar(
                                                  mobileRes['message'] ??
                                                      'Google sign-in failed',
                                                  isError: true);
                                            }
                                          }
                                        } catch (e) {
                                          _showSnackBar('Error: $e',
                                              isError: true);
                                        } finally {
                                          if (mounted) {
                                            setState(() => isLoading = false);
                                          }
                                        }
                                      },
                                child: SizedBox(
                                  width: double.infinity,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.g_mobiledata,
                                        color: AppColors.primaryBlueDark,
                                        size: 24,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          "Continue with Google",
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.darkBg,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 25),

                            // Toggle Auth Mode
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                    isLogin
                                        ? "Don't have an account?"
                                        : "Already have an account?",
                                    style:
                                        TextStyle(color: Colors.grey.shade600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Flexible(
                                  child: TextButton(
                                    onPressed: isLoading
                                        ? null
                                        : () {
                                            // Reset form key to avoid duplicate GlobalKey errors
                                            setState(() {
                                              isLogin = !isLogin;
                                              _formKey = GlobalKey<FormState>();
                                            });
                                          },
                                    child: Text(
                                      isLogin ? "Sign Up" : "Sign In",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryBlue,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.grey.shade50,
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(
            color: AppColors.primaryBlue,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(
            color: Colors.red,
            width: 2,
          ),
        ),
        prefixIcon: Icon(icon, color: AppColors.primaryBlueDark),
        suffixIcon: suffixIcon,
      ),
    );
  }
}
