import 'package:flutter/material.dart';
import '../services/google_signin_2fa_service.dart';

class GoogleSignIn2FAPage extends StatefulWidget {
  const GoogleSignIn2FAPage({super.key});

  @override
  State<GoogleSignIn2FAPage> createState() => _GoogleSignIn2FAPageState();
}

class _GoogleSignIn2FAPageState extends State<GoogleSignIn2FAPage> {
  final _auth = GoogleSignIn2FAService();
  final _codeController = TextEditingController();
  
  bool _isLoading = false;
  bool _show2FAInput = false;
  String? _userEmail;
  String _message = '';
  bool _isError = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _message = '';
      _isError = false;
    });

    final result = await _auth.signInWithGoogle();

    setState(() {
      _isLoading = false;
      
      if (result['success'] == true) {
        if (result['requires2FA'] == true) {
          // Show 2FA input
          _show2FAInput = true;
          _userEmail = result['email'];
          _message = result['message'] ?? '2FA code sent to your email';
          _isError = false;
        } else {
          // Sign-in complete
          _message = result['message'] ?? 'Sign-in successful!';
          _isError = false;
          
          // Navigate to home screen
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              Navigator.of(context).pushReplacementNamed('/home');
            }
          });
        }
      } else {
        // Error
        _message = result['message'] ?? 'Sign-in failed';
        _isError = true;
      }
    });
  }

  Future<void> _handleVerify2FA() async {
    if (_codeController.text.isEmpty) {
      setState(() {
        _message = 'Please enter the 2FA code';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _message = '';
      _isError = false;
    });

    final result = await _auth.verify2FACode(
      _userEmail ?? '',
      _codeController.text.trim(),
    );

    setState(() {
      _isLoading = false;
      
      if (result['success'] == true) {
        _message = result['message'] ?? 'Verification successful!';
        _isError = false;
        
        // Navigate to home screen
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/home');
          }
        });
      } else {
        _message = result['message'] ?? 'Invalid code';
        _isError = true;
      }
    });
  }

  Future<void> _handleResendCode() async {
    if (_userEmail == null) return;

    setState(() {
      _isLoading = true;
      _message = '';
    });

    final result = await _auth.request2FACode(_userEmail!);

    setState(() {
      _isLoading = false;
      _message = result['message'] ?? 'Code sent';
      _isError = result['success'] != true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.shade900,
              Colors.purple.shade900,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo/Icon
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.home_rounded,
                      size: 60,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Title
                  const Text(
                    'Smart Home IoT',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Secure Login with 2FA',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 48),
                  
                  // Card for content
                  Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          if (!_show2FAInput) ...[
                            // Google Sign-In Button
                            _buildGoogleSignInButton(),
                          ] else ...[
                            // 2FA Code Input
                            _build2FAInput(),
                          ],
                          
                          const SizedBox(height: 16),
                          
                          // Message display
                          if (_message.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _isError
                                    ? Colors.red.shade50
                                    : Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _isError ? Icons.error : Icons.check_circle,
                                    color: _isError ? Colors.red : Colors.green,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _message,
                                      style: TextStyle(
                                        color: _isError ? Colors.red : Colors.green,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Info text
                  const Text(
                    'Your data is protected with\nGoogle Sign-In and Two-Factor Authentication',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
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

  Widget _buildGoogleSignInButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _handleGoogleSignIn,
        icon: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Image.asset(
                'assets/google_logo.png',
                height: 24,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.g_mobiledata, size: 24),
              ),
        label: Text(
          _isLoading ? 'Signing in...' : 'Sign in with Google',
          style: const TextStyle(fontSize: 16),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _build2FAInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Enter 2FA Code',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'A 6-digit code has been sent to:\n$_userEmail',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 24),
        
        // Code input field
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: 8,
          ),
          decoration: InputDecoration(
            hintText: '000000',
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.blue, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 24),
        
        // Verify button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleVerify2FA,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text(
                    'Verify Code',
                    style: TextStyle(fontSize: 16),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        
        // Resend code button
        Center(
          child: TextButton(
            onPressed: _isLoading ? null : _handleResendCode,
            child: const Text('Resend Code'),
          ),
        ),
        
        // Back button
        Center(
          child: TextButton(
            onPressed: () {
              setState(() {
                _show2FAInput = false;
                _codeController.clear();
                _message = '';
              });
            },
            child: const Text('Back to Sign In'),
          ),
        ),
      ],
    );
  }
}
