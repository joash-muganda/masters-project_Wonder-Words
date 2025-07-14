import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  UserData? _userData;
  bool _isLoading = false;
  String? _error;

  // Getters
  UserData? get userData => _userData;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _userData != null;
  String? get error => _error;
  bool get isParent => _userData?.accountType == AccountType.parent;
  bool get isChild => _userData?.accountType == AccountType.child;

  // Initialize auth state
  Future<void> initializeAuth() async {
    try {
      // Check if user is already signed in
      final User? currentUser = _authService.currentUser;
      if (currentUser != null) {
        final userData = await _authService.getUserData(currentUser.uid);
        _userData = userData;
      }
    } catch (e) {
      _error = e.toString();
    }
  }

  // Sign in with email and password
  Future<bool> signIn(String email, String password) async {
    _setLoading(true);
    _clearError();

    try {
      final userData =
          await _authService.signInWithEmailAndPassword(email, password);     
      _userData = userData;
      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Register parent account
  Future<bool> registerParent(
      String email, String password, String displayName) async {
    _setLoading(true);
    _clearError();

    try {
      final userData =
          await _authService.registerParent(email, password, displayName);
      _userData = userData;
      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Create child account
  Future<bool> createChildAccount(String displayName,
      {String? username, String? pin, int? age}) async {
    if (_userData == null || _userData!.accountType != AccountType.parent) {
      _setError('Only parent accounts can create child accounts');
      return false;
    }

    _setLoading(true);
    _clearError();

    try {
      await _authService.createChildAccount(
        displayName: displayName,
        parentUid: _userData!.uid,
        username: username ?? 'child_${DateTime.now().millisecondsSinceEpoch}',
        pin: pin ?? '1234', // Default PIN
        age: age ?? 8, // Default age
      );
      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Sign out
  Future<void> signOut() async {
    _setLoading(true);
    _clearError();

    try {
      await _authService.signOut();
      _userData = null;
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  // Update profile
  Future<bool> updateProfile(String displayName) async {
    if (_userData == null) {
      _setError('User not authenticated');
      return false;
    }

    _setLoading(true);
    _clearError();

    try {
      await _authService.updateProfile(displayName);

      // Update local user data
      _userData = UserData(
        uid: _userData!.uid,
        email: _userData!.email,
        displayName: displayName,
        accountType: _userData!.accountType,
        parentUid: _userData!.parentUid,
      );

      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Reset password
  Future<bool> resetPassword(String email) async {
    _setLoading(true);
    _clearError();

    try {
      await _authService.resetPassword(email);
      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Get Firebase ID token
  Future<String?> getIdToken() async {
    try {
      return await _authService.getIdToken();
    } catch (e) {
      _setError(e.toString());
      return null;
    }
  }

  // Set child user data (used for child login)
  void setChildUserData(UserData childUserData, String token) {
    _userData = childUserData;
    _childToken = token; // Store the child token
    notifyListeners();
  }

  // Child token
  String? _childToken;

  // Get the child token
  String? get childToken => _childToken;

  // Helper methods
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String error) {
    _error = error;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    notifyListeners();
  }
}
