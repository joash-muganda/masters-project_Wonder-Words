import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wonder_words_flutter_application/colors.dart';
import '../../services/auth/auth_provider.dart';
import '../auth/login_screen.dart';
import 'story_screen.dart';
import 'kid_friendly_story_screen.dart';
import 'profile_screen.dart';
import 'child_accounts_screen.dart';
import 'story_history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final userData = authProvider.userData;

    // If user is not authenticated, redirect to login
    if (userData == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Screens for parent account
    final List<Widget> parentScreens = [
      const StoryScreen(),
      const ChildAccountsScreen(),
      const ProfileScreen(),
    ];

    // Screens for child account
    final List<Widget> childScreens = [
      const KidFriendlyStoryScreen(),
      const StoryHistoryScreen(),
      const ProfileScreen(),
    ];

    // Use appropriate screens based on account type
    final screens = authProvider.isParent ? parentScreens : childScreens;

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        surfaceTintColor: ColorTheme.accentBlueColor,
        indicatorColor: ColorTheme.accentBlueColor,
        indicatorShape: const CircleBorder(),
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        backgroundColor: Colors.white,
        elevation: 8,
        destinations: [
          // Story destination (for both parent and child)
          const NavigationDestination(
            icon: Icon(Icons.book),
            label: 'Create',
          ),

          // Child accounts destination (parent only)
          if (authProvider.isParent)
            const NavigationDestination(
              icon: Icon(Icons.family_restroom),
              label: 'Children',
            ),
          if (authProvider.isChild)
            const NavigationDestination(
              icon: Icon(Icons.bookmark),
              label: 'Library',
            ),

          // Profile destination (for both parent and child)
          const NavigationDestination(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
