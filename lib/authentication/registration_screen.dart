// registration_screen.dart
import 'package:almaworks/authentication/auth_ui.dart';
import 'package:almaworks/authentication/login_screen.dart';
import 'package:almaworks/authentication/welcome_screen.dart';
import 'package:almaworks/rbacsystem/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
// ignore: implementation_imports
import 'package:logger/src/logger.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key, required Logger logger});

  @override
  RegistrationScreenState createState() => RegistrationScreenState();
}

class RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      setState(() => _errorMessage = 'Username is required');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Check if username (doc ID) already exists
      final existingDoc = await FirebaseFirestore.instance.collection('Users').doc(username).get();
      if (existingDoc.exists) {
        throw Exception('Username already taken');
      }

      // Create user with email and password
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = userCredential.user;
      if (user == null) {
        throw Exception('User creation failed');
      }

      // Create document in 'Users' with ID = username
      final userData = {
        'Username': username,
        'email': _emailController.text.trim(),
        'uid': user.uid,
        'role': 'Client', // Default to lowest role
      };

      await FirebaseFirestore.instance.collection('Users').doc(username).set(userData);

      // Mirror uid -> role in UserRoles so Firestore security rules can look
      // up the caller's role via a direct get() (Users doc IDs are usernames,
      // not uids, so rules can't query Users directly).
      await _authService.ensureUserRoleMirror(uid: user.uid, username: username, role: 'Client');

      // Set persistent login state
      await _authService.setLoginState(true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration successful! Welcome to AlmaWorks.'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => WelcomeScreen(username: username, initialRole: 'Client'),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        switch (e.code) {
          case 'email-already-in-use':
            _errorMessage = 'This email address is already registered. Please login instead.';
            break;
          case 'invalid-email':
            _errorMessage = 'The email address format is invalid. Please enter a valid email.';
            break;
          case 'weak-password':
            _errorMessage = 'Password is too weak. Please use at least 6 characters with a mix of letters and numbers.';
            break;
          case 'operation-not-allowed':
            _errorMessage = 'Email/password accounts are not enabled. Please contact support.';
            break;
          default:
            _errorMessage = 'Registration failed: ${e.message ?? "Unknown error occurred"}';
        }
      });
    } catch (e) {
      setState(() {
        if (e.toString().contains('Username already taken')) {
          _errorMessage = 'This username is already taken. Please choose a different one.';
        } else {
          _errorMessage = 'An unexpected error occurred. Please try again later.';
        }
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthResponsiveShell(
      brandIcon: Icons.person_add_alt_1_rounded,
      brandHeadline: 'Join the\nAlmaWorks team',
      brandSubtext:
          'Create an account to start tracking projects, assets, and communication in one workspace.',
      form: AuthFormCard(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _BackButton(onTap: () => Navigator.pop(context)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Create Account',
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AuthColors.navy,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Fill in your details to get started',
                style: GoogleFonts.poppins(fontSize: 13.5, color: Colors.grey[600]),
              ),
              const SizedBox(height: 28),
              AuthTextField(
                controller: _usernameController,
                label: 'Username',
                hint: 'Choose a unique username',
                icon: Icons.account_circle_outlined,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Username is required';
                  }
                  if (value.trim().length < 3) {
                    return 'Username must be at least 3 characters';
                  }
                  if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value.trim())) {
                    return 'Username can only contain letters, numbers, and underscores';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              AuthTextField(
                controller: _emailController,
                label: 'Email',
                hint: 'you@company.com',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Email is required';
                  }
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              AuthTextField(
                controller: _passwordController,
                label: 'Password',
                hint: 'Create a strong password',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _signUp(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: Colors.grey[500],
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Password is required';
                  }
                  if (value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                AuthErrorBanner(message: _errorMessage!),
              ],
              const SizedBox(height: 22),
              AuthPrimaryButton(
                label: 'Sign Up',
                isLoading: _isLoading,
                onPressed: _isLoading ? null : _signUp,
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Already have an account? ',
                    style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 13.5),
                  ),
                  AuthLinkButton(
                    text: 'Log In',
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => const LoginScreen()),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small circular back affordance used in place of the old AppBar back
/// button — the new auth shell has no AppBar, so this sits inline above the
/// form heading instead, with the same tactile press feedback as the rest
/// of the auth UI.
class _BackButton extends StatefulWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  State<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends State<_BackButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.9 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AuthColors.navy.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back_rounded, size: 19, color: AuthColors.navy),
          ),
        ),
      ),
    );
  }
}