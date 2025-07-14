import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wonder_words_flutter_application/colors.dart';
import '../../services/auth/auth_provider.dart';
import 'register_screen.dart';
import 'reset_password_screen.dart';
import '../home/home_screen.dart';
import 'package:google_fonts/google_fonts.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_formKey.currentState?.validate() ?? false) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      if (email.isEmpty || password.isEmpty) {
        // Handle the case where email or password is empty
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Email and password cannot be empty')),
        );
        return;
      }

      final success = await authProvider.signIn(email, password);

      if (success && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      body: Container(
        color: ColorTheme.backgroundColor,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App Logo
                  const Image(
                    image: AssetImage('assets/frog.png'),
                    width: 225, // Set the desired width
                    height: 225, // Set the desired height
                  ),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'W',
                          style: TextStyle(
                            fontSize: 32,
                            color: ColorTheme.textColor,
                            fontFamily: GoogleFonts.montserrat(
                              fontWeight: FontWeight.bold,
                            ).fontFamily,
                          ),
                        ),
                        TextSpan(
                          text: 'o',
                          style: TextStyle(
                            fontSize: 32,
                            color: ColorTheme
                                .primaryColor, // Change this to your desired color
                            fontFamily: GoogleFonts.montserrat(
                              fontWeight: FontWeight.bold,
                            ).fontFamily,
                          ),
                        ),
                        TextSpan(
                          text: 'nd',
                          style: TextStyle(
                            fontSize: 32,
                            color: ColorTheme.textColor,
                            fontFamily: GoogleFonts.montserrat(
                              fontWeight: FontWeight.bold,
                            ).fontFamily,
                          ),
                        ),
                        TextSpan(
                          text: 'e',
                          style: TextStyle(
                            fontSize: 32,
                            color: ColorTheme.accentBlueColor,
                            fontFamily: GoogleFonts.montserrat(
                              fontWeight: FontWeight.bold,
                            ).fontFamily,
                          ),
                        ),
                        TextSpan(
                          text: 'rW',
                          style: TextStyle(
                            fontSize: 32,
                            color: ColorTheme.textColor,
                            fontFamily: GoogleFonts.montserrat(
                              fontWeight: FontWeight.bold,
                            ).fontFamily,
                          ),
                        ),
                        TextSpan(
                          text: 'o',
                          style: TextStyle(
                            fontSize: 32,
                            color: ColorTheme
                                .secondaryColor, // Change this to your desired color
                            fontFamily: GoogleFonts.montserrat(
                              fontWeight: FontWeight.bold,
                            ).fontFamily,
                          ),
                        ),
                        TextSpan(
                          text: 'rds',
                          style: TextStyle(
                            fontSize: 32,
                            color: ColorTheme.textColor,
                            fontFamily: GoogleFonts.montserrat(
                              fontWeight: FontWeight.bold,
                            ).fontFamily,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create your own stories',
                    style: TextStyle(
                      fontSize: 16,
                      color: ColorTheme.textColor,
                      fontFamily: GoogleFonts.montserrat().fontFamily,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Login Form
                  Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    color: ColorTheme.accentYellowColor,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Let\'s Read',
                              style: TextStyle(
                                fontSize: 24,
                                fontFamily: GoogleFonts.montserrat(
                                  fontWeight: FontWeight.bold,
                                ).fontFamily,
                                color: ColorTheme.secondaryColor,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              'Login to your account',
                              style: TextStyle(
                                fontSize: 14,
                                fontFamily: GoogleFonts.montserrat().fontFamily,
                                color: ColorTheme.textColor,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),

                            // Email Field
                            TextFormField(
                              controller: _emailController,
                              decoration: InputDecoration(
                                labelText: 'Email',
                                prefixIcon: const Icon(Icons.email),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                fillColor: Colors.white,
                                filled: true,
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your email';
                                }
                                if (!value.contains('@')) {
                                  return 'Please enter a valid email';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // Password Field
                            TextFormField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                fillColor: Colors.white,
                                filled: true,
                              ),
                              obscureText: _obscurePassword,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your password';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 8),

                            // Forgot Password Link
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const ResetPasswordScreen(),
                                    ),
                                  );
                                },
                                child: Text(
                                  'Forgot Password?',
                                  style: TextStyle(
                                      color: ColorTheme.secondaryColor),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Login Button
                            ElevatedButton(
                              onPressed: authProvider.isLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: ColorTheme.secondaryColor,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: authProvider.isLoading
                                  ? const CircularProgressIndicator(
                                      color: Colors.white,
                                    )
                                  : Text('Login',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontFamily: GoogleFonts.montserrat(
                                                fontWeight: FontWeight.bold)
                                            .fontFamily,
                                      )),
                            ),

                            // Error Message
                            if (authProvider.error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Text(
                                  authProvider.error!,
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
                  ),
                  const SizedBox(height: 24),

                  // Register Link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account?"),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RegisterScreen(),
                            ),
                          );
                        },
                        child: Text('Register',
                            style: TextStyle(color: ColorTheme.secondaryColor)),
                      ),
                    ],
                  ),

                  // Child Login Button - More kid-friendly design
                  Padding(
                    padding: const EdgeInsets.only(top: 24.0),
                    child: Container(
                      height: 60,
                      width: 220,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        gradient: LinearGradient(
                          colors: [
                            ColorTheme.pink,
                            ColorTheme.secondaryColor,
                            ColorTheme.accentBlueColor,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            spreadRadius: 1,
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/child-login');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.child_care,
                              size: 28,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Kids Zone',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
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
