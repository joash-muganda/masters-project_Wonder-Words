import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:wonder_words_flutter_application/colors.dart';
import '../../services/auth/auth_provider.dart';
import '../../services/story_service.dart';
import '../../services/tts/google_tts_service.dart';
import 'story_history_screen.dart';
import 'package:wonder_words_flutter_application/services/debug/storyDetailsForm.dart';

class Message {
  final String content;
  final bool isUser;

  Message({required this.content, required this.isUser});
}

class StoryScreen extends StatefulWidget {
  const StoryScreen({Key? key}) : super(key: key);

  @override
  State<StoryScreen> createState() => StoryScreenState();

  static AppBar buildAppBar(BuildContext context, Function showVoiceInfoDialog,
      Function refreshMessages,
      {bool isStoryDetailsForm = false}) {
    return AppBar(
      title: Text('WonderWords',
          style: TextStyle(
              color: ColorTheme.darkPurple,
              fontFamily: GoogleFonts.montserrat(fontWeight: FontWeight.bold)
                  .fontFamily)),
      backgroundColor: ColorTheme.accentYellowColor,
      foregroundColor: Colors.black,
      leading: isStoryDetailsForm
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                Navigator.pop(context);
              },
              color: ColorTheme.accentBlueColor,
            )
          : null,
      actions: [
        if (!isStoryDetailsForm)
          IconButton(
            icon: const Icon(Icons.record_voice_over),
            onPressed: () => showVoiceInfoDialog(),
            tooltip: 'Select Voice',
            color: ColorTheme.accentBlueColor,
          ),
        IconButton(
          icon: const Icon(Icons.history),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const StoryHistoryScreen(),
              ),
            );
          },
          tooltip: 'View Story History',
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => refreshMessages(),
          tooltip: 'Start New Conversation',
        ),
        if (!isStoryDetailsForm)
          IconButton(
            icon: const Icon(Icons.details),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StoryDetailsForm(),
                ),
              );
            },
            tooltip: 'Story Details',
          ),
      ],
    );
  }
}

