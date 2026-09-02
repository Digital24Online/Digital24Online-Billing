import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'firebase_service.dart';

class FirebaseAuthScreen extends StatefulWidget {
  const FirebaseAuthScreen({
    super.key,
    required this.onAuthenticated,
  });

  final VoidCallback onAuthenticated;

  @override
  State<FirebaseAuthScreen> createState() => _FirebaseAuthScreenState();
}

class _FirebaseAuthScreenState extends State<FirebaseAuthScreen> {
  final FirebaseService _firebase = FirebaseService.instance;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _registerMode = false;
  bool _loading = false;
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;

  String? _error;

  String _errorMessage(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'সঠিক Email Address দিন।';
        case 'weak-password':
        case 'invalid-password':
          return 'Password কমপক্ষে ৬ অক্ষরের এবং নিরাপদ হতে হবে।';
        case 'email-already-in-use':
          return 'এই Email দিয়ে ইতিমধ্যে Account আছে। Login করুন।';
        case 'invalid-credential':
          return 'Email অথবা Password সঠিক নয়।';
        case 'user-disabled':
          return 'এই Account নিষ্ক্রিয় করা হয়েছে।';
        case 'too-many-requests':
          return 'অনেকবার চেষ্টা হয়েছে। কিছুক্ষণ পরে আবার চেষ্টা করুন।';
        case 'network-request-failed':
          return 'Internet connection পাওয়া যাচ্ছে না।';
        case 'operation-not-allowed':
          return 'Firebase Email/Password Authentication চালু করা নেই।';
        default:
          return error.message ?? 'Authentication-এ সমস্যা হয়েছে।';
      }
    }

    return error.toString().replaceFirst('Exception: ', '');
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (email.isEmpty) {
      setState(() => _error = 'Email Address দিন।');
      return;
    }

    if (password.isEmpty) {
      setState(() => _error = 'Password দিন।');
      return;
    }

    if (password.length < 6) {
      setState(() => _error = 'Password কমপক্ষে ৬ অক্ষরের হতে হবে।');
      return;
    }

    if (_registerMode && password != confirm) {
      setState(() => _error = 'দুইটি Password একই নয়।');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_registerMode) {
        await _firebase.createAccount(
          email: email,
          password: password,
        );
      } else {
        await _firebase.signIn(
          email: email,
          password: password,
        );
      }

      if (!mounted) return;

      widget.onAuthenticated();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = _errorMessage(e);
      });
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() => _error = 'আগে আপনার Email Address লিখুন।');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _firebase.sendPasswordResetEmail(email);

      if (!mounted) return;

      setState(() => _loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password reset করার জন্য আপনার Email-এ নির্দেশনা পাঠানো হয়েছে।',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = _errorMessage(e);
      });
    }
  }

  void _toggleMode() {
    FocusScope.of(context).unfocus();

    setState(() {
      _registerMode = !_registerMode;
      _error = null;
      _confirmPasswordController.clear();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title =
        _registerMode ? 'নতুন Account তৈরি করুন' : 'Login করুন';

    final buttonText =
        _registerMode ? 'Account তৈরি করুন' : 'Login';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 82,
                        height: 82,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: const Color(0xFF0867C8),
                        ),
                        child: const Icon(
                          Icons.wifi,
                          color: Colors.white,
                          size: 46,
                        ),
                      ),

                      const SizedBox(height: 18),

                      const Text(
                        'Digital 24 Online Billing',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 6),

                      Text(
                        _registerMode
                            ? 'Cloud Account তৈরি করুন'
                            : 'আপনার Billing Account-এ প্রবেশ করুন',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 24),

                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        enabled: !_loading,
                        decoration: const InputDecoration(
                          labelText: 'Email Address',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),

                      const SizedBox(height: 12),

                      TextField(
                        controller: _passwordController,
                        obscureText: _hidePassword,
                        enabled: !_loading,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: _loading
                                ? null
                                : () => setState(
                                      () => _hidePassword = !_hidePassword,
                                    ),
                            icon: Icon(
                              _hidePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                          ),
                        ),
                      ),

                      if (_registerMode) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _confirmPasswordController,
                          obscureText: _hideConfirmPassword,
                          enabled: !_loading,
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Password আবার লিখুন',
                            prefixIcon:
                                const Icon(Icons.lock_reset_outlined),
                            suffixIcon: IconButton(
                              onPressed: _loading
                                  ? null
                                  : () => setState(
                                        () => _hideConfirmPassword =
                                            !_hideConfirmPassword,
                                      ),
                              icon: Icon(
                                _hideConfirmPassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                            ),
                          ),
                        ),
                      ],

                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 18),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _submit,
                          icon: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  _registerMode
                                      ? Icons.person_add_alt_1
                                      : Icons.login,
                                ),
                          label: Text(buttonText),
                        ),
                      ),

                      if (!_registerMode) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _loading ? null : _forgotPassword,
                          child: const Text('Password ভুলে গেছেন?'),
                        ),
                      ],

                      const Divider(height: 28),

                      TextButton.icon(
                        onPressed: _loading ? null : _toggleMode,
                        icon: Icon(
                          _registerMode
                              ? Icons.login
                              : Icons.person_add_alt_1,
                        ),
                        label: Text(
                          _registerMode
                              ? 'আগে থেকেই Account আছে? Login করুন'
                              : 'নতুন Account তৈরি করুন',
                        ),
                      ),

                      const SizedBox(height: 8),

                      const Text(
                        'Cloud Account আপনার Billing Data-কে\n'
                        'একাধিক Device ও Reinstall-এর জন্য পরিচিত রাখবে।',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
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
}
