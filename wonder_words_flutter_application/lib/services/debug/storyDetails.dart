import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:wonder_words_flutter_application/config/api_config.dart';
import 'package:wonder_words_flutter_application/services/debug/storyInference.dart';
import 'package:wonder_words_flutter_application/services/debug/storyRequest.dart';
import 'package:wonder_words_flutter_application/services/story_service.dart';
// import kisWeb to check if the app is running on web
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';

final StoryService _storyService = StoryService();
// initialize the storyservice context
bool _needsConfirmation = false;
// define the .env file


class StoryDetails extends StatefulWidget {
  final Function(Map<String, dynamic>) onSubmit;
  final Function(String, String, String) onResponse; // Modify the callback function to accept three parameters
  String model;
  String taskType = 'story-generation';
  List<String> models = ['gpt', 'llama'];
  List<String> taskTypes = ['story-generation', 'prompt-generation', 'story-continuation'];
  StoryDetails({required this.onSubmit, required this.model, required this.taskType, required this.onResponse}) {
    if (!models.contains(model)) {
      throw ArgumentError('Invalid model: $model. Valid models are: ${models.join(', ')}');
    }
    if (!taskTypes.contains(taskType)) {
      throw ArgumentError('Invalid task type: $taskType. Valid task types are: ${taskTypes.join(', ')}');
    }
  }

  final _StoryDetailsState _storyDetailsState = _StoryDetailsState();

  void setModel(String newModel) {
    _storyDetailsState.setModel(newModel);
  }

  void setTaskType(String newTaskType) {
    _storyDetailsState.setTaskType(newTaskType);
  }

  void setIsNewStory(bool newIsNewStory) {
    _storyDetailsState.setIsNewStory(newIsNewStory);
  }

  void setLastUserInput(String newLastUserInput) {
    _storyDetailsState.setLastUserInput(newLastUserInput);
  }

  void refreshInput() {
    _storyDetailsState.refreshInput();
    // also clearing the text controllers
    _storyDetailsState._titleController.clear();
    _storyDetailsState._narrativesController.clear();
    _storyDetailsState._vocabularyController.clear();
  }

  // Public getters to access state variables
  bool get isNewStory => _storyDetailsState.isNewStory;
  String get lastUserInput => _storyDetailsState.lastUserInput;
  int? get conversationId => _storyDetailsState.conversationId;
  Function(int?) get setConversationId => _storyDetailsState.setConversationId;
  Function(bool) get setPendingConfirmation => _storyDetailsState.setPendingConfirmation;
  Function(String, String) get handleSubmit => _storyDetailsState._handleSubmit;
  Future<Map<String, dynamic>?> Function(String) get sendConfirmation => _storyDetailsState._sendConfirmation;

  @override
  _StoryDetailsState createState() => _storyDetailsState;
}

class SubmitButton extends StatelessWidget {
  final bool isNewStory;
  final String lastUserInput;
  final String model;
  final String taskType;
  final Function(String, String) handleSubmit;
  final Future<Map<String, dynamic>?> Function(String) sendConfirmation;
  final Function(String, String, String) onResponse;
  final int? conversationId;
  final Function(int?) setConversationId;
  final Function(bool) setPendingConfirmation;

  const SubmitButton({
    Key? key,
    required this.isNewStory,
    required this.lastUserInput,
    required this.model,
    required this.taskType,
    required this.handleSubmit,
    required this.sendConfirmation,
    required this.onResponse,
    required this.conversationId,
    required this.setConversationId,
    required this.setPendingConfirmation,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () async {
        if (isNewStory) {
          handleSubmit(model, taskType);
          print('Submitted user input');
          print('new story request');
          print('Last user input: $lastUserInput');
          // if model = 'llama' don't send confirmation
          if (!(model == 'llama')) {
            final confirmResponse = await sendConfirmation('y');
            print('Confirmation response: $confirmResponse'); 
            if (confirmResponse != null) {
              setConversationId(confirmResponse['conversation_id'] as int?);
              setPendingConfirmation(false);
    
              if (taskType == 'story-generation' || taskType == 'story-continuation') {
                onResponse(confirmResponse['response'] ?? '', '', '');
              } else if (taskType == 'prompt-generation') {
                onResponse('', lastUserInput, confirmResponse['response'] ?? '');
              }
            }
          } {
            handleSubmit(model, taskType);
          }
          // llama model doesn't have a confirmation step

        } else {
          print('continued story request');
          print('Last user input: $lastUserInput');
          handleSubmit(model, taskType);
        }
      },
      child: Text('Submit'),
    );
  }
}

