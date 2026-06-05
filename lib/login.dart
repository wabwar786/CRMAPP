// lib/login.dart
// [CHANGED] Full rewrite with:
//   - Stable login with longer timeout and no duplicate taps
//   - Role check completely removed
//   - Raw username/password passed to WebViewScreen
//   - Password saved to SharedPreferences for Web View switch

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartcrm_project/dashboard.dart';
import 'package:smartcrm_project/webview_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailOrUsernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  // [FIXED] Guard flag to prevent duplicate login taps
  bool _loginInProgress = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  final Color _primaryColor = const Color(0xFF049881);
  final Color _backgroundColor = const Color(0xFFF5F5F5);
  final Color _lightTextColor = const Color(0xFF757575);
  final Color _errorColor = const Color(0xFFD32F2F);
  final Color _successColor = const Color(0xFF388E3C);

  static const String _baseUrl =
      'https://smartcrmbackend-production-56c0.up.railway.app';
  static const String _loginEndpoint = '/login';

  // [FIXED] Increased timeout from 10s to 30s to prevent premature timeouts
  static const Duration _apiTimeout = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _checkSavedLogin();
  }

  Future<void> _checkSavedLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('userId');
      final cCode = prefs.getString('cCode');
      final username = prefs.getString('username');

      if (userId != null && cCode != null && username != null) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DashboardScreen(
              userId: userId,
              cCode: cCode,
              username: username,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error checking saved login: $e');
    }
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1).animate(
      CurvedAnimation(
          parent: _animationController, curve: Curves.easeOutBack),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailOrUsernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showToast(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: isError ? _errorColor : _successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _handleLogin() async {
    // [FIXED] Prevent duplicate taps — guard with _loginInProgress flag
    if (_loginInProgress) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _loginInProgress = true;
    });

    // [CHANGED] Capture raw typed values before any async gap
    final String rawUsername = _emailOrUsernameController.text.trim();
    final String rawPassword = _passwordController.text;

    http.Response? response;
    try {
      final uri = Uri.parse('$_baseUrl$_loginEndpoint');
      final body = jsonEncode({
        'loginValue': rawUsername,
        'password': rawPassword,
      });

      response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(_apiTimeout);

      final contentType = response.headers['content-type'] ?? '';
      final isJson = contentType.toLowerCase().contains('application/json');

      if (!isJson) {
        _handleFailedLogin(response.body);
        return;
      }

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        // [CHANGED] Pass raw username/password, not API-returned user_name
        await _handleSuccessfulLogin(data['user'], rawUsername, rawPassword);
      } else {
        _handleFailedLogin(
          data['message'] ??
              'Login failed with status code ${response.statusCode}',
        );
      }
    } on SocketException {
      _showToast('Network error: Cannot connect to server. Check your internet connection.');
    } on TimeoutException {
      // [FIXED] Clear message instead of silent failure
      _showToast('Connection timed out. Please check your internet and try again.');
    } on http.ClientException catch (e) {
      _showToast('Network error: ${e.message}');
    } on FormatException catch (e) {
      _showToast('Server response error. Please try again.');
      debugPrint('JSON decode error: $e\nResponse: ${response?.body}');
    } catch (e) {
      _showToast('An unexpected error occurred. Please try again.');
      debugPrint('Login error: $e');
    } finally {
      // [FIXED] Always reset loading/guard state even on error
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loginInProgress = false;
        });
      }
    }
  }

  Future<void> _handleSuccessfulLogin(
    Map<String, dynamic> user,
    String rawUsername,
    String rawPassword,
  ) async {
    try {
      if (user['ID'] == null || user['c_code'] == null) {
        throw Exception('Invalid user data received from server');
      }

      // [CHANGED] Role check completely removed — every valid user is allowed

      _showToast('Login successful!', isError: false);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userId', user['ID'].toString());
      await prefs.setString('cCode', user['c_code'].toString());
      await prefs.setString('username', rawUsername);
      await prefs.setString('role', user['role']?.toString() ?? '');
      // [CHANGED] Save raw password for WebView URL reconstruction
      // SECURITY NOTE: Storing plain-text password in SharedPreferences and
      // passing it as a URL query parameter is NOT recommended for production.
      // Recommended alternatives: short-lived one-time tokens, POST-based login,
      // or SSO cookie handoff. Implemented as-is per project requirement.
      await prefs.setString('password', rawPassword);

      if (!mounted) return;

      // [CHANGED] After login, open WebViewScreen first
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => WebViewScreen(
            userId: user['ID'].toString(),
            cCode: user['c_code'].toString(),
            // [CHANGED] Use raw username/password typed by user — not API field
            username: rawUsername,
            password: rawPassword,
          ),
        ),
      );
    } on Exception catch (e) {
      _handleFailedLogin(e.toString());
    }
  }

  void _handleFailedLogin(String message) {
    String cleaned = message.replaceAll(RegExp(r'<[^>]*>'), '');

    if (cleaned.startsWith('{') || cleaned.startsWith('[')) {
      try {
        final json = jsonDecode(cleaned);
        if (json is Map) {
          cleaned = json['message']?.toString() ??
              json['error']?.toString() ??
              cleaned;
        }
      } catch (_) {}
    }

    const errorMapping = {
      'invalid credentials': 'Invalid email/username or password',
      'user not found': 'Account not found',
      'incorrect password': 'Incorrect password',
      'account locked': 'Account temporarily locked. Try again later.',
    };

    final lower = cleaned.toLowerCase();
    for (final entry in errorMapping.entries) {
      if (lower.contains(entry.key)) {
        cleaned = entry.value;
        break;
      }
    }

    debugPrint('Login failed: $cleaned\nOriginal: $message');
    _showToast(cleaned.isNotEmpty ? cleaned : 'Login failed. Please try again.');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: size.width * 0.06,
            vertical: 32,
          ),
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) => Opacity(
              opacity: _fadeAnimation.value,
              child: Transform.scale(scale: _scaleAnimation.value, child: child),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  _buildHeaderSection(size),
                  const SizedBox(height: 32),
                  _buildEmailField(),
                  const SizedBox(height: 16),
                  _buildPasswordField(),
                  const SizedBox(height: 28),
                  _buildLoginButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection(Size size) {
    return Column(
      children: [
        Image.asset(
          'assets/Appicon.png',
          width: size.width * 0.45,
          height: size.width * 0.45,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.account_circle, size: size.width * 0.45, color: _primaryColor),
        ),
        const SizedBox(height: 16),
        Text(
          'Login',
          style: GoogleFonts.poppins(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: _primaryColor,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Welcome back! Please enter your credentials',
          style: GoogleFonts.poppins(fontSize: 14, color: _lightTextColor),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return _buildInputField(
      controller: _emailOrUsernameController,
      label: 'Email or Username',
      icon: Icons.person_outline,
    );
  }

  Widget _buildPasswordField() {
    return _buildInputField(
      controller: _passwordController,
      label: 'Password',
      icon: Icons.lock_outline,
      isPassword: true,
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: isPassword ? _obscurePassword : false,
        textInputAction:
            isPassword ? TextInputAction.done : TextInputAction.next,
        onFieldSubmitted: isPassword ? (_) => _handleLogin() : null,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.poppins(color: _lightTextColor),
          prefixIcon: Icon(icon, color: _lightTextColor),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: _lightTextColor,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) return 'Please enter $label';
          if (isPassword && value.length < 4) {
            return 'Password is too short';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        // [FIXED] Disable button while login is in progress
        onPressed: (_isLoading || _loginInProgress) ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryColor,
          disabledBackgroundColor: _primaryColor.withOpacity(0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                'SIGN IN',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}