import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:wonder_words_flutter_application/colors.dart';
import '../../models/conversation.dart';
import '../../services/story_service.dart';
import '../../services/auth/auth_provider.dart';
import '../../config/api_config.dart';
import 'story_detail_screen.dart';
import 'package:flutter/foundation.dart';

class StoryHistoryScreen extends StatefulWidget {
  const StoryHistoryScreen({super.key});

  @override
  State<StoryHistoryScreen> createState() => _StoryHistoryScreenState();
}

class _StoryHistoryScreenState extends State<StoryHistoryScreen> {
  late StoryService _storyService;
  bool _isLoading = true;
  List<Conversation> _conversations = [];
  String? _error;
  int _currentPage = 0; // Tracks the current page
  bool _hasMoreBooks = true; // Indicates if there are more books to load
  bool _isLoadingMore = false; // Tracks if the next page is being loaded

  @override
  void initState() {
    super.initState();
    // Initialize StoryService and set the context
    _storyService = StoryService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadConversations();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _storyService.setContext(context);
    // No longer initialize or set context here
    // previously '_storyService' and _loadMessages() were called here
    // it caused a context setting loop and graphical issues in ipad
  }

  Future<void> _loadConversations({bool isLoadMore = false}) async {
    if (isLoadMore) {
      setState(() {
        _isLoadingMore = true;
      });
    } else {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      // Get the AuthProvider to check if the user is a child
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // Load conversations based on account type
      // if the user is a child, and _isLoadingMore is true & _hasMoreBooks is false, do not load more books
      if (authProvider.isChild && _isLoadingMore && !_hasMoreBooks) {
        setState(() {
          _isLoadingMore = false;
        });
        return;
      }
      List<Conversation> conversations;
      if (authProvider.isChild) {
        final assignedStories = await _storyService.getAssignedStories();
        // convert assignedStories to a list of conversation IDs for use with the API
        final assignedStoriesIds =
            assignedStories.map((story) => story.conversationId).toList();
        final childConversations = await _storyService.getConversations(
            page: _currentPage, limit: 20, assignedStories: assignedStoriesIds);
        conversations = childConversations;
        // Check if childConversations is < assignedStoriesIds.length
        if (childConversations.length < assignedStoriesIds.length) {
          setState(() {
            _hasMoreBooks = true; // No more books to load
          });
        } else {
          setState(() {
            _hasMoreBooks = false; // No more books to load
          });
        }
      } else {
        conversations =
            await _storyService.getConversations(page: _currentPage, limit: 20);
      }

      setState(() {
        if (isLoadMore) {
          _conversations.addAll(conversations);
        } else {
          _conversations = conversations;
        }
        // if account is parent, and conversations is empty, set _hasMoreBooks to false
        if (!authProvider.isChild && conversations.isEmpty) {
          _hasMoreBooks = false; // No more books to load
        }
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get the AuthProvider to check if the user is a child
    final authProvider = Provider.of<AuthProvider>(context);
    final isChild = authProvider.isChild;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          isChild ? 'My Stories' : 'Library',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            fontFamily: GoogleFonts.montserrat(
              fontWeight: FontWeight.bold,
            ).fontFamily,
            color: Colors.black,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadConversations,
          ),
        ],
        backgroundColor: ColorTheme.accentYellowColor,
        foregroundColor: Colors.black,
      ),
      body: Container(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ColorTheme.backgroundColor,
            image: const DecorationImage(
              image: AssetImage('assets/bottomFrog.png'),
              fit: BoxFit.cover,
            ),
          ),
          child: _buildBody(),
        ),
      ),
    );
  }

  // Fetch child accounts for the current user
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

      final response = await http.post(
        Uri.parse('$url/get_child_accounts'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'parent_uid': authProvider.userData?.uid,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['child_accounts']);
      } else {
        throw Exception(
            'Failed to fetch child accounts: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching child accounts: $e');
      return [];
    }
  }

  // Show dialog to assign a story to a child
  Future<void> _showAssignStoryDialog(Conversation conversation) async {
    final childAccounts = await _fetchChildAccounts();

    if (childAccounts.isEmpty) {
      if (!mounted) return;

      // Use the root context for the ScaffoldMessenger
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You need to create child accounts first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    String? selectedChildUsername;
    final titleController = TextEditingController();

    // Extract title from the preview if it's in the TITLE: STORY: format
    String suggestedTitle;
    if (conversation.preview.contains("TITLE:") &&
        conversation.preview.contains("STORY:")) {
      final parts = conversation.preview.split("STORY:");
      final titlePart = parts[0].trim();
      suggestedTitle = titlePart.replaceFirst("TITLE:", "").trim();
    } else {
      // Fallback to the old method if the format is not found
      final previewWords = conversation.preview.split(' ');
      suggestedTitle = previewWords.length > 3
          ? '${previewWords.take(3).join(' ')}...'
          : conversation.preview;
    }
    titleController.text = suggestedTitle;

    if (!mounted) return;

    // Pass the root context to the dialog
    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Assign Story to Child'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Story Title:'),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    hintText: 'Enter a title for this story',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Select Child:'),
                const SizedBox(height: 8),
                ...childAccounts.map((account) => RadioListTile<String>(
                      title: Text(account['display_name'] ?? 'Child'),
                      subtitle: Text('Username: ${account['username']}'),
                      value: account['username'],
                      groupValue: selectedChildUsername,
                      onChanged: (value) {
                        setState(() {
                          selectedChildUsername = value;
                        });
                      },
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed:
                  selectedChildUsername == null || titleController.text.isEmpty
                      ? null
                      : () async {
                          Navigator.pop(dialogContext);

                          try {
                            print('Assigning story to $selectedChildUsername');
                            final result = await _storyService.assignStory(
                              conversation.id,
                              selectedChildUsername!,
                              titleController.text,
                            );
                            print('Assign story result: $result');

                            if (!mounted) return;

                            // Use the root context for the ScaffoldMessenger
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Story assigned to ${selectedChildUsername}'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;

                            // Use the root context for the ScaffoldMessenger
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to assign story: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurple),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'Error loading stories',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(_error!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadConversations,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_conversations.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.auto_stories,
                color: Colors.deepPurple,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                'Your Bookshelf',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your stories will appear here as books',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Start a new story to see it here',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        _currentPage = 0; // Reset to the first page
        _hasMoreBooks = true;
        await _loadConversations();
      },
      color: Colors.deepPurple,
      child: Padding(
        padding:
            const EdgeInsets.all(4.0), // Add a small padding around the grid
        child: LayoutBuilder(builder: (context, constraints) {
          // Limit to maximum 8 books per row, minimum 3
          int crossAxisCount = 4;
          if (constraints.maxWidth < 800) {
            crossAxisCount = 6;
          }
          if (constraints.maxWidth < 600) {
            crossAxisCount = 4;
          }
          if (constraints.maxWidth < 400) {
            crossAxisCount = 3;
          }

          return Column(
            children: [
              Expanded(
                child: GridView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount:
                          (constraints.maxWidth / 180).floor().clamp(2, 4),
                      childAspectRatio: 0.6,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: _conversations.length,
                    itemBuilder: (context, index) {
                      final conversation = _conversations[index];
                      return _buildConversationCard(conversation, index);
                    }),
              ),
              if (_hasMoreBooks && !_isLoadingMore)
                ElevatedButton(
                  onPressed: () {
                    _currentPage++;
                    _loadConversations(isLoadMore: true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Load More Books'),
                ),
              if (_isLoadingMore)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildConversationCard(Conversation conversation, int index) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final formattedDate = dateFormat.format(conversation.createdAt);

    final bookColors = [
      ColorTheme.accentBlueColor,
      ColorTheme.darkPurple,
      ColorTheme.primaryColor,
      ColorTheme.secondaryColor,
    ];

    final bookColor = bookColors[index % bookColors.length];
    final preview = conversation.preview.trim();
    final titleMatch =
        RegExp(r'TITLE:\s*(.*?)\s*STORY.*', dotAll: true, caseSensitive: false)
            .firstMatch(preview);
    final title = titleMatch != null ? titleMatch.group(1)!.trim() : preview;

    return Container(
      margin: const EdgeInsets.all(8),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  StoryDetailScreen(conversationId: conversation.id),
            ),
          );
        },
        child: Column(
          children: [
            // Book Cover — full width, flush to sides
            SizedBox(
              height: 260,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: bookColor,
                    gradient: LinearGradient(
                      colors: [bookColor, bookColor.withOpacity(0.8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.montserrat(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                          textAlign:
                              TextAlign.center, // centers lines if multiline
                        ),
                      ]),
                ),
              ),
            ),

            // White "page base"
            SizedBox(
              height: 60,
              child: Material(
                elevation: 5,
                shadowColor: Colors.black.withOpacity(0.15),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                clipBehavior: Clip.antiAlias, // adjust as needed
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment:
                        CrossAxisAlignment.center, // vertical alignment
                    children: [
                      Text(
                        'read story',
                        style: GoogleFonts.montserrat(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: Colors.black54,
                        ),
                      ),
                      const Spacer(),
                      const Image(
                        image: AssetImage('assets/frog.png'),
                        width: 40,
                        height: 40,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Action buttons - more compact and better aligned
            Container(
              width: double.infinity,
              height: 30,
              color: Colors.grey[100],
              child: Consumer<AuthProvider>(
                builder: (context, authProvider, child) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Assign button - only show for parent accounts
                      if (!authProvider.isChild)
                        Expanded(
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _showAssignStoryDialog(conversation),
                            icon: const Icon(Icons.child_care, size: 16),
                            color: Colors.deepPurple,
                            tooltip: 'Assign to Child',
                          ),
                        ),
                      // View button
                      Expanded(
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => StoryDetailScreen(
                                  conversationId: conversation.id,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.visibility, size: 16),
                          color: Colors.deepPurple,
                          tooltip: 'View Story',
                        ),
                      ),
                      // Delete button - only show for parent accounts
                      if (!authProvider.isChild)
                        Expanded(
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () =>
                                _showDeleteConfirmationDialog(conversation),
                            icon: const Icon(Icons.delete, size: 16),
                            color: Colors.red,
                            tooltip: 'Delete Story',
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Show confirmation dialog before deleting a story
  Future<void> _showDeleteConfirmationDialog(Conversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Story'),
        content: const Text(
          'Are you sure you want to delete this story? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        // Show loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );

        // Delete the conversation
        await _storyService.deleteConversation(conversation.id);

        // Close loading dialog
        if (mounted) Navigator.pop(context);

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Story deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }

        // Remove the deleted conversation from the list
        setState(() {
          _conversations.removeWhere((c) => c.id == conversation.id);
        });
      } catch (e) {
        // Close loading dialog
        if (mounted) Navigator.pop(context);

        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete story: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
