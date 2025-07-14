import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../config/api_config.dart';
import 'package:flutter/foundation.dart';

enum AccountType { parent, child }

class UserData {
  final String uid;
  final String email;
  final String? displayName;
  final AccountType accountType;
  final String? parentUid; // Only for child accounts
  final String? username; // For child accounts
  final String? pin; // For child accounts
  final int? age; // For child accounts
  final String? avatarUrl; // Optional avatar image URL

  UserData({
    required this.uid,
    required this.email,
    this.displayName,
    required this.accountType,
    this.parentUid,
    this.username,
    this.pin,
    this.age,
    this.avatarUrl,
  });

  factory UserData.fromFirebaseUser(User user, AccountType type,
      {String? parentUid,
      String? username,
      String? pin,
      int? age,
      String? avatarUrl}) {
    return UserData(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName,
      accountType: type,
      parentUid: parentUid,
      username: username,
      pin: pin,
      age: age,
      avatarUrl: avatarUrl,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'accountType': accountType.toString(),
      'parentUid': parentUid,
      'username': username,
      'pin': pin,
      'age': age,
      'avatarUrl': avatarUrl,
    };
  }

  factory UserData.fromMap(Map<String, dynamic> map) {
    return UserData(
      uid: map['uid'],
      email: map['email'],
      displayName: map['displayName'],
      accountType: map['accountType'] == 'AccountType.parent'
          ? AccountType.parent
          : AccountType.child,
      parentUid: map['parentUid'],
      username: map['username'],
      pin: map['pin'],
      age: map['age'],
      avatarUrl: map['avatarUrl'],
    );
  }
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign in with email and password
  Future<UserData> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      final UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final User? user = result.user;
      if (user == null) {
        throw Exception('User is null after sign in');
      }

      // Get user data from secure storage
      final String? userDataJson = await _storage.read(key: user.uid);
      if (userDataJson == null) {
        // Default to parent account if not found
        final userData = UserData.fromFirebaseUser(user, AccountType.parent);
        await _saveUserData(userData);
        return userData;
      }

      // Wrap all keys and string values in double quotes, making sure to handle null values, special characters and spaces
      final sanitizedJsonWithQuotes = userDataJson.replaceAllMapped(
        RegExp(r'(\w+):\s*([^,}\s][^,}]*)'),
        (match) {
          final key = match.group(1);
          final value = match.group(2);
          if (value == 'null') {
            return '"$key": null';
          } else {
            return '"$key": "$value"';
          }
        },
      );

      // Parse the JSON string to a Map
      final Map<String, dynamic> userData = {
        'uid': user.uid,
        'email': user.email ?? '',
        'displayName': user.displayName,
        'accountType': 'AccountType.parent',
      };
      return UserData.fromMap(userData);
    } catch (e) {
      print('Sign in error: $e');
      throw Exception('Failed to sign in: $e');
    }
  }

  // Register with email and password (parent account)
  Future<UserData> registerParent(
      String email, String password, String displayName) async {
    try {
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? user = result.user;
      if (user == null) {
        throw Exception('User is null after registration');
      }

      // Update display name
      await user.updateDisplayName(displayName);

      // Create user data
      final userData = UserData.fromFirebaseUser(user, AccountType.parent);

      // Save user data
      await _saveUserData(userData);

      return userData;
    } catch (e) {
      throw Exception('Failed to register: $e');
    }
  }

  // Create child account (linked to parent)
  Future<UserData> createChildAccount({
    required String displayName,
    required String parentUid,
    required String username,
    required String pin,
    required int age,
    String? avatarUrl,
  }) async {
    try {
      // Generate a unique email for the child (not visible to users)
      final String childEmail =
          'child_${DateTime.now().millisecondsSinceEpoch}@wonderwords.app';
      final String childPassword =
          'Child${DateTime.now().millisecondsSinceEpoch}';

      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: childEmail,
        password: childPassword,
      );

      final User? user = result.user;
      if (user == null) {
        throw Exception('User is null after child account creation');
      }

      // Update display name
      await user.updateDisplayName(displayName);

      // Create user data
      final userData = UserData.fromFirebaseUser(
        user,
        AccountType.child,
        parentUid: parentUid,
        username: username,
        pin: pin,
        age: age,
        avatarUrl: avatarUrl,
      );

      // Save user data to local storage
      await _saveUserData(userData);

      // Save child account to backend database
      await _saveChildAccountToBackend(
        username: username,
        pin: pin,
        displayName: displayName,
        age: age,
        parentUid: parentUid,
      );

      return userData;
    } catch (e) {
      throw Exception('Failed to create child account: $e');
    }
  }

  // Save child account to backend database
  Future<void> _saveChildAccountToBackend({
    required String username,
    required String pin,
    required String displayName,
    required int age,
    required String parentUid,
  }) async {
    try {
      // Get the parent's ID token
      final String? token = await getIdToken();
      if (token == null) {
        throw Exception('Failed to get authentication token');
      }
      // Call the backend API to authenticate the child
      // Use baseUrl from ApiConfig if running on web, and deviceUrl if running on a device
      const isWeb = kIsWeb;
      const url = isWeb ? ApiConfig.baseUrl : ApiConfig.deviceUrl;
      // Make API call to backend
      final response = await http.post(
        Uri.parse('$url/create_child_account'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'username': username,
          'pin': pin,
          'display_name': displayName,
          'age': age,
          'parent_uid': parentUid,
        }),
      );

      if (response.statusCode != 200) {
        final data = json.decode(response.body);
        throw Exception(
            data['error'] ?? 'Failed to save child account to backend');
      }
    } catch (e) {
      throw Exception('Failed to save child account to backend: $e');
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Save user data to secure storage
  Future<void> _saveUserData(UserData userData) async {
    await _storage.write(
      key: userData.uid,
      value: jsonEncode(userData.toMap()), // Ensure the value is a valid JSON string
    );
  }

  // Get user data from secure storage
  Future<UserData?> getUserData(String uid) async {
    final String? userDataJson = await _storage.read(key: uid);
    if (userDataJson == null) {
      return null;
    }
    // Wrap all keys and string values in double quotes, making sure to handle null values, special characters and spaces
      final sanitizedJsonWithQuotes = userDataJson.replaceAllMapped(
        RegExp(r'(\w+):\s*([^,}\s][^,}]*)'),
        (match) {
          final key = match.group(1);
          final value = match.group(2);
          if (value == 'null') {
            return '"$key": null';
          } else {
            return '"$key": "$value"';
          }
        },
      );

    // Get user from Firebase
    final User? user = _auth.currentUser;
    if (user == null) {
      return null;
    }

    // Parse the JSON string to a Map
    final Map<String, dynamic> userData = {
      'uid': user.uid,
      'email': user.email ?? '',
      'displayName': user.displayName,
      'accountType': 'AccountType.parent',
    };
    return UserData.fromMap(userData);
  }

  // Update user profile
  Future<void> updateProfile(String displayName) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await user.updateDisplayName(displayName);

        // Update stored user data
        final userData = await getUserData(user.uid);
        if (userData != null) {
          final updatedUserData = UserData(
            uid: userData.uid,
            email: userData.email,
            displayName: displayName,
            accountType: userData.accountType,
            parentUid: userData.parentUid,
          );

          await _saveUserData(updatedUserData);
        }
      }
    } catch (e) {
      throw Exception('Failed to update profile: $e');
    }
  }

  // Reset password
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      throw Exception('Failed to send password reset email: $e');
    }
  }

  // Get Firebase ID token
  Future<String?> getIdToken() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        return await user.getIdToken();
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get ID token: $e');
    }
  }
}