class _StoryDetailsState extends State<StoryDetails> {
  final _formKey = GlobalKey<FormState>();

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      widget.onSubmit(_submittedData);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Set the context for the StoryService
    _storyService.setContext(context);
  }

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _narrativesController = TextEditingController();
  final TextEditingController _vocabularyController = TextEditingController();

  // New controller for open-ended user prompt
  final TextEditingController _userPromptController = TextEditingController();

  Map<String, dynamic> _submittedData = {};
  StoryRequest? storyRequest;
  int? conversationId;
  bool pendingConfirmation = false;
  String lastUserInput = "";
  bool isNewStory = true;

  void _handleSubmit(String model, String taskType) async {
    print('Handling submit');
    print("Using model: $model");
    print("Using task type: $taskType");
    print('Is new story: $isNewStory');
    setState(() {
      _submittedData = {
        'title': _titleController.text,
        'prompt': _userPromptController.text,
        'narratives': _narrativesController.text,
        'vocabulary': _vocabularyController.text
      };
    });

    widget.onSubmit(_submittedData); // Ensure the onSubmit callback is called

    StoryRequest storyRequest = StoryRequest.fromJson(_submittedData);

    if (!isNewStory && taskType == 'story-generation') {
      taskType = 'story-continuation';
    }
    print('Task type: $taskType');
    print('model: $model');
    if (model == 'llama') {
      print('calling llama');
      WidgetsFlutterBinding.ensureInitialized();
      // Loading the API key from the .env file
      final apiKey = dotenv.env['HUGGINGFACE_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('HUGGINGFACE_API_KEY is not defined. Please set it in your environment variables.');
      }
      print('API Key loaded successfully');

      if (apiKey.isEmpty) {
        print('HUGGINGFACE_API_KEY is not defined. Please set it in your environment variables.');
        throw Exception('HUGGINGFACE_API_KEY is not defined. Please set it in your environment variables.');
      }
      
      
      print('calling huggingface');

      final openai = OpenAI(baseURL: 'https://zq0finoawyna397e.us-east-1.aws.endpoints.huggingface.cloud/v1/chat', apiKey: apiKey); // Replace with your actual key

      final response = await openai.chatCompletionsCreate({
        "model": "tgi",
        "messages": [
          {"role": "user", "content": storyRequest.formatStoryRequest(taskType)}
        ],
        'max_tokens': 150,
        'stream': false
      });

      if (taskType == 'story-generation') {
        widget.onResponse(response['choices'][0]['message']['content'], '', '');
      } else if (taskType == 'prompt-generation') {
        widget.onResponse('', storyRequest.formatStoryRequest(taskType), response['choices'][0]['message']['content']);
      }
      
    }

    if (model == 'gpt') {
      // if-else statement to check if the task type is 'story-generation' or 'story-continuation', or 'prompt-generation'
      final response = taskType == 'prompt-generation'
          ? await _sendMetaPromptRequest(storyRequest.formatStoryRequest(taskType))
          : await _sendGptRequest(storyRequest.formatStoryRequest(taskType));

      if (response != null) {
        if (response.containsKey('confirmation')) {
          print('confirmation expected');
          setState(() {
            lastUserInput = storyRequest.formatStoryRequest(taskType);
            pendingConfirmation = true;
          });
        } else {
          if (taskType == 'story-generation' || taskType == 'story-continuation') {
            // guard clause to check if respons has 'message' key indicating error message
            //check if message key is in response
            if (!response.containsKey('message')) {
              widget.onResponse(response['response'], '', '');
            }
          } else if (taskType == 'prompt-generation') {
            // print the keys in the json respons
            if (!response.containsKey('message')) {
              widget.onResponse('', storyRequest.formatStoryRequest(taskType), response['response']);
            }
          } else {
            if (!response.containsKey('message')) {
              // print the keys in the json respons
              widget.onResponse('', storyRequest.formatStoryRequest(taskType), response['response']);
            }
          }
        } 
      } else {
        print('Error: No response data received. The server might have encountered an error.');
      }
    }
  }

  Future<Map<String, dynamic>?> _sendGptRequest(String userInput) async {
    const isWeb = kIsWeb;
    const base = isWeb ? ApiConfig.baseUrl : ApiConfig.deviceUrl;

    String url = '$base/handle_request';
    final String idToken = await _storyService.getIdToken();
    print('Sending GPT request to $url');

    setState(() {
      lastUserInput = userInput;
    });
  
    Map<String, dynamic> data = {
      'query': userInput,
      'user_id': 'test_user',
        if (conversationId != null) 'conversation_id': conversationId
    };

    http.Response response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $idToken'},
      body: jsonEncode(data),
    );
    print(response.body);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      print('Failed to get response from GPT API');
      // return map with error message
      return {
        'error': 'Failed to get response from GPT API'
      };
    }
  }

  // funciton to send request to /generate_meta_prompt
  Future<Map<String, dynamic>?> _sendMetaPromptRequest(String userInput) async {
    const isWeb = kIsWeb;
    const base = isWeb ? ApiConfig.baseUrl : ApiConfig.deviceUrl;

    String url = '$base/generate_meta_prompt';

    print('Sending meta prompt request to $url');

    Map<String, dynamic> data = {
      'user_input': userInput,
    };

    http.Response response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      print('Failed to get response from GPT API');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _sendConfirmation(String confirmation) async {
    const isWeb = kIsWeb;
    const base = isWeb ? ApiConfig.baseUrl : ApiConfig.deviceUrl;

    String url = '$base/confirm_new_story';
    final String idToken = await _storyService.getIdToken();
    print('Sending confirmation to $url');
    print('Last user input: $lastUserInput');

    Map<String, dynamic> data = {
      'query': lastUserInput,
      'user_id': 'test_user',
      'confirmation': confirmation,
      if (conversationId != null) 'conversation_id': conversationId,
    };

    http.Response response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $idToken'},
      body: jsonEncode(data),
    );
    if (response.statusCode == 200) {
      print('Confirmation response received');
      return jsonDecode(response.body);
    } else {
      print('Failed to get confirmation response from GPT API');
      print(response.body);
      print(response.statusCode);
      return null;
    }
  }

  void refreshInput() {
    _titleController.clear();
    _narrativesController.clear();
    _vocabularyController.clear();
  }

  void setModel(String newModel) {
    setState(() {
      widget.model = newModel;
    });
  }

  void setTaskType(String newTaskType) {
    setState(() {
      widget.taskType = newTaskType;
    });
  }

  void setIsNewStory(bool newIsNewStory) {
    setState(() {
      isNewStory = newIsNewStory;
    });
  }

  void setLastUserInput(String newLastUserInput) {
    setState(() {
      lastUserInput = newLastUserInput;
    });
  }

  void setConversationId(int? newConversationId) {
    setState(() {
      conversationId = newConversationId;
    });
  }

  void setPendingConfirmation(bool newPendingConfirmation) {
    setState(() {
      pendingConfirmation = newPendingConfirmation;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _titleController,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Whats the title of your new story?',
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _narrativesController,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'What are some storytelling narrative features related to your story?',
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _vocabularyController,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'What are some vocabulary words related to your story?',
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        // New TextField for open-ended user prompt
        TextField(
          controller: _userPromptController,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Enter an open-ended prompt for your story',
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        if (lastUserInput.isNotEmpty)
          CheckboxListTile(
            title: Text('Is this a new story?'),
            value: isNewStory,
            onChanged: (bool? value) {
              setState(() {
                isNewStory = value ?? false;
              });
            },
          ),
        SizedBox(height: 16.0),
        SubmitButton(
          isNewStory: isNewStory,
          lastUserInput: lastUserInput,
          model: widget.model,
          taskType: widget.taskType,
          handleSubmit: _handleSubmit,
          sendConfirmation: _sendConfirmation,
          onResponse: widget.onResponse,
          conversationId: conversationId,
          setConversationId: setConversationId,
          setPendingConfirmation: setPendingConfirmation,
        ),
      ],
    );
  }
}
