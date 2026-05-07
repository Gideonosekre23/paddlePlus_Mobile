import 'dart:async';
import 'package:flutter/material.dart';
import 'package:paddleapp/Apiendpoints/apiservices/auth_api_service.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  static const _blue = Color(0xFF76ACC6);

  int _step = 0; // 0=email, 1=otp, 2=new password
  bool _isLoading = false;
  String? _error;

  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureNew = true;
  bool _obscureConfirm = true;

  String _email = '';
  String _resetToken = '';

  // Resend countdown
  int _resendCooldown = 0;
  Timer? _resendTimer;

  void _startResendTimer() {
    _resendCooldown = 60;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) t.cancel();
      });
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Please enter your email address');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final resp = await AuthApiService.forgotPassword(email);
    if (!mounted) return;
    if (resp.success) {
      _email = email;
      _startResendTimer();
      setState(() {
        _step = 1;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        _error = resp.error ?? 'Failed to send OTP';
      });
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _error = 'Please enter the 6-digit code');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final resp = await AuthApiService.verifyResetOtp(_email, otp);
    if (!mounted) return;
    if (resp.success && resp.data != null) {
      _resetToken = resp.data!.resetToken;
      setState(() {
        _step = 2;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        _error = resp.error ?? 'Invalid or expired code';
      });
    }
  }

  Future<void> _resetPassword() async {
    final newPw = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;
    if (newPw.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    if (newPw != confirm) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final resp = await AuthApiService.resetPassword(_resetToken, newPw);
    if (!mounted) return;
    if (resp.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset successfully — please log in'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } else {
      setState(() {
        _isLoading = false;
        _error = resp.error ?? 'Failed to reset password';
      });
    }
  }

  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Forgot Password',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter your email and we\'ll send you a reset code.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Email address',
            prefixIcon: const Icon(Icons.email_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 24),
        _buildPrimaryButton('Send Code', _sendOtp),
      ],
    );
  }

  Widget _buildOtpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Enter Reset Code',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'A 6-digit code was sent to $_email',
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
          decoration: InputDecoration(
            labelText: 'Reset code',
            counterText: '',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 24),
        _buildPrimaryButton('Verify Code', _verifyOtp),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _isLoading ? null : () => setState(() { _step = 0; _error = null; }),
              child: const Text('Change email'),
            ),
            TextButton(
              onPressed: (_isLoading || _resendCooldown > 0) ? null : _resendOtp,
              child: Text(
                _resendCooldown > 0 ? 'Resend in ${_resendCooldown}s' : 'Resend Code',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _resendOtp() async {
    setState(() { _isLoading = true; _error = null; });
    final resp = await AuthApiService.forgotPassword(_email);
    if (!mounted) return;
    if (resp.success) {
      _startResendTimer();
      setState(() { _isLoading = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New code sent'), backgroundColor: Colors.green),
      );
    } else {
      setState(() { _isLoading = false; _error = resp.error ?? 'Failed to resend code'; });
    }
  }

  Widget _buildNewPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'New Password',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose a strong password — at least 8 characters.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _newPasswordController,
          obscureText: _obscureNew,
          decoration: InputDecoration(
            labelText: 'New password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirm,
          decoration: InputDecoration(
            labelText: 'Confirm password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 24),
        _buildPrimaryButton('Reset Password', _resetPassword),
      ],
    );
  }

  Widget _buildPrimaryButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!, style: const TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            if (_step == 0) _buildEmailStep(),
            if (_step == 1) _buildOtpStep(),
            if (_step == 2) _buildNewPasswordStep(),
          ],
        ),
      ),
    );
  }
}
