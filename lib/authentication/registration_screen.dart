// registration_screen.dart
import 'package:almaworks/authentication/auth_ui.dart';
import 'package:almaworks/authentication/login_screen.dart';
import 'package:almaworks/authentication/welcome_screen.dart';
import 'package:almaworks/rbacsystem/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// ignore: implementation_imports
import 'package:logger/src/logger.dart';
import 'package:almaworks/core/l10n/l10n.dart';
import 'package:almaworks/core/theme/app_colors.dart';
import 'package:almaworks/core/errors/friendly_error.dart';

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
      setState(() => _errorMessage = context.l10n.usernameRequired);
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
        throw UserFacingException(l10nNow.usernameTaken);
      }

      // Create user with email and password
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = userCredential.user;
      if (user == null) {
        throw UserFacingException(l10nNow.couldNotCreateAccount);
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
        showSuccessSnack(context, context.l10n.registrationSuccess);

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => WelcomeScreen(username: username, initialRole: 'Client'),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = e.code == 'email-already-in-use'
            ? l10nNow.emailAlreadyRegistered
            : friendlyError(e, action: l10nNow.couldNotCreateAccount);
      });
    } catch (e) {
      setState(() {
        _errorMessage = e is UserFacingException ? e.message : friendlyError(e, action: l10nNow.couldNotCreateAccount);
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
      brandHeadline: context.l10n.joinHeadline,
      brandSubtext: context.l10n.joinSubtext,
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
                      context.l10n.createAccount,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandInk,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.createAccountSubtitle,
                style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 28),
              AuthTextField(
                controller: _usernameController,
                label: context.l10n.username,
                hint: context.l10n.usernameHint,
                icon: Icons.account_circle_outlined,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return context.l10n.usernameRequired;
                  }
                  if (value.trim().length < 3) {
                    return context.l10n.usernameTooShort;
                  }
                  if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value.trim())) {
                    return context.l10n.usernameInvalidChars;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              AuthTextField(
                controller: _emailController,
                label: context.l10n.email,
                hint: context.l10n.emailHint,
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return context.l10n.emailRequired;
                  }
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
                hint: context.l10n.newPasswordHint,
                icon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _signUp(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: AppColors.inkFaint,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return context.l10n.passwordRequired;
                  }
                  if (value.length < 6) {
                    return context.l10n.passwordTooShort;
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
                label: context.l10n.signUp,
                isLoading: _isLoading,
                onPressed: _isLoading ? null : _signUp,
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    context.l10n.alreadyHaveAccount,
                    style: TextStyle(color: AppColors.inkMuted, fontSize: 13.5),
                  ),
                  AuthLinkButton(
                    text: context.l10n.signIn,
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
              color: AppColors.brandTint,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.arrow_back_rounded, size: 19, color: AppColors.brandInk, semanticLabel: context.l10n.back),
          ),
        ),
      ),
    );
  }
}