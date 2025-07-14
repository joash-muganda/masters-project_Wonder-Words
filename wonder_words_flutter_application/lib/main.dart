import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'services/auth/auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/child_login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/home/child_accounts_screen.dart';
import 'screens/auth/account_selection_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show kIsWeb;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // load env
  // Construct the path to the .env file depending on the platform
  if (!kIsWeb) {
    // method for mobile
    String fileName = 'assets/.env';
    final envString = await rootBundle.loadString(fileName);
    dotenv.testLoad(
      mergeWith: Map<String, String>.fromEntries(
        envString.split('\n').where((line) => line.contains('=')).map(
              (line) {
                final parts = line.split('=');
                return MapEntry(parts[0].trim(), parts.sublist(1).join('=').trim());
              },
            ),
      ),
    );
  } else {
    // method for web
    await dotenv.load(fileName: ".env");
  }
  //verify that the env was loaded properly
  if (dotenv.env['GOOGLE_CLOUD_API_KEY'] == null) {
    print('Environment variables not loaded properly');
  }
  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    print('Failed to initialize Firebase: $e');
    // Continue without Firebase for developmentr
  }

  runApp(
    ChangeNotifierProvider(
      create: (context) => AuthProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wonder Words',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/child-login': (context) => const ChildLoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/child-accounts': (context) => const ChildAccountsScreen(),
        '/account-selection': (context) => const AccountSelectionScreen(),
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.initializeAuth();

    if (mounted) {
      setState(() {
        _initializing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        if (authProvider.isAuthenticated) {
          if (authProvider.isParent) {
            return const AccountSelectionScreen();
          } else {
            return const HomeScreen();
          }
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}
