import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:wonder_words_flutter_application/colors.dart';
import '../../services/auth/auth_provider.dart';
import '../../services/story_service.dart';
import '../../services/tts/google_tts_service.dart';
import '../../models/assigned_story.dart';
import '../../models/conversation.dart';
import 'story_history_screen.dart';
import 'kid_friendly_methods.dart';

class KidFriendlyStoryScreen extends StatefulWidget {
  const KidFriendlyStoryScreen({Key? key}) : super(key: key);

  @override
  State<KidFriendlyStoryScreen> createState() => _KidFriendlyStoryScreenState();
}

class _KidFriendlyStoryScreenState extends State<KidFriendlyStoryScreen>
    with TickerProviderStateMixin {
  final StoryService _storyService = StoryService();
  final GoogleTtsService _ttsService = GoogleTtsService();
  final ScrollController _scrollController = ScrollController();

  // Animation controllers
  late AnimationController _bounceController;
  late AnimationController _rotateController;
  late AnimationController _scaleController;

  String? _conversationId;
  bool _isLoading = false;
  bool _needsConfirmation = false;
  bool _isSpeaking = false;
  String _pendingQuery = '';
  String _currentStory =
      'Hi there, I\'m Hopper the story lovin\' Frog. Tap a story button below to begin our wonderful reading journey!';

  // List to store assigned stories
  List<AssignedStory> _assignedStories = [];
  bool _loadingAssignedStories = false;

  // Theme-based story generation options
  final List<Map<String, dynamic>> _storyThemes = [
    {
      'name': 'Dragons',
      'icon': Icons.local_fire_department,
      'color': Colors.red,
      'theme': 'dragons'
    },
    {
      'name': 'Space',
      'icon': Icons.rocket_launch,
      'color': ColorTheme.accentBlueColor,
      'theme': 'space'
    },
    {
      'name': 'Animals',
      'icon': Icons.pets,
      'color': ColorTheme.green,
      'theme': 'animals'
    },
    {
      'name': 'Magic',
      'icon': Icons.auto_awesome,
      'color': ColorTheme.darkPurple,
      'theme': 'magic'
    },
    {
      'name': 'Pirates',
      'icon': Icons.sailing,
      'color': Colors.brown,
      'theme': 'pirates'
    },
    {
      'name': 'Dinosaurs',
      'icon': Icons.landscape,
      'color': ColorTheme.orange,
      'theme': 'dinosaurs'
    },
    {
      'name': 'Fairy Tales',
      'icon': Icons.castle,
      'color': ColorTheme.pink,
      'theme': 'fairy_tale'
    },
    {
      'name': 'Adventure',
      'icon': Icons.explore,
      'color': Colors.orangeAccent,
      'theme': 'adventure'
    },
  ];

  // Story continuation options
  final List<Map<String, dynamic>> _continuationOptions = [
    {
      'name': 'What happens next?',
      'icon': Icons.arrow_forward,
      'color': ColorTheme.accentBlueColor,
    },
    {
      'name': 'Different ending',
      'icon': Icons.auto_awesome,
      'color': ColorTheme.secondaryColor,
    },
    {
      'name': 'Make it funny!',
      'icon': Icons.emoji_emotions,
      'color': ColorTheme.orange,
    },
    {
      'name': 'Add a twist!',
      'icon': Icons.loop,
      'color': ColorTheme.pink,
    },
  ];

  @override
  void initState() {
    super.initState();

    // Initialize animation controllers
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _rotateController = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    )..repeat();

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    // Listen for TTS state changes

    _ttsService.addStateListener((isSpeaking) {
      if (mounted) {
        setState(() {
          _isSpeaking = isSpeaking;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Set the context for the StoryService
    _storyService.setContext(context);

    // Load assigned stories
    _loadAssignedStories();
  }

  // Load assigned stories from the backend
  Future<void> _loadAssignedStories() async {
    if (!mounted) return;

    setState(() {
      _loadingAssignedStories = true;
    });

    try {
      final stories = await _storyService.getAssignedStories();
      if (mounted) {
        setState(() {
          _assignedStories = stories;
          _loadingAssignedStories = false;
        });
      }
    } catch (e) {
      print('Error loading assigned stories: $e');
      if (mounted) {
        setState(() {
          _loadingAssignedStories = false;
        });
      }
    }
  }

  /// Speak the given text using Google Cloud TTS
  Future<void> _speak(String text) async {
    if (text.isNotEmpty) {
      await _ttsService.speak(text);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _ttsService.dispose();
    _bounceController.dispose();
    _rotateController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  void _requestStory(String prompt) async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (_needsConfirmation) {
        // Handle confirmation for new story when there's an existing conversation
        await _handleConfirmation('yes');
      } else {
        // Normal message handling
        await _handleNormalMessage(prompt);
      }
    } catch (e) {
      setState(() {
        _currentStory = 'Oops! Something went wrong. Try again!';
        _isLoading = false;
      });
    }
  }

  // Generate a themed story
  Future<void> _generateThemedStory(String theme) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _storyService.generateThemedStory(theme);

      setState(() {
        _isLoading = false;
        _currentStory = response['response'] ?? 'No story generated';
        if (response['conversation_id'] != null) {
          _conversationId = response['conversation_id'].toString();
        }

        // Automatically speak the story
        _speak(_currentStory);
      });
    } catch (e) {
      setState(() {
        _currentStory = 'Oops! Something went wrong. Try again!';
        _isLoading = false;
      });
    }
  }

  // Open an assigned story
  Future<void> _openAssignedStory(AssignedStory story) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final messages =
          await _storyService.getConversationMessages(story.conversationId);

      // Find the first model message (the story content)
      final storyMessage = messages.firstWhere(
        (msg) => msg.senderType == SenderType.MODEL,
        orElse: () => Message(
          id: '0',
          senderType: SenderType.MODEL,
          content: 'Story not found',
          createdAt: DateTime.now(),
          code: 0,
        ),
      );

      setState(() {
        _isLoading = false;
        _currentStory = storyMessage.content;
        _conversationId = story.conversationId;

        // Automatically speak the story
        _speak(_currentStory);
      });
    } catch (e) {
      setState(() {
        _currentStory = 'Oops! Something went wrong. Try again!';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleNormalMessage(String userMessage) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.userData?.uid ?? 'anonymous_user';

    Map<String, dynamic> response;

    if (_conversationId == null) {
      // New conversation
      response = await _storyService.getNewStory(userMessage, userId);
    } else {
      // Existing conversation
      response =
          await _storyService.addToStory(userMessage, userId, _conversationId!);
    }

    setState(() {
      _isLoading = false;

      // Check if we need confirmation for a new story
      if (response.containsKey('confirmation')) {
        _currentStory = response['confirmation'];
        _needsConfirmation = true;
        _pendingQuery = userMessage;
        _conversationId = response['conversation_id'].toString();
      } else {
        // Normal response
        final storyContent =
            response['response'] ?? response['message'] ?? 'No response';
        _currentStory = storyContent;
        if (response['conversation_id'] != null) {
          _conversationId = response['conversation_id'].toString();
        }

        // Automatically speak the story
        _speak(storyContent);
      }
    });
  }

  Future<void> _handleConfirmation(String userInput) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.userData?.uid ?? 'anonymous_user';

    final lowerInput = userInput.toLowerCase();
    String confirmation;

    if (lowerInput.contains('yes') || lowerInput.contains('y')) {
      confirmation = 'y';
    } else if (lowerInput.contains('no') || lowerInput.contains('n')) {
      confirmation = 'n';
    } else {
      setState(() {
        _currentStory = 'Please tap Yes or No!';
        _isLoading = false;
      });
      return;
    }

    final response = await _storyService.confirmNewStory(
        _pendingQuery, userId, _conversationId!, confirmation);

    setState(() {
      _isLoading = false;
      _needsConfirmation = false;
      _pendingQuery = '';

      if (confirmation == 'y') {
        final storyContent = response['response'] ?? 'New story created';
        _currentStory = storyContent;
        if (response['conversation_id'] != null) {
          _conversationId = response['conversation_id'].toString();
        }

        // Automatically speak the story
        _speak(storyContent);
      } else {
        _currentStory = 'Okay! Let\'s try a different story!';
      }
    });
  }

  // Show information about the Google Cloud TTS voice and allow voice selection
  void _showVoiceSelectionDialog() {
    // Get the current selected voice
    var currentVoice = _ttsService.selectedVoice;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.record_voice_over, color: Colors.deepPurple, size: 30),
              SizedBox(width: 10),
              Text(
                'Choose a Voice!',
                style: TextStyle(
                  color: Colors.deepPurple,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: LinearGradient(
                    colors: [Colors.purple[100]!, Colors.purple[50]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withOpacity(0.3),
                      blurRadius: 5,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                padding: EdgeInsets.all(15),
                child: Column(
                  children: [
                    Text(
                      'Who should tell your story?',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.deepPurple,
                      ),
                    ),
                    SizedBox(height: 15),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.deepPurple, width: 2),
                      ),
                      child: DropdownButton<GoogleTtsVoice>(
                        isExpanded: true,
                        value: currentVoice,
                        underline: Container(),
                        icon: Icon(Icons.arrow_drop_down_circle,
                            color: Colors.deepPurple),
                        items: _ttsService.voices.map((voice) {
                          return DropdownMenuItem<GoogleTtsVoice>(
                            value: voice,
                            child: Text(
                              voice.displayName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.deepPurple,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (GoogleTtsVoice? newVoice) async {
                          if (newVoice != null) {
                            await _ttsService.setVoice(newVoice);
                            setState(() {
                              currentVoice =
                                  newVoice; // Update the selected voice
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 15),
              Center(
                child: ElevatedButton.icon(
                  icon: Icon(Icons.play_circle_filled),
                  label: Text("Test Voice"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: () =>
                      _speak("Hello! I'll be telling your stories today!"),
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              icon: Icon(Icons.check_circle, color: Colors.green),
              label: Text(
                'Done',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.green,
                ),
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: ColorTheme.primaryColor,
        child: SafeArea(
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Animated app bar with bouncing elements
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: ColorTheme.accentYellowColor,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'W',
                                      style: TextStyle(
                                        fontSize: 22,
                                        color: ColorTheme.textColor,
                                        fontFamily: GoogleFonts.montserrat(
                                          fontWeight: FontWeight.bold,
                                        ).fontFamily,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'o',
                                      style: TextStyle(
                                        fontSize: 22,
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
                                        fontSize: 22,
                                        color: ColorTheme.textColor,
                                        fontFamily: GoogleFonts.montserrat(
                                          fontWeight: FontWeight.bold,
                                        ).fontFamily,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'e',
                                      style: TextStyle(
                                        fontSize: 22,
                                        color: ColorTheme.accentBlueColor,
                                        fontFamily: GoogleFonts.montserrat(
                                          fontWeight: FontWeight.bold,
                                        ).fontFamily,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'rW',
                                      style: TextStyle(
                                        fontSize: 22,
                                        color: ColorTheme.textColor,
                                        fontFamily: GoogleFonts.montserrat(
                                          fontWeight: FontWeight.bold,
                                        ).fontFamily,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'o',
                                      style: TextStyle(
                                        fontSize: 22,
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
                                        fontSize: 22,
                                        color: ColorTheme.textColor,
                                        fontFamily: GoogleFonts.montserrat(
                                          fontWeight: FontWeight.bold,
                                        ).fontFamily,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            ],
                          ),
                          Row(
                            children: [
                              // Voice selection button
                              IconButton(
                                icon: Icon(
                                  Icons.record_voice_over,
                                  color: ColorTheme.secondaryColor,
                                  size: 28,
                                ),
                                onPressed: _showVoiceSelectionDialog,
                                tooltip: 'Choose a Voice',
                              ),

                              // New story button
                              IconButton(
                                icon: Icon(
                                  Icons.refresh,
                                  color: Colors.black,
                                  size: 28,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _conversationId = null;
                                    _needsConfirmation = false;
                                    _pendingQuery = '';
                                  });
                                },
                                tooltip: 'New Story',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Story display area with animated elements
                    Flexible(
                      flex: 3,
                      child: Container(
                        margin: EdgeInsets.all(16),
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: ColorTheme.backgroundColor,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Stack(
                          children: [
                            // Story text with scroll
                            SingleChildScrollView(
                              controller: _scrollController,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Story title with animated stars
                                  Row(
                                    children: [
                                      const Image(
                                        image: AssetImage('assets/frog.png'),
                                        width: 50,
                                        height: 50,
                                      ),
                                      Text(
                                        'Welcome Adventurer',
                                        style: TextStyle(
                                          fontSize: 30,
                                          color: ColorTheme.accentBlueColor,
                                          fontFamily: GoogleFonts.montserrat(
                                            fontWeight: FontWeight.bold,
                                          ).fontFamily,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 16),

                                  // Story content
                                  Text(
                                    _currentStory,
                                    style: TextStyle(
                                      fontSize: 22,
                                      height: 1.5,
                                      color: Colors.black87,
                                    ),
                                  ),

                                  // Add some space at the bottom for better scrolling
                                  SizedBox(height: 60),
                                ],
                              ),
                            ),

                            // Play/Stop button (floating)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: AnimatedBuilder(
                                animation: _scaleController,
                                builder: (context, child) {
                                  return Transform.scale(
                                    scale: 1.0 + (_scaleController.value * 0.1),
                                    child: child,
                                  );
                                },
                                child: FloatingActionButton(
                                  onPressed: () => _speak(_currentStory),
                                  backgroundColor: ColorTheme.accentBlueColor,
                                  foregroundColor: ColorTheme.darkPurple,
                                  child: Icon(
                                    _isSpeaking ? Icons.stop : Icons.play_arrow,
                                    size: 32,
                                  ),
                                  tooltip: _isSpeaking ? 'Stop' : 'Play',
                                ),
                              ),
                            ),

                            // Loading indicator
                            if (_isLoading)
                              Center(
                                child: Container(
                                  padding: EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 10,
                                        offset: Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircularProgressIndicator(
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Colors.deepPurple,
                                        ),
                                        strokeWidth: 5,
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        'Creating your story...',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.deepPurple,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // Story theme selection or continuation options
                    Container(
                      height: 180,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(left: 20, bottom: 8),
                            child: Text(
                              _needsConfirmation
                                  ? 'Do you want a new story?'
                                  : (_conversationId == null
                                      ? 'Choose a theme'
                                      : 'What happens next?'),
                              style: TextStyle(
                                fontSize: 20,
                                fontFamily: GoogleFonts.montserrat(
                                  fontWeight: FontWeight.bold,
                                ).fontFamily,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 2,
                                    offset: Offset(1, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: _needsConfirmation
                                ? _buildConfirmationButtons()
                                : (_conversationId == null
                                    ? _buildThemeButtons()
                                    : _buildContinuationButtons()),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 250),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThemeButtons() {
    return buildThemeButtons(_storyThemes, _generateThemedStory);
  }

  Widget _buildContinuationButtons() {
    return buildContinuationButtons(
        _continuationOptions, _bounceController, _requestStory);
  }

  Widget _buildConfirmationButtons() {
    return buildConfirmationButtons(_scaleController, _handleConfirmation);
  }
}
