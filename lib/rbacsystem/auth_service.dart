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
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    if (!isLoggedIn) return false;

    // SharedPreferences says the session should still be valid, but
    // FirebaseAuth.instance.currentUser is not guaranteed to be populated
    // the instant this runs — its persisted-session restore after
    // Firebase.initializeApp() is asynchronous. Reading currentUser
    // synchronously here used to race that restore: on any cold start that
    // happens to run this check before restoration completes (e.g. Android
    // killing and relaunching the app after a back-button press on a
    // root-level screen), currentUser would still read null even though the
    // user never logged out, and the app would wrongly bounce to the login
    // screen. Waiting for the first authStateChanges() emission gives
    // restoration a chance to finish before we decide.
    if (_auth.currentUser != null) return true;
    final user = await _auth.authStateChanges().first.timeout(
          const Duration(seconds: 5),
          onTimeout: () => _auth.currentUser,
        );
    return user != null;
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
  /// Returns true on success. Never throws — callers can await this for
  /// ordering (so nothing tries to read a rule-gated collection before the
  /// mirror exists) without it ever being able to block sign-in on failure.
  Future<bool> ensureUserRoleMirror({
    required String uid,
    required String username,
    required String role,
  }) async {
    try {
      await _firestore.collection('UserRoles').doc(uid).set({
        'role': role,
        'username': username,
      });
      return true;
    } catch (e) {
      // Most likely cause if this ever fires: firestore.rules' cross-check
      // (Users/{username}.uid == auth.uid && Users/{username}.role == role)
      // failed — e.g. the Users doc is missing a `uid` field, or `uid`
      // doesn't match this Firebase Auth account. Left visible via
      // debugPrint (rather than fully swallowed) since a silent failure
      // here manifests later as a confusing permission-denied on Inventory.
      debugPrint('⚠️ ensureUserRoleMirror failed for uid=$uid username=$username role=$role: $e');
      return false;
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