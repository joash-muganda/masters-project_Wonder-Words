import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import '../models/conversation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/assigned_story.dart';
import '../config/api_config.dart';
import 'auth/auth_provider.dart' as app_auth;
import 'package:flutter/foundation.dart';


class StoryService {
  // Get the base URL from ApiConfig
  static const isWeb = kIsWeb;
  static const baseUrl = isWeb ? ApiConfig.baseUrl : ApiConfig.deviceUrl;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Store the BuildContext for later use
  BuildContext? _context;

  // Set the BuildContext
  void setContext(BuildContext context) {
    print("Setting context in StoryService: $context");
    _context = context;
  }

  // Check if the context is initialized
  bool get isContextInitialized => _context != null;

  // Helper method to get the current user's ID token
  Future<String> getIdToken() async {
    if (_context == null) {
      throw Exception('Context not initialized');
    }

    // Get the AuthProvider instance
    final authProvider =
        Provider.of<app_auth.AuthProvider>(_context!, listen: false);

    // Check if the user is a child
    if (authProvider.isChild) {
      // For child accounts, we need to use the child token
      // This token should be stored in the AuthProvider when the child logs in
      final childToken = await _getChildToken();
      if (childToken != null) {
        return childToken;
      }
    }

    // For parent accounts, use Firebase authentication
    final User? user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }
    final String? token = await user.getIdToken();
    if (token == null) {
      throw Exception('Failed to get ID token');
    }
    return token;
  }

  // Helper method to get the child token
  Future<String?> _getChildToken() async {
    if (_context == null) {
      throw Exception('Context not initialized');
    }

    try {
      // Get the AuthProvider instance
      final authProvider =
          Provider.of<app_auth.AuthProvider>(_context!, listen: false);

      // Check if the user is a child
      if (authProvider.isChild) {
        // Get the child token from the AuthProvider
        return authProvider.childToken;
      }

      return null;
    } catch (e) {
      print('Error getting child token: $e');
      return null;
    }
  }
  // Method to utilize meta-prompting
  Future<Map<String, dynamic>> metaPrompt(String userInput) async {
    if (_context == null) {
      throw Exception('Context not initialized');
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/generate_meta_prompt'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'user_input': userInput,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get meta-prompt: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error connecting to server: $e');
    }
  }

  // Method to get a new story
  Future<Map<String, dynamic>> getNewStory(String query, String userId) async {
    if (_context == null) {
      throw Exception('Context not initialized');
    }

    try {
      final String idToken = await getIdToken();
      final authProvider =
          Provider.of<app_auth.AuthProvider>(_context!, listen: false);

      // Use the correct endpoint based on the account type
      final endpoint =
          authProvider.isChild ? 'handle_child_request' : 'handle_request';

      final response = await http.post(
        Uri.parse('$baseUrl/$endpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'query': query,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get story: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error connecting to server: $e');
    }
  }

  // Method to add to an existing story
  Future<Map<String, dynamic>> addToStory(
      String query, String userId, String conversationId) async {
    if (_context == null) {
      throw Exception('Context not initialized');
    }

    try {
      final String idToken = await getIdToken();
      final authProvider =
          Provider.of<app_auth.AuthProvider>(_context!, listen: false);

      // Use the correct endpoint based on the account type
      final endpoint =
          authProvider.isChild ? 'handle_child_request' : 'handle_request';

      final response = await http.post(
        Uri.parse('$baseUrl/$endpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'query': query,
          'conversation_id': conversationId,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to add to story: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error connecting to server: $e');
    }
  }

  // Method to confirm a new story when there's an existing conversation
  Future<Map<String, dynamic>> confirmNewStory(String query, String userId,
      String conversationId, String confirmation) async {
    if (_context == null) {
      throw Exception('Context not initialized');
    }

    try {
      final String idToken = await getIdToken();
      final authProvider =
          Provider.of<app_auth.AuthProvider>(_context!, listen: false);

      // Use the correct endpoint based on the account type
      final endpoint = authProvider.isChild
          ? 'confirm_child_new_story'
          : 'confirm_new_story';

      final response = await http.post(
        Uri.parse('$baseUrl/$endpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'query': query,
          'conversation_id': conversationId,
          'confirmation': confirmation,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to confirm new story: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error connecting to server: $e');
    }
  }

  // Method to get all conversations for the current user
  Future<List<Conversation>> getConversations({int? page, int? limit, List<String>? assignedStories}) async {
    // if page or limit is null, set default values to None
    if (_context == null) {
      throw Exception('Context not initialized');
    }

    try {
      final String idToken = await getIdToken();
      final authProvider =
          Provider.of<app_auth.AuthProvider>(_context!, listen: false);

      // Use the correct endpoint based on the account type
      final endpoint = authProvider.isChild
          ? 'get_child_conversations'
          : 'get_conversations';
      // if page and limit are null, set default values as 'None' in the Uri
      final String pageParam = page != null ? 'page=$page' : 'page=None';
      final String limitParam = limit != null ? 'limit=$limit' : 'limit=None';
      final String assignedStoriesParam = assignedStories != null
          ? 'assigned_stories=${jsonEncode(assignedStories)}'
          : 'assigned_stories=None';
      final response = await http.get(
        Uri.parse('$baseUrl/$endpoint?$pageParam&$limitParam&$assignedStoriesParam'),
        headers: {
          'Authorization': 'Bearer $idToken',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> conversationsJson = data['conversations'];
        return conversationsJson
            .map((json) => Conversation.fromJson(json))
            .toList();
      } else {
        throw Exception('Failed to get conversations: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error connecting to server: $e');
    }
  }

  // Method to get all messages for a specific conversation
  Future<List<Message>> getConversationMessages(String conversationId) async {
    if (_context == null) {
      throw Exception('Context not initialized');
    }

    try {
      final String idToken = await getIdToken();
      final authProvider =
          Provider.of<app_auth.AuthProvider>(_context!, listen: false);

      // Use the correct endpoint based on the account type
      final endpoint = authProvider.isChild
          ? 'get_child_conversation_messages'
          : 'get_conversation_messages';

      final response = await http.get(
        Uri.parse('$baseUrl/$endpoint?conversation_id=$conversationId'),
        headers: {
          'Authorization': 'Bearer $idToken',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> messagesJson = data['messages'];
        return messagesJson.map((json) => Message.fromJson(json)).toList();
      } else {
        throw Exception('Failed to get messages: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error connecting to server: $e');
    }
  }

  // Method to assign a story to a child
  Future<Map<String, dynamic>> assignStory(
      String conversationId, String childUsername, String title) async {
    if (_context == null) {
      throw Exception('Context not initialized');
    }

    try {
      final String idToken = await getIdToken();

      final response = await http.post(
        Uri.parse('$baseUrl/assign_story'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'conversation_id': conversationId,
          'child_username': childUsername,
          'title': title,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to assign story: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error connecting to server: $e');
    }
  }

  // Method to get assigned stories for a child
  Future<List<AssignedStory>> getAssignedStories() async {
    if (_context == null) {
      throw Exception('Context not initialized');
    }

    try {
      final String idToken = await getIdToken();

      final response = await http.get(
        Uri.parse('$baseUrl/get_assigned_stories'),
        headers: {
          'Authorization': 'Bearer $idToken',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> storiesJson = data['assigned_stories'];
        return storiesJson.map((json) => AssignedStory.fromJson(json)).toList();
      } else {
        throw Exception(
            'Failed to get assigned stories: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error connecting to server: $e');
    }
  }

  // Method to generate a themed story
  Future<Map<String, dynamic>> generateThemedStory(String theme) async {
    if (_context == null) {
      throw Exception('Context not initialized');
    }

    try {
      final String idToken = await getIdToken();

      final response = await http.post(
        Uri.parse('$baseUrl/generate_themed_story'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'theme': theme,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(
            'Failed to generate themed story: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error connecting to server: $e');
    }
  }

  // Method to delete a conversation
  Future<void> deleteConversation(String conversationId) async {
    if (_context == null) {
      throw Exception('Context not initialized');
    }

    try {
      final String idToken = await getIdToken();
      final authProvider =
          Provider.of<app_auth.AuthProvider>(_context!, listen: false);

      // Only parent accounts can delete conversations
      if (authProvider.isChild) {
        throw Exception('Child accounts cannot delete stories');
      }

      final response = await http.delete(
        Uri.parse(
            '$baseUrl/delete_conversation?conversation_id=$conversationId'),
        headers: {
          'Authorization': 'Bearer $idToken',
        },
      );

      if (response.statusCode != 200) {
        throw Exception(
            'Failed to delete conversation: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error connecting to server: $e');
    }
  }
}
