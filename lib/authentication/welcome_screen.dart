// welcome_screen.dart
import 'package:almaworks/authentication/login_screen.dart';
import 'package:almaworks/rbacsystem/auth_service.dart';
import 'package:almaworks/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'dart:async';

class WelcomeScreen extends StatefulWidget {
  final String username;
  final String initialRole;

  const WelcomeScreen({super.key, required this.username, required this.initialRole});

  @override
  WelcomeScreenState createState() => WelcomeScreenState();
}

class WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  String _currentRole = '';
  StreamSubscription<DocumentSnapshot>? _roleSubscription;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _currentRole = widget.initialRole;
    _setupRoleListener();
    _setupAnimations();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));

    _animationController.forward();
  }

  void _setupRoleListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
      return;
    }

    _roleSubscription = FirebaseFirestore.instance
        .collection('Users')
        .doc(widget.username)
        .snapshots()
        .listen(
      (snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data();
          final newRole = data?['role'] as String? ?? 'Client';
          if (newRole != _currentRole) {
            setState(() {
              _currentRole = newRole;
            });
            // ignore: use_build_context_synchronously
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Your role has been updated to $newRole'),
                backgroundColor: const Color(0xFF0A2E5A),
              ),
            );
          }
        } else {
          setState(() {
            _currentRole = 'Client';
          });
        }
      },
      onError: (error) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $error')),
        );
      },
    );
  }

  void _navigateToDashboard() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => DashboardScreen(logger: Logger()),
      ),
    );
  }

  @override
  void dispose() {
    _roleSubscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              // Extra bottom padding keeps content clear of the floating
              // "Continue to Dashboard" button pinned via the Scaffold.
              padding: EdgeInsets.fromLTRB(
                isMobile ? 16.0 : 24.0,
                isMobile ? 16.0 : 24.0,
                isMobile ? 16.0 : 24.0,
                isMobile ? 96.0 : 108.0,
              ),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  _buildHeader(isMobile),
                  const SizedBox(height: 40),
                  _buildFeatureCards(isMobile),
                  const SizedBox(height: 24),
                  _buildLogoutButton(),
                ],
              ),
            ),
          ),
        ),
      ),
      // Floating rather than at the bottom of the scroll content, so it's
      // always reachable without scrolling on shorter screens.
      floatingActionButton: _buildContinueButton(isMobile),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 20 : 30),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A2E5A), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A2E5A).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: isMobile ? 60 : 80,
            color: Colors.white,
          ),
          const SizedBox(height: 16),
          Text(
            'Welcome, ${widget.username}!',
            style: TextStyle(
              fontSize: isMobile ? 24 : 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Role: $_currentRole',
              style: TextStyle(
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCards(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'AlmaWorks Site Management',
            style: TextStyle(
              fontSize: isMobile ? 20 : 24,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF0A2E5A),
            ),
          ),
        ),
        _buildFeatureCard(
          icon: Icons.engineering,
          title: 'Project Management',
          description: 'Organize and track construction projects from start to finish',
          isMobile: isMobile,
        ),
        const SizedBox(height: 12),
        _buildFeatureCard(
          icon: Icons.groups,
          title: 'Team Collaboration',
          description: 'Coordinate with team members and manage tasks efficiently',
          isMobile: isMobile,
        ),
        const SizedBox(height: 12),
        _buildFeatureCard(
          icon: Icons.analytics,
          title: 'Real-time Insights',
          description: 'Monitor progress with live updates and comprehensive analytics',
          isMobile: isMobile,
        ),
        const SizedBox(height: 12),
        _buildFeatureCard(
          icon: Icons.location_on,
          title: 'Site Tracking',
          description: 'Manage multiple construction sites with location-based tools',
          isMobile: isMobile,
        ),
      ],
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    required bool isMobile,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: Container(
        padding: EdgeInsets.all(isMobile ? 16 : 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF0A2E5A).withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A2E5A).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: const Color(0xFF0A2E5A),
                size: isMobile ? 28 : 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: isMobile ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0A2E5A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: isMobile ? 13 : 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueButton(bool isMobile) {
    return FloatingActionButton.extended(
      onPressed: _navigateToDashboard,
      backgroundColor: const Color(0xFF0A2E5A),
      foregroundColor: Colors.white,
      elevation: 4,
      extendedPadding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      label: Text(
        'Continue to Dashboard',
        style: TextStyle(
          fontSize: isMobile ? 15 : 17,
          fontWeight: FontWeight.bold,
        ),
      ),
      icon: const Icon(Icons.arrow_forward, size: 20),
    );
  }

  Widget _buildLogoutButton() {
    return TextButton.icon(
      onPressed: () async {
        await _authService.logout();
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );
        }
      },
      icon: const Icon(Icons.logout, color: Color(0xFF0A2E5A)),
      label: const Text(
        'Logout',
        style: TextStyle(
          color: Color(0xFF0A2E5A),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}