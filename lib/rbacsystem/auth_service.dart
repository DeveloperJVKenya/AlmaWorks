// services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Check if user is logged in
  Future<bool> isUserLoggedIn() async {
    final user = _auth.currentUser;
    if (user != null) {
      // Check SharedPreferences for persistent login
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
      return isLoggedIn;
    }
    return false;
  }

  // Set login state
  Future<void> setLoginState(bool isLoggedIn) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', isLoggedIn);
  }

  // Get current user role
  Future<String> getUserRole() async {
    final user = _auth.currentUser;
    if (user == null) return 'Client';

    try {
      final querySnapshot = await _firestore
          .collection('Users')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final userData = querySnapshot.docs.first.data();
        return userData['role'] as String? ?? 'Client';
      }
    } catch (e) {
      debugPrint('Error getting user role: $e');
    }
    return 'Client';
  }

  // Get current username
  Future<String> getUsername() async {
    final user = _auth.currentUser;
    if (user == null) return '';

    try {
      final querySnapshot = await _firestore
          .collection('Users')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return querySnapshot.docs.first.id; // Document ID is the username
      }
    } catch (e) {
      debugPrint('Error getting username: $e');
    }
    return '';
  }

  // Get user data
  Future<Map<String, dynamic>?> getUserData() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final querySnapshot = await _firestore
          .collection('Users')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final data = querySnapshot.docs.first.data();
        data['username'] = querySnapshot.docs.first.id;
        return data;
      }
    } catch (e) {
      debugPrint('Error getting user data: $e');
    }
    return null;
  }

  // Mirror this user's uid -> role into UserRoles so Firestore security
  // rules (which can only get() a doc by known path, not query) can resolve
  // a caller's role for the Inventory module. Safe and idempotent to call on
  // every login/registration: firestore.rules only accepts this write if
  // [role]/[username] exactly match the caller's own Users doc, so it can
  // never grant a role the account doesn't already have. Failures are
  // swallowed — this is a best-effort background sync, never something that
  // should block sign-in.
  Future<void> ensureUserRoleMirror({
    required String uid,
    required String username,
    required String role,
  }) async {
    try {
      await _firestore.collection('UserRoles').doc(uid).set({
        'role': role,
        'username': username,
      });
    } catch (e) {
      debugPrint('Error syncing UserRoles mirror: $e');
    }
  }

  // Logout
  Future<void> logout() async {
    await setLoginState(false);
    await _auth.signOut();
  }

  // Get current user
  User? get currentUser => _auth.currentUser;
}