import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:wonder_words_flutter_application/colors.dart';
import 'dart:convert';
import '../../services/auth/auth_provider.dart';
import '../../services/auth/auth_service.dart';
// load the ApiConfig class to access deviceiP
import '../../config/api_config.dart';
// loading the kIsWeb to check if on web
import 'package:flutter/foundation.dart' show kIsWeb;

class ChildLoginScreen extends StatefulWidget {
  const ChildLoginScreen({Key? key}) : super(key: key);

  @override
  State<ChildLoginScreen> createState() => _ChildLoginScreenState();
}

class _ChildLoginScreenState extends State<ChildLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _pinController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      try {
        // Print debug information
        print('Attempting child login with:');
        print('Username: ${_usernameController.text.trim()}');
        print('PIN: ${_pinController.text.trim()}');
        // Resolve the device IP from ApiConfig depending on if web environment or device

        const resolvedUrl = kIsWeb ? ApiConfig.baseUrl : ApiConfig.deviceUrl;

        // Call the backend API to authenticate the child
        final response = await http.post(
          Uri.parse('$resolvedUrl/child_login'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'username': _usernameController.text.trim(),
            'pin': _pinController.text.trim(),
          }),
        );

        // Print response for debugging
        print('Response status code: ${response.statusCode}');
        print('Response body: ${response.body}');

        if (response.statusCode == 200) {
          // Parse the response
          final data = json.decode(response.body);
          final token = data['token'];
          final displayName = data['display_name'];
          final age = data['age'];

          // Update the AuthProvider with the child's authentication information
          final authProvider =
              Provider.of<AuthProvider>(context, listen: false);

          // Create a child user data object
          final childUserData = UserData(
            uid:
                'child-${DateTime.now().millisecondsSinceEpoch}', // Generate a temporary UID
            email: 'child@example.com', // Placeholder email
            displayName: displayName,
            accountType: AccountType.child,
            username: _usernameController.text.trim(),
            pin: _pinController.text.trim(),
            age: age,
          );

          // Set the user data in the AuthProvider
          authProvider.setChildUserData(childUserData, token);

          if (mounted) {
            // Navigate to the home screen
            Navigator.of(context).pushReplacementNamed('/home');
          }
        } else {
          // Handle authentication error
          final data = json.decode(response.body);
          setState(() {
            _error = data['error'] ?? 'Authentication failed';
            _isLoading = false;
          });
        }
      } catch (e) {
        setState(() {
          _error = 'Connection error: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: ColorTheme.backgroundColor,
          image: const DecorationImage(
            image: AssetImage('assets/megafrog.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Login Card - More child-friendly design
                  Container(
                    padding: const EdgeInsets.all(24.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Fun header for kids
                          const SizedBox(height: 100),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Hi there! I\'m',
                                style: TextStyle(
                                  fontSize: 32,
                                  color: ColorTheme.textColor,
                                  fontFamily: GoogleFonts.montserrat(
                                    fontWeight: FontWeight.bold,
                                  ).fontFamily,
                                ),
                              ),
                              Text(
                                ' Hopper',
                                style: TextStyle(
                                  fontSize: 32,
                                  color: ColorTheme.accentYellowColor,
                                  fontFamily: GoogleFonts.montserrat(
                                    fontWeight: FontWeight.bold,
                                  ).fontFamily,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'What\'s your name?',
                            style: TextStyle(
                              fontSize: 25,
                              color: ColorTheme.accentYellowColor,
                              fontFamily: GoogleFonts.montserrat(
                                      fontWeight: FontWeight.bold)
                                  .fontFamily,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),

                          // Username Field - Matching the PIN field style
                          TextFormField(
                            controller: _usernameController,
                            decoration: InputDecoration(
                              labelText: 'Username',
                              labelStyle: TextStyle(
                                fontSize: 16,
                                color: ColorTheme.textColor,
                                fontFamily: GoogleFonts.montserrat().fontFamily,
                              ),
                              prefixIcon: Icon(
                                Icons.person,
                                color: ColorTheme.pink,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 16,
                              ),
                            ),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            textCapitalization: TextCapitalization.words,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your username';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // PIN Field - More kid-friendly design
                          TextFormField(
                            controller: _pinController,
                            decoration: InputDecoration(
                              labelText: 'Secret PIN',
                              labelStyle: TextStyle(
                                fontSize: 16,
                                color: ColorTheme.textColor,
                                fontFamily: GoogleFonts.montserrat().fontFamily,
                              ),
                              prefixIcon: Icon(
                                Icons.lock_outline,
                                color: ColorTheme.orange,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 16,
                              ),
                            ),
                            style: const TextStyle(
                              fontSize: 18,
                              letterSpacing: 8,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                            obscureText: true,
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your secret PIN';
                              }
                              if (value.length != 4 ||
                                  int.tryParse(value) == null) {
                                return 'PIN must be exactly 4 digits';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),

                          // Login Button - More child-friendly design
                          Container(
                            height: 60,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(30),
                              color: ColorTheme.accentBlueColor,
                            ),
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: ColorTheme.darkPurple,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'let\'s read',
                                          style: TextStyle(
                                            fontSize: 25,
                                            color: ColorTheme.darkPurple,
                                            fontFamily: GoogleFonts.montserrat(
                                                    fontWeight: FontWeight.bold)
                                                .fontFamily,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),

                          // Error Message
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Parent Login Link
                  Padding(
                    padding: const EdgeInsets.only(top: 24.0),
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacementNamed('/login');
                      },
                      child: const Text(
                        'Parent Login',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
