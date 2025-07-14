import 'package:flutter/material.dart';
import 'package:wonder_words_flutter_application/screens/home/story_screen.dart';
import 'package:wonder_words_flutter_application/services/debug/storyDetails.dart';
import 'package:wonder_words_flutter_application/services/debug/storyInference.dart';
import 'package:wonder_words_flutter_application/services/story_service.dart';
import '../../services/auth/auth_provider.dart';

class StoryDetailsForm extends StatefulWidget {
  const StoryDetailsForm({Key? key}) : super(key: key);

  @override
  _StoryDetailsFormState createState() => _StoryDetailsFormState();
}

class _StoryDetailsFormState extends State<StoryDetailsForm> {
  Map<String, dynamic> _submittedData = {};
  String _model = 'gpt'; // Add a state variable for the model
  String _taskType = 'story-generation'; // Add a state variable for the task type
  String _responseText = '';
  String _promptResponseText = '';
  String _formattedRequestText = '';

  late StoryDetails _storyDetails = StoryDetails(
    model: _model,
    taskType: _taskType,
    onSubmit: _handleSubmittedData,
    onResponse: _handleResponse,
  );

  void _handleSubmittedData(Map<String, dynamic> onSubmit) {
    setState(() {
      _submittedData = onSubmit;
      print('Submitted Data: $_submittedData');
    });
  }

  void _handleResponse(String response, String formattedRequest, String promptResponse) {
    setState(() {
      // only set if the parameters are not null or empty strings
      if (response.isNotEmpty) {
        _responseText = response;
      }
      if (formattedRequest.isNotEmpty) {
        _formattedRequestText = formattedRequest;
      }
      if (promptResponse.isNotEmpty) {
        _promptResponseText = promptResponse;
      }
    });
  }

  void _toggleModel(String? newValue) {
    setState(() {
      _model = newValue!;
      print('Model changed to: $_model');
    _storyDetails.setModel(_model);
    });
  }

  void _toggleTaskType(String? newValue) {
    setState(() {
      _taskType = newValue!;
      print('Task type changed to: $_taskType');
      _storyDetails.setTaskType(_taskType);
    });
  }

  void _showVoiceSelectionDialog() {
    // Implementation of _showVoiceSelectionDialog
  }

  void _refreshMessages() {
    setState(() {
      _responseText = '';
      _promptResponseText = '';
      _formattedRequestText = '';
      _storyDetails.refreshInput();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: StoryScreen.buildAppBar(context, _showVoiceSelectionDialog, _refreshMessages, isStoryDetailsForm: true),
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                  child: Row(
                                    children: [
                                      const Text('Model: '),
                                      DropdownButton<String>(
                                        value: _model,
                                        onChanged: _toggleModel,
                                        items: <String>['gpt', 'llama'].map<DropdownMenuItem<String>>((String value) {
                                          return DropdownMenuItem<String>(
                                            value: value,
                                            child: Text(value),
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20), // Add some space between the dropdowns
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                  child: Row(
                                    children: [
                                      const Text('Task Type: '),
                                      DropdownButton<String>(
                                        value: _taskType,
                                        onChanged: _toggleTaskType,
                                        items: <String>['story-generation', 'prompt-generation'].map<DropdownMenuItem<String>>((String value) {
                                          return DropdownMenuItem<String>(
                                            value: value,
                                            child: Text(value),
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _storyDetails,
                          const SizedBox(height: 20),
                          if (_taskType == 'story-generation') ...[
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: 200.0, // Adjust the max height as needed
                              ),
                              child: SingleChildScrollView(
                                child: TextField(
                                  controller: TextEditingController(text: _responseText),
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    labelText: 'Story Response',
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  readOnly: true,
                                  maxLines: null,
                                ),
                              ),
                            ),
                          ],
                          if (_taskType == 'prompt-generation') ...[
                            const SizedBox(height: 20),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: 200.0, // Adjust the max height as needed
                              ),
                              child: SingleChildScrollView(
                                child: TextField(
                                  controller: TextEditingController(text: _formattedRequestText),
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    labelText: 'AI Prompt',
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  readOnly: true,
                                  maxLines: null,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: 200.0, // Adjust the max height as needed
                              ),
                              child: SingleChildScrollView(
                                child: TextField(
                                  controller: TextEditingController(text: _promptResponseText),
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    labelText: 'Prompt Response',
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  readOnly: true,
                                  maxLines: null,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
