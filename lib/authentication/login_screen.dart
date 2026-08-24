// login_screen.dart
import 'package:almaworks/authentication/auth_ui.dart';
import 'package:almaworks/authentication/registration_screen.dart';
import 'package:almaworks/authentication/welcome_screen.dart';
import 'package:almaworks/rbacsystem/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = userCredential.user;
      if (user == null) {
        throw Exception('User not found after login');
      }

      // Fetch user document by uid
      final querySnapshot = await FirebaseFirestore.instance
          .collection('Users')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        throw Exception('User document not found');
      }

      final userData = querySnapshot.docs.first.data();
      final username = querySnapshot.docs.first.id; // Doc ID is Username
      final role = userData['role'] as String? ?? 'Client'; // Fallback to Client

      // Keep the UserRoles/{uid} mirror in sync so pre-existing accounts
      // (registered before this mirror existed) and any account whose role
      // was changed directly in Users aren't gated out of role-restricted
      // features like Inventory. Safe to call every login — see
      // AuthService.ensureUserRoleMirror for why this can't grant a role the
      // account doesn't already have.
      await _authService.ensureUserRoleMirror(uid: user.uid, username: username, role: role);

      // Set persistent login state
      await _authService.setLoginState(true);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => WelcomeScreen(username: username, initialRole: role),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        switch (e.code) {
          case 'user-not-found':
            _errorMessage = 'No account found with this email address. Please check and try again.';
            break;
          case 'wrong-password':
            _errorMessage = 'Incorrect password. Please try again or reset your password.';
            break;
          case 'invalid-email':
            _errorMessage = 'The email address format is invalid. Please enter a valid email.';
            break;
          case 'user-disabled':
            _errorMessage = 'This account has been disabled. Please contact support.';
            break;
          case 'invalid-credential':
            _errorMessage = 'Invalid email or password. Please check your credentials and try again.';
            break;
          case 'too-many-requests':
            _errorMessage = 'Too many failed login attempts. Please try again later or reset your password.';
            break;
          default:
            _errorMessage = 'Login failed: ${e.message ?? "Unknown error occurred"}';
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'An unexpected error occurred. Please try again later.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your email address first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password reset email sent to $email. Please check your inbox.'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No account found with this email address.';
          break;
        case 'invalid-email':
          message = 'Invalid email address format.';
          break;
        default:
          message = 'Failed to send reset email. Please try again.';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthResponsiveShell(
      brandIcon: Icons.lock_outline_rounded,
      brandHeadline: 'Welcome back to\nAlmaWorks',
      brandSubtext:
          'Sign in to manage your projects, inventory, and team communication — all in one place.',
      form: AuthFormCard(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sign In',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AuthColors.navy,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Enter your details to access your account',
                style: GoogleFonts.poppins(fontSize: 13.5, color: Colors.grey[600]),
              ),
              const SizedBox(height: 28),
              AuthTextField(
                controller: _emailController,
                label: 'Email',
                hint: 'you@company.com',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Email is required';
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
                hint: 'Enter your password',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _handleLogin(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: Colors.grey[500],
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Password is required';
                  return null;
                },
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: AuthLinkButton(text: 'Forgot Password?', onPressed: _handleForgotPassword),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 6),
                AuthErrorBanner(message: _errorMessage!),
              ],
              const SizedBox(height: 22),
              AuthPrimaryButton(
                label: 'Login',
                isLoading: _isLoading,
                onPressed: _isLoading ? null : _handleLogin,
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Don't have an account? ",
                    style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 13.5),
                  ),
                  AuthLinkButton(
                    text: 'Sign Up',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => RegistrationScreen(logger: Logger())),
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