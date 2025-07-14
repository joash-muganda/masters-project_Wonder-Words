import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth/auth_provider.dart';
import '../../services/auth/auth_service.dart';
import '../home/home_screen.dart';
import '../home/kid_friendly_story_screen.dart';
import 'dart:convert';
import '../../config/api_config.dart';
// kisweb
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;


class AccountSelectionScreen extends StatefulWidget {
  const AccountSelectionScreen({Key? key}) : super(key: key);

  @override
  State<AccountSelectionScreen> createState() => _AccountSelectionScreenState();
}

class _AccountSelectionScreenState extends State<AccountSelectionScreen> {
  bool _isLoading = false;
  String? _error;
  var _childAccounts = [];

  @override
  void initState() {
    super.initState();
    _loadChildAccounts();
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

  Future<void> _loadChildAccounts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Simulate network delay
      await Future.delayed(const Duration(milliseconds: 500));

      // Fetch child accounts outside of setState
      final fetchedAccounts = await _fetchChildAccounts();

      if (mounted) {
        setState(() {
          _childAccounts = fetchedAccounts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _continueAsParent() async {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final userData = authProvider.userData;

    if (userData == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Account'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.purple[50]!,
              Colors.purple[100]!,
            ],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Error loading accounts',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(_error!),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadChildAccounts,
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  )
                : _buildAccountSelection(userData),
      ),
    );
  }

  Widget _buildAccountSelection(UserData parentAccount) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Parent Account Card
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: InkWell(
              onTap: _continueAsParent,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.deepPurple,
                          child: Text(
                            parentAccount.displayName?.isNotEmpty == true
                                ? parentAccount.displayName![0].toUpperCase()
                                : 'P',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                parentAccount.displayName ?? 'Parent',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Text(
                                'Parent Account',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.deepPurple,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Child Accounts Section
          const Text(
            'Child Accounts',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // Child Accounts List with FutureBuilder
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _fetchChildAccounts(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Text(
                      'No child accounts yet',
                      style: TextStyle(
                        fontSize: 16,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey,
                      ),
                    ),
                  );
                } else {
                  final childAccounts = snapshot.data!;
                  return ListView.builder(
                    itemCount: childAccounts.length,
                    itemBuilder: (context, index) {
                      final childAccount = childAccounts[index];
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.symmetric(vertical: 8.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          onTap: () => _navigateToChildStoryScreen(childAccount),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: Colors.orange,
                                  child: Text(
                                    childAccount['display_name']?.isNotEmpty == true
                                        ? childAccount['display_name'][0]
                                            .toUpperCase()
                                        : 'C',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        childAccount['display_name'] ?? 'Child',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        'Age: ${childAccount['age'] ?? 'Unknown'}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward_ios,
                                  color: Colors.orange,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }
              },
            ),
          ),

          // Create Child Account Button
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: ElevatedButton.icon(
              onPressed: () {
                // Navigate to child accounts screen
                Navigator.of(context).pushNamed('/child-accounts');
              },
              icon: const Icon(Icons.add),
              label: const Text('Create Child Account'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
