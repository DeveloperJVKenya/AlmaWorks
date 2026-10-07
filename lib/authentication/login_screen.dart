// login_screen.dart
import 'package:almaworks/authentication/auth_ui.dart';
import 'package:almaworks/authentication/registration_screen.dart';
import 'package:almaworks/authentication/welcome_screen.dart';
import 'package:almaworks/rbacsystem/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/theme/app_colors.dart';
import 'package:almaworks/core/errors/friendly_error.dart';

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
        throw UserFacingException(l10nNow.errSignInAgain);
      }

      // Fetch user document by uid
      final querySnapshot = await FirebaseFirestore.instance
          .collection('Users')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        throw UserFacingException(l10nNow.profileNotFound);
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
      final l = l10nNow;
      setState(() {
        _errorMessage = switch (e.code) {
          'user-not-found' => l.accountNotFound,
          'wrong-password' => l.incorrectPassword,
          'too-many-requests' => l.tooManyLoginAttempts,
          _ => friendlyError(e, action: l.signInFailed),
        };
      });
    } catch (e) {
      setState(() {
        _errorMessage = friendlyError(e, action: l10nNow.signInFailed);
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

    final l = context.l10n;
    if (email.isEmpty) {
      showWarningSnack(context, l.enterEmailFirst);
      return;
    }

    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
      showWarningSnack(context, l.errInvalidEmail);
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (mounted) showSuccessSnack(context, l.passwordResetSent(email));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'user-not-found') {
        showErrorMessage(context, l.accountNotFound);
      } else {
        showErrorSnack(context, e, action: l.couldNotSendResetEmail);
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
      brandHeadline: context.l10n.welcomeBackHeadline,
      brandSubtext: context.l10n.welcomeBackSubtext,
      form: AuthFormCard(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.signIn,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandInk,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.signInSubtitle,
                style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 28),
              AuthTextField(
                controller: _emailController,
                label: context.l10n.email,
                hint: context.l10n.emailHint,
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.isEmpty) return context.l10n.emailRequired;
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                    return context.l10n.errInvalidEmail;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              AuthTextField(
                controller: _passwordController,
                label: context.l10n.password,
                hint: context.l10n.passwordHint,
                icon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _handleLogin(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: AppColors.inkFaint,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return context.l10n.passwordRequired;
                  return null;
                },
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: AuthLinkButton(text: context.l10n.forgotPassword, onPressed: _handleForgotPassword),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 6),
                AuthErrorBanner(message: _errorMessage!),
              ],
              const SizedBox(height: 22),
              AuthPrimaryButton(
                label: context.l10n.login,
                isLoading: _isLoading,
                onPressed: _isLoading ? null : _handleLogin,
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    context.l10n.noAccountYet,
                    style: TextStyle(color: AppColors.inkMuted, fontSize: 13.5),
                  ),
                  AuthLinkButton(
                    text: context.l10n.signUp,
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