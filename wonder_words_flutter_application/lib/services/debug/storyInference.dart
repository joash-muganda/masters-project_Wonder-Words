import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';


class OpenAI {
  final String baseURL;
  final String apiKey;

  OpenAI({required this.baseURL, required this.apiKey});

  Future<dynamic> chatCompletionsCreate(Map<String, dynamic> body) async {
    final response = await http.post(Uri.parse("$baseURL/completions"), headers: {"Authorization": "Bearer $apiKey", "Content-Type":"application/json"}, body: jsonEncode(body));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
      // print response body and status code
    } else {
      throw Exception('Failed to load story. Status code: ${response.statusCode}. Response: ${response.body}');
      
    }
    

  }
}