class StoryScreenState extends State<StoryScreen> {
  final TextEditingController _promptController = TextEditingController();
  final StoryService _storyService = StoryService();
  final GoogleTtsService _ttsService = GoogleTtsService();
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  String? _conversationId;
  bool _isLoading = false;
  bool _needsConfirmation = false;
  bool _isSpeaking = false;
  String _pendingQuery = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Set the context for the StoryService
    _storyService.setContext(context);
  }

  final List<Message> _messages = [
    Message(
      content: 'Welcome to Wonder Words! Ask me to tell you a story.',
      isUser: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Listen for TTS state changes
    _ttsService.addStateListener((isSpeaking) {
      if (mounted) {
        setState(() {
          _isSpeaking = isSpeaking;
        });
      }
    });
  }

  /// Speak the given text using Google Cloud TTS
  Future<void> _speak(String text) async {
    if (text.isNotEmpty) {
      await _ttsService.speak(text);
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    _ttsService.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    if (_promptController.text.trim().isEmpty) return;

    final userMessage = _promptController.text.trim();
    setState(() {
      _messages.add(Message(content: userMessage, isUser: true));
      _isLoading = true;
      _promptController.clear();
    });

    _scrollToBottom();

    try {
      if (_needsConfirmation) {
        // Handle confirmation for new story when there's an existing conversation
        await _handleConfirmation(userMessage);
      } else {
        // Normal message handling
        await _handleNormalMessage(userMessage);
      }
    } catch (e) {
      setState(() {
        _messages.add(Message(
          content: 'Error: ${e.toString()}',
          isUser: false,
        ));
        _isLoading = false;
      });
      _scrollToBottom();
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
        _messages.add(Message(
          content: response['confirmation'],
          isUser: false,
        ));
        _needsConfirmation = true;
        _pendingQuery = userMessage;
        _conversationId = response['conversation_id'].toString();
      } else {
        // Normal response
        final storyContent =
            response['response'] ?? response['message'] ?? 'No response';
        _messages.add(Message(
          content: storyContent,
          isUser: false,
        ));
        if (response['conversation_id'] != null) {
          _conversationId = response['conversation_id'].toString();
        }

        // Automatically speak the story
        _speak(storyContent);
      }
    });

    _scrollToBottom();
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
        _messages.add(Message(
          content: 'Please respond with "yes" or "no".',
          isUser: false,
        ));
        _isLoading = false;
      });
      _scrollToBottom();
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
        _messages.add(Message(
          content: storyContent,
          isUser: false,
        ));
        if (response['conversation_id'] != null) {
          _conversationId = response['conversation_id'].toString();
        }

        // Automatically speak the story
        _speak(storyContent);
      } else {
        _messages.add(Message(
          content: 'New story request canceled.',
          isUser: false,
        ));
      }
    });

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Show information about the Google Cloud TTS voice and allow voice selection
  void _showVoiceInfoDialog() {
    // Get the current selected voice
    var currentVoice = _ttsService.selectedVoice;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Voice Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Using Google Cloud Text-to-Speech',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'This app uses Google\'s Neural2 voice technology for high-quality, natural-sounding narration.',
              ),
              const SizedBox(height: 16),
              const Text(
                'Select a voice:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<GoogleTtsVoice>(
                  isExpanded: true,
                  value: currentVoice,
                  underline: Container(), // Remove the default underline
                  items: _ttsService.voices.map((voice) {
                    return DropdownMenuItem<GoogleTtsVoice>(
                      value: voice,
                      child: Text(voice.displayName),
                    );
                  }).toList(),
                  onChanged: (GoogleTtsVoice? newVoice) async {
                    if (newVoice != null) {
                      await _ttsService.setVoice(newVoice);
                      print('Set voice as: ${newVoice.displayName}');
                      currentVoice =
                          newVoice; // Update the current voice for the dialog
                      setState(() {}); // Update the dialog state
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'If you\'re offline, the app will automatically switch to your device\'s built-in text-to-speech.',
                style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _startListening() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (status) => print('Speech status: $status'),
        onError: (error) => print('Speech error: $error'),
      );
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(onResult: (result) {
          setState(() {
            _promptController.text = result.recognizedWords;
          });
        });
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final isChild = authProvider.isChild;

    return Scaffold(
      appBar: StoryScreen.buildAppBar(
          context, _showVoiceInfoDialog, _refreshMessages),
      body: Container(
        decoration: BoxDecoration(color: ColorTheme.backgroundColor),
        child: Column(
          children: [
            // Story suggestions for children
            if (isChild)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                color: Colors.white.withOpacity(0.7),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      _buildSuggestionChip('Tell me a story about a dragon'),
                      _buildSuggestionChip('Tell me a fairy tale'),
                      _buildSuggestionChip('Tell me a space adventure'),
                      _buildSuggestionChip('Tell me a story about animals'),
                      _buildSuggestionChip('Tell me a funny story'),
                    ],
                  ),
                ),
              ),

            // Messages
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length + (_isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length) {
                    // Show loading indicator
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  final message = _messages[index];
                  return _buildMessageBubble(message);
                },
              ),
            ),

            // Input area
            Container(
              padding: const EdgeInsets.all(8.0),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _promptController,
                      decoration: InputDecoration(
                        hintText: 'Ask for a story...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    heroTag: 'micButton',
                    onPressed: _startListening,
                    backgroundColor:
                        _isListening ? Colors.red : ColorTheme.accentBlueColor,
                    foregroundColor: ColorTheme.darkPurple,
                    child: Icon(_isListening ? Icons.mic : Icons.mic_none),
                    mini: true,
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    heroTag: 'sendButton',
                    onPressed: _sendMessage,
                    backgroundColor: ColorTheme.accentBlueColor,
                    foregroundColor: ColorTheme.darkPurple,
                    child: const Icon(Icons.send),
                    mini: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionChip(String suggestion) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ActionChip(
        label: Text(
          suggestion,
          style: const TextStyle(fontSize: 12),
        ),
        backgroundColor: Colors.deepPurple[100],
        onPressed: () {
          _promptController.text = suggestion;
          _sendMessage();
        },
      ),
    );
  }

  Widget _buildMessageBubble(Message message) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: message.isUser ? ColorTheme.accentBlueColor : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: TextStyle(
                color: message.isUser ? ColorTheme.darkPurple : Colors.black87,
                fontSize: 16,
              ),
            ),
            if (!message.isUser) // Only show speak button for AI messages
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: Icon(
                    _isSpeaking ? Icons.stop : Icons.volume_up,
                    color: ColorTheme.darkPurple,
                    size: 20,
                  ),
                  onPressed: () => _speak(message.content),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _refreshMessages() {
    setState(() {
      _messages.clear();
      _messages.add(Message(
        content: 'Welcome to Wonder Words! Ask me to tell you a story.',
        isUser: false,
      ));
      _conversationId = null;
      _needsConfirmation = false;
      _pendingQuery = '';
    });
  }
}
