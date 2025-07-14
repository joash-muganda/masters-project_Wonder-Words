import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:wonder_words_flutter_application/colors.dart';
import 'dart:convert';
import '../../services/auth/auth_provider.dart';
import '../../services/auth/auth_service.dart';
import '../../config/api_config.dart';
import 'kid_friendly_story_screen.dart';
// kisweb
import 'package:flutter/foundation.dart';

class ChildAccountsScreen extends StatefulWidget {
  const ChildAccountsScreen({Key? key}) : super(key: key);

  @override
  State<ChildAccountsScreen> createState() => _ChildAccountsScreenState();
}

class _ChildAccountsScreenState extends State<ChildAccountsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _pinController = TextEditingController();
  final _ageController = TextEditingController();
  bool _isCreating = false;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _pinController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _createChildAccount() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      try {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);

        // Parse age to integer
        int? age;
        if (_ageController.text.isNotEmpty) {
          age = int.tryParse(_ageController.text.trim());
        }

        final success = await authProvider.createChildAccount(
          _nameController.text.trim(),
          username: _usernameController.text.trim(),
          pin: _pinController.text.trim(),
          age: age ?? 8, // Default to 8 if parsing fails
        );

        if (success && mounted) {
          setState(() {
            _isCreating = false;
            _nameController.clear();
            _usernameController.clear();
            _pinController.clear();
            _ageController.clear();
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Child account created successfully'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (mounted) {
          setState(() {
            _error = authProvider.error ?? 'Failed to create child account';
          });
        }
      } catch (e) {
        setState(() {
          _error = e.toString();
        });
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  // Navigate to the child's story screen
  void _navigateToChildStoryScreen(Map<String, dynamic> childAccount) async {
    try {
      // Get the child's username and PIN
      final username = childAccount['username'];
      final pin =
          childAccount['pin'] ?? '1234'; // Use actual PIN or default to 1234

      setState(() {
        _isLoading = true;
      });

      // Call the backend API to authenticate the child
      // Use baseUrl from ApiConfig if running on web, and deviceUrl if running on a device
      const isWeb = kIsWeb;
      const url = isWeb ? ApiConfig.baseUrl : ApiConfig.deviceUrl;

      final response = await http.post(
        Uri.parse('$url/child_login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'pin': pin,
        }),
      );

      setState(() {
        _isLoading = false;
      });

      if (response.statusCode == 200) {
        // Parse the response
        final data = json.decode(response.body);
        final token = data['token'];
        final displayName = data['display_name'];
        final age = data['age'];

        // Update the AuthProvider with the child's authentication information
        final authProvider = Provider.of<AuthProvider>(context, listen: false);

        // Create a child user data object
        final childUserData = UserData(
          uid:
              'child-${DateTime.now().millisecondsSinceEpoch}', // Generate a temporary UID
          email: 'child@example.com', // Placeholder email
          displayName: displayName,
          accountType: AccountType.child,
          username: username,
          pin: pin,
          age: age,
        );

        // Set the user data in the AuthProvider
        authProvider.setChildUserData(childUserData, token);

        if (mounted) {
          // Navigate to the KidFriendlyStoryScreen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const KidFriendlyStoryScreen(),
            ),
          );
        }
      } else {
        // Handle authentication error
        final data = json.decode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['error'] ?? 'Failed to login as child'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    // Only parent accounts should access this screen
    if (!authProvider.isParent) {
      return const Center(
        child: Text('Only parent accounts can manage child accounts'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Child Accounts',
          style: TextStyle(
              fontFamily: GoogleFonts.montserrat(fontWeight: FontWeight.bold)
                  .fontFamily),
        ),
        backgroundColor: ColorTheme.accentYellowColor,
        foregroundColor: Colors.black,
      ),
      body: Container(
        decoration: BoxDecoration(
          color: ColorTheme.backgroundColor,
        ),
        child: Column(
          children: [
            // Child Accounts List
            Expanded(
              child: _buildChildAccountsList(),
            ),

            // Create Child Account Form
            if (_isCreating)
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Create Child Account',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Child Name Field
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Child\'s Name',
                          prefixIcon: const Icon(Icons.child_care),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a name for the child';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Username Field
                      TextFormField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          labelText: 'Username',
                          prefixIcon: const Icon(Icons.person),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a username for the child';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // PIN Field
                      TextFormField(
                        controller: _pinController,
                        decoration: InputDecoration(
                          labelText: 'PIN (4 digits)',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a PIN';
                          }
                          if (value.length != 4 ||
                              int.tryParse(value) == null) {
                            return 'PIN must be exactly 4 digits';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Age Field
                      TextFormField(
                        controller: _ageController,
                        decoration: InputDecoration(
                          labelText: 'Age',
                          prefixIcon: const Icon(Icons.cake),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter the child\'s age';
                          }
                          final age = int.tryParse(value);
                          if (age == null || age < 1 || age > 17) {
                            return 'Please enter a valid age (1-17)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Action Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    setState(() {
                                      _isCreating = false;
                                      _nameController.clear();
                                      _error = null;
                                    });
                                  },
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            onPressed: _isLoading ? null : _createChildAccount,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: ColorTheme.accentBlueColor,
                              foregroundColor: ColorTheme.darkPurple,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Create Account'),
                          ),
                        ],
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
          ],
        ),
      ),
      floatingActionButton: !_isCreating
          ? FloatingActionButton(
              heroTag: 'createChildAccount',
              onPressed: () {
                setState(() {
                  _isCreating = true;
                });
              },
              backgroundColor: ColorTheme.accentBlueColor,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchChildAccounts() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = await authProvider.getIdToken();

      if (token == null) {
        throw Exception('Failed to get authentication token');
      }

      // Call the backend API to authenticate the child
      // Use baseUrl from ApiConfig if running on web, and deviceUrl if running on a device
      const isWeb = kIsWeb;
      const url = isWeb ? ApiConfig.baseUrl : ApiConfig.deviceUrl;
      // use the parentID to get the child accounts
      final parentId = authProvider.userData?.uid;
      final response = await http.post(
        Uri.parse('$url/get_child_accounts'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'parent_uid': parentId,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final accounts =
            List<Map<String, dynamic>>.from(data['child_accounts']);
        print('Child accounts fetched: ${accounts.length}');
        print('Child accounts data: $accounts');
        return accounts;
      } else {
        throw Exception(
            'Failed to fetch child accounts: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
      return [];
    }
  }

  Widget _buildChildAccountsList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchChildAccounts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {});
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final childAccounts = snapshot.data ?? [];

        if (childAccounts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Image(
                  image: AssetImage('assets/frog.png'),
                  width: 200, // Set the desired width
                  height: 200, // Set the desired height
                ),
                const SizedBox(height: 5),
                Text(
                  'Child Accounts',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: ColorTheme.darkPurple,
                    fontFamily: GoogleFonts.montserrat(
                      fontWeight: FontWeight.bold,
                    ).fontFamily,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Create child accounts to let your children enjoy personalized stories.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'No child accounts yet',
                  style: TextStyle(
                    fontSize: 18,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 5),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isCreating = true;
                    });
                  },
                  icon: Icon(
                    Icons.add,
                    color: ColorTheme.darkPurple,
                  ),
                  label: Text(
                    'Create Child Account',
                    style: TextStyle(
                      fontFamily: GoogleFonts.montserrat().fontFamily,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ColorTheme.accentBlueColor,
                    foregroundColor: ColorTheme.darkPurple,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: childAccounts.length,
          itemBuilder: (context, index) {
            final account = childAccounts[index];
            return Card(
              color: Colors.white,
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: InkWell(
                onTap: () => _navigateToChildStoryScreen(account),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: ColorTheme.orange,
                    radius: 24,
                    child: const Image(
                      image: AssetImage('assets/frog.png'),
                      width: 40, // Set the desired width
                      height: 40, // Set the desired height
                    ),
                  ),
                  title: Text(
                    account['display_name'] ?? 'Child',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      fontFamily:
                          GoogleFonts.montserrat(fontWeight: FontWeight.bold)
                              .fontFamily,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text('Username: ${account['username']}'),
                      Text('Age: ${account['age']}'),
                    ],
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios,
                    color: ColorTheme.accentBlueColor,
                    size: 16,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
