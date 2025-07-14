import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import '../../config/api_config.dart';
// import 'package:dio_interceptor/dio_interceptor.dart'; // Removed as the package is not found

/// Voice model for Google Cloud TTS
class GoogleTtsVoice {
  final String name;
  final String displayName;
  final String languageCode;
  final String gender;
  final bool isNeural;

  GoogleTtsVoice({
    required this.name,
    required this.displayName,
    required this.languageCode,
    required this.gender,
    required this.isNeural,
  });
}

/// A service that provides text-to-speech functionality using Google Cloud TTS API.
/// It includes caching to reduce API calls and a fallback to device TTS when offline.
class GoogleTtsService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _flutterTts = FlutterTts(); // Fallback TTS

  bool isSpeaking = false;
  final List<Function(bool)> _stateListeners = [];

  // Free tier limits
  static const int FREE_TIER_LIMIT = 1000000; // 1 million characters per month
  int _monthlyUsage = 0;
  String _currentMonth = '';

  // Cache to avoid repeated API calls for the same text
  final Map<String, String> _audioCache = {};

  // Available voices
  final List<GoogleTtsVoice> _voices = [
    GoogleTtsVoice(
      name: "en-US-Chirp3-HD-Achernar",
      displayName: 'Female 1',
      languageCode: 'en-US',
      gender: 'FEMALE',
      isNeural: true,
    ),
    GoogleTtsVoice(
      name: "en-US-Chirp3-HD-Enceladus",
      displayName: 'Male 1',
      languageCode: 'en-US',
      gender: 'MALE',
      isNeural: true,
    )
  ];

  // Currently selected voice (default to first voice)
  late GoogleTtsVoice _selectedVoice;

  // Private constructor
  GoogleTtsService() {
    _selectedVoice = _voices[0]; // Default to first voice
    _initFallbackTts();
    _initUsageTracking();
    _initCache();
    _loadSelectedVoice();
  }

  /// Get the list of available voices
  List<GoogleTtsVoice> get voices => _voices;

  /// Get the currently selected voice
  GoogleTtsVoice get selectedVoice => _selectedVoice;

  /// Set the voice to use
  Future<void> setVoice(GoogleTtsVoice voice) async {
    _selectedVoice = voice;
    print('Setting voice to: ${voice.displayName}');
    // Save the selected voice
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tts_selected_voice', voice.name);
  }

  /// Load the previously selected voice
  Future<void> _loadSelectedVoice() async {
    print('Loading selected voice from storage...');
    try {
      final prefs = await SharedPreferences.getInstance();
      final voiceName = prefs.getString('tts_selected_voice');

      if (voiceName != null) {
        final voice = _voices.firstWhere(
          (v) => v.name == voiceName,
          orElse: () => _selectedVoice,
        );
        _selectedVoice = voice;
      }
    } catch (e) {
      print('Error loading selected voice: $e');
    }
  }

  /// Initialize usage tracking
  Future<void> _initUsageTracking() async {
    final now = DateTime.now();
    final thisMonth = '${now.year}-${now.month}';

    final prefs = await SharedPreferences.getInstance();
    _currentMonth = prefs.getString('tts_current_month') ?? '';

    // Reset counter if it's a new month
    if (_currentMonth != thisMonth) {
      _monthlyUsage = 0;
      await prefs.setString('tts_current_month', thisMonth);
      await prefs.setInt('tts_monthly_usage', 0);
    } else {
      _monthlyUsage = prefs.getInt('tts_monthly_usage') ?? 0;
    }

    print('TTS Usage this month: $_monthlyUsage characters');
  }

  /// Update usage tracking
  Future<void> _updateUsage(int characters) async {
    _monthlyUsage += characters;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tts_monthly_usage', _monthlyUsage);
    print('Updated TTS usage: $_monthlyUsage characters');
  }

  /// Initialize persistent cache
  Future<void> _initCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedItems = prefs.getStringList('tts_cache_keys') ?? [];

      for (var key in cachedItems) {
        final path = prefs.getString('tts_cache_$key');
        if (path != null && File(path).existsSync()) {
          _audioCache[key] = path;
        }
      }

      print('Loaded ${_audioCache.length} items from TTS cache');
    } catch (e) {
      print('Error initializing TTS cache: $e');
    }
  }

  /// Save to persistent cache
  Future<void> _saveToCacheStorage(String textHash, String audioPath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedItems = prefs.getStringList('tts_cache_keys') ?? [];

      if (!cachedItems.contains(textHash)) {
        cachedItems.add(textHash);
        await prefs.setStringList('tts_cache_keys', cachedItems);
      }

      await prefs.setString('tts_cache_$textHash', audioPath);

    } catch (e) {
      print('Error saving to TTS cache: $e');
    }
  }

  // save to backend
  Future<String> _saveToBackend({required String filename, required String bytes}) async {
    try {
      // Implement your backend saving logic here
      const String backendUrl = kIsWeb ? ApiConfig.baseUrl : ApiConfig.deviceUrl;
      final response = await http.post(
        Uri.parse('$backendUrl/upload_audio'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'filename': filename,
          'bytes': bytes,
        }),
      );
      
      final responseBody = json.decode(response.body);
      return responseBody['file_path'];
    } catch (e) {
      print('Error saving to backend: $e');
      throw Exception('Failed to save to backend');
    }
  }

  /// Add a listener for TTS state changes
  void addStateListener(Function(bool) listener) {
    _stateListeners.add(listener);
  }

  /// Remove a listener for TTS state changes
  void removeStateListener(Function(bool) listener) {
    _stateListeners.remove(listener);
  }

  /// Notify all listeners of state changes
  void notifyListeners() {
    //print("Notifying listeners: isSpeaking = $isSpeaking");
    for (var listener in _stateListeners) {
      listener(isSpeaking);
    }
  }

  /// Initialize the fallback TTS engine
  Future<void> _initFallbackTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.9); // Slightly slower for storytelling
    await _flutterTts.setPitch(1.0); // Natural pitch
    await _flutterTts.setVolume(1.0); // Full volume

    _flutterTts.setStartHandler(() {
      isSpeaking = true;
      notifyListeners();
    });

    _flutterTts.setCompletionHandler(() {
      isSpeaking = false;
      notifyListeners();
    });

    _flutterTts.setErrorHandler((error) {
      isSpeaking = false;
      notifyListeners();
      print('Fallback TTS error: $error');
    });
  }

  /// Speak the given text using Google Cloud TTS or fallback to device TTS if offline
  Future<void> speak(String text) async {
    if (isSpeaking) {
      await stop();
      return;
    }

    try {
      // Check if adding this text would exceed the free tier limit
      if (_monthlyUsage + text.length > FREE_TIER_LIMIT) {
        print('Warning: Approaching free tier limit. Using fallback TTS.');
        await _speakWithFallbackTts(text);
        return;
      }

      // Check internet connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasInternet = connectivityResult != ConnectivityResult.none;

      if (hasInternet) {
        await _speakWithGoogleTts(text);
        // Update usage only if Google TTS was used successfully
        await _updateUsage(text.length);
      } else {
        await _speakWithFallbackTts(text);
      }
    } catch (e) {
      print('Error in speak: $e');
      // Try fallback if Google TTS fails
      await _speakWithFallbackTts(text);
    }
  }

  /// Stop speaking
  Future<void> stop() async {
    isSpeaking = false;
    await _audioPlayer.stop();
    await _flutterTts.stop();
    notifyListeners();
  }
  
  /// Speak using Google Cloud TTS
  Future<void> _speakWithGoogleTts(String text) async {
    print('Using Google TTS...');
    if (text.isEmpty) {
      print('Text is empty, nothing to speak.');
      return;
    }

    try {
      // Generate a hash of the text combined with the selected voice
      final textHash =
          md5.convert(utf8.encode('$text|${_selectedVoice.name}')).toString();
      String? audioPath = _audioCache[textHash];

      // If not cached, or if the voice has changed, call the API to synthesize speech
      if (audioPath == null) {
        try {
          print('Calling _synthesizeSpeech in GoogleTtsService...');
          audioPath = await _synthesizeSpeech(text, textHash);
          _audioCache[textHash] = audioPath;

          // Limit cache size to 50 entries (simple LRU implementation)
          if (_audioCache.length > 50) {
            final oldestKey = _audioCache.keys.first;
            _audioCache.remove(oldestKey);
          }
        } catch (e) {
          print('Error synthesizing speech: $e');
          await _speakWithFallbackTts(text);
          return;
        }
      }

      // Play the audio
      isSpeaking = true;
      notifyListeners();

      try {
        if (kIsWeb) {
          try {
            // format the apiurl for download_audio from app.py
            const String backendUrl = kIsWeb ? ApiConfig.baseUrl : ApiConfig.deviceUrl;
            // Use the backend URL to get the audio file
            String audio_url = '$backendUrl/download_audio?file_path=$audioPath';
            // saving the 
            // Set the audio source
            print('Setting audio source for web playback...');
            print('using URL instead of file path');
            // Use just_audio to play the audio
            await _audioPlayer.setUrl(audio_url, headers: {'Content-Type': 'application/json'});
            _audioPlayer.play();
            // Listen for completion
            _audioPlayer.playerStateStream.listen((state) {
              if (state.processingState == ProcessingState.completed) {
                isSpeaking = false;
                notifyListeners();
              }
            });
          } catch (e) {
            print('Error playing audio using just_audio: $e');
            // Fallback to flutterTts for web playback
            await _flutterTts.speak(text); // Use fallback TTS for web
          }
          // Fallback to flutterTts for web playback
        } else {
        print('Playing audio using just_audio...');
        // For non-web platforms, play the audio file
        await _audioPlayer.setFilePath(audioPath);
        await _audioPlayer.play();

        // Listen for completion
        _audioPlayer.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            isSpeaking = false;
            notifyListeners();
          }
        });
      }
      } catch (e) {
        print('Error playing audio: $e');
        // Fallback to device TTS
        await _speakWithFallbackTts(text);
      }
    } catch (e) {
      print('Error in Google TTS: $e');
      // Fallback to device TTS
      await _speakWithFallbackTts(text);
    }
  }

  /// Speak using the device's built-in TTS
  Future<void> _speakWithFallbackTts(String text) async {
    print('Using fallback TTS...');
    if (text.isEmpty) return;

    try {
      isSpeaking = true;
      notifyListeners();
      print('Using fallback TTS...');
      await _flutterTts.speak(text);
    } catch (e) {
      isSpeaking = false;
      notifyListeners();
      print('Error in fallback TTS: $e');
    }
  }

  /// Call the Google Cloud TTS API to synthesize speech
  Future<String> _synthesizeSpeech(String text, String textHash) async {
    try {
      // Loading the API key from the .env file
      final String apiKey = dotenv.env['GOOGLE_CLOUD_API_KEY'] ?? '';
      if (apiKey.isEmpty) {
        throw Exception(
            'Google Cloud API key is not set. Please configure it in the .env file.');
      }
      final url =
          'https://texttospeech.googleapis.com/v1/text:synthesize?key=$apiKey';

      // Use the selected voice
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'input': {'text': text},
          'voice': {
            'languageCode': _selectedVoice.languageCode,
            'name': _selectedVoice.name,
            'ssmlGender': _selectedVoice.gender
          },
          'audioConfig': {
            'audioEncoding': 'MP3',
            'speakingRate': 0.9, // Slightly slower for storytelling
            'pitch': 0.0, // Natural pitch
            'volumeGainDb': 1.0 // Slightly louder
          }
        }),
      );
      try {

        if (response.statusCode == 200) {
          // Decode the base64-encoded audio content
          final audioContent = json.decode(response.body)['audioContent'];
          final bytes = base64.decode(audioContent);
          // Save to a temporary file for non-web platforms
          if (kIsWeb) {
            // For web, we save the file to backend
            print('Saving audio to backend...');
            String filename = await _saveToBackend(filename: textHash, bytes: audioContent);
            return filename;
          } else {
            // For non-web platforms, save to a temporary file
            print('Saving audio to temporary file...');
          
          final tempDir = await getTemporaryDirectory();
          final file = File(
              '${tempDir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3');
          await file.writeAsBytes(bytes);

          // Save to persistent cache
          await _saveToCacheStorage(textHash, file.path);

          return file.path;
          }
        } else {
        throw Exception('Failed to synthesize speech: ${response.body}');
        }
        
      } catch (e) {
        // If we can't access the file system (e.g., on web), fall back to device TTS
        print('Error accessing file system: $e');
        throw Exception('File system access error');
      }
    } catch (e) {
      print('Error in _synthesizeSpeech: $e');
      throw e;
    }
  }

  /// Clean up resources
  void dispose() {
    if (!kIsWeb) {
      _flutterTts.stop();
      _audioPlayer.dispose();
    }
  }
}
