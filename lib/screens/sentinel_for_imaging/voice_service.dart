import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';

class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();

  bool _isListening = false;
  bool _isInitialized = false;

  // Stream to notify when wake word is detected or speech is recognized
  final StreamController<String> _speechController =
      StreamController<String>.broadcast();
  Stream<String> get speechStream => _speechController.stream;

  // Stream to notify status changes (listening, speaking, etc.)
  final StreamController<String> _statusController =
      StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  Future<void> init() async {
    if (_isInitialized) return;

    // Request microphone permission
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      _statusController.add('Permission denied');
      return;
    }

    // Initialize TTS
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5);

    // Initialize STT
    try {
      bool available = await _speech.initialize(
        onStatus: (status) {
          print('STT Status: $status');
          _statusController.add(status);
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
            // Auto-restart listening if we are in "wake word mode"
            // For now, we'll handle this in the provider loop
          }
        },
        onError: (errorNotification) {
          print('STT Error: $errorNotification');
          _statusController.add('error: ${errorNotification.errorMsg}');
          _isListening = false;
        },
      );

      if (available) {
        _isInitialized = true;
        _statusController.add('initialized');
      } else {
        _statusController.add('unavailable');
      }
    } catch (e) {
      print('STT Initialization Error: $e');
      _statusController.add('stt_error');
    }
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    print('TTS Speaking: $text');
    await _flutterTts.speak(text);
  }

  Future<void> stopSpeaking() async {
    await _flutterTts.stop();
  }

  void startListening({bool partialResults = false}) {
    if (!_isInitialized || _isListening) return;

    _isListening = true;
    _speech.listen(
      onResult: (result) {
        if (result.finalResult || partialResults) {
          _speechController.add(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: partialResults,
      localeId: "en_US",
      cancelOnError: false,
      listenMode: stt.ListenMode.dictation,
    );
  }

  void stopListening() {
    if (_isListening) {
      _speech.stop();
      _isListening = false;
    }
  }

  bool get isListening => _isListening;
}
