import 'dart:developer' as developer;
import 'package:audioplayers/audioplayers.dart';

/// Improved helper to play short asset sounds for success/error feedback.
///
/// This class uses low-latency players for short UI sounds, performs a
/// lazy initialization and attempts to preload the asset variants
/// (e.g. `ok.mp3` and `ok.MP3`) to reduce runtime latency. It also logs
/// errors to help debugging when playback silently fails.
class SoundPlayer {
  // Use default constructor to remain compatible across platforms/versions.
  static final AudioPlayer _successPlayer = AudioPlayer();
  static final AudioPlayer _errorPlayer = AudioPlayer();
  static final AudioPlayer _closeBoxPlayer = AudioPlayer();
  static bool _initialized = false;

  static const String _okLower = 'sounds/ok.mp3';
  static const String _okUpper = 'sounds/ok.MP3';
  static const String _err = 'sounds/error.mp3';
  static const String _closeBox = 'sounds/close_box.mp3';

  /// Ensure players are configured and attempt to preload assets once.
  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      // Attempt to set sensible defaults
      try {
        await _successPlayer.setVolume(1.0);
      } catch (e) {
        developer.log(
          'SoundPlayer: failed to set success player volume: $e',
          name: 'SoundPlayer',
        );
      }
      try {
        await _errorPlayer.setVolume(1.0);
      } catch (e) {
        developer.log(
          'SoundPlayer: failed to set error player volume: $e',
          name: 'SoundPlayer',
        );
      }
      try {
        await _closeBoxPlayer.setVolume(1.0);
      } catch (e) {
        developer.log(
          'SoundPlayer: failed to set close-box player volume: $e',
          name: 'SoundPlayer',
        );
      }

      // Try preloading the success sound (prefer lowercase, fallback to provided uppercase file)
      try {
        await _successPlayer.setSource(AssetSource(_okLower));
        developer.log('SoundPlayer: preloaded $_okLower', name: 'SoundPlayer');
      } catch (_) {
        try {
          await _successPlayer.setSource(AssetSource(_okUpper));
          developer.log(
            'SoundPlayer: preloaded $_okUpper',
            name: 'SoundPlayer',
          );
        } catch (e) {
          developer.log(
            'SoundPlayer: could not preload success sound: $e',
            name: 'SoundPlayer',
          );
        }
      }

      // Preload error sound
      try {
        await _errorPlayer.setSource(AssetSource(_err));
        developer.log('SoundPlayer: preloaded $_err', name: 'SoundPlayer');
      } catch (e) {
        developer.log(
          'SoundPlayer: could not preload error sound: $e',
          name: 'SoundPlayer',
        );
      }

      // Preload close box sound
      try {
        await _closeBoxPlayer.setSource(AssetSource(_closeBox));
        developer.log('SoundPlayer: preloaded $_closeBox', name: 'SoundPlayer');
      } catch (e) {
        developer.log(
          'SoundPlayer: could not preload close box sound: $e',
          name: 'SoundPlayer',
        );
      }
    } catch (e) {
      developer.log(
        'SoundPlayer: initialization failed: $e',
        name: 'SoundPlayer',
      );
    } finally {
      _initialized = true;
    }
  }

  /// Play the success sound (ok.mp3/ok.MP3 in assets/sounds/)
  static Future<void> playSuccess() async {
    try {
      await _ensureInitialized();
      try {
        await _successPlayer.play(AssetSource(_okLower));
        return;
      } catch (e) {
        developer.log(
          'SoundPlayer: play lower-case success failed: $e',
          name: 'SoundPlayer',
        );
      }
      try {
        await _successPlayer.play(AssetSource(_okUpper));
        return;
      } catch (e) {
        developer.log(
          'SoundPlayer: play upper-case success failed: $e',
          name: 'SoundPlayer',
        );
      }
    } catch (e) {
      developer.log(
        'SoundPlayer: unexpected error in playSuccess: $e',
        name: 'SoundPlayer',
      );
    }
  }

  /// Play the error sound (error.mp3 in assets/sounds/)
  static Future<void> playError() async {
    try {
      await _ensureInitialized();
      try {
        await _errorPlayer.play(AssetSource(_err));
        return;
      } catch (e) {
        developer.log(
          'SoundPlayer: play error failed: $e',
          name: 'SoundPlayer',
        );
      }
    } catch (e) {
      developer.log(
        'SoundPlayer: unexpected error in playError: $e',
        name: 'SoundPlayer',
      );
    }
  }

  /// Play the close box sound (close_box.mp3 in assets/sounds/)
  static Future<void> playCloseBox() async {
    try {
      await _ensureInitialized();
      try {
        await _closeBoxPlayer.play(AssetSource(_closeBox));
        return;
      } catch (e) {
        developer.log(
          'SoundPlayer: play close box failed: $e',
          name: 'SoundPlayer',
        );
      }
    } catch (e) {
      developer.log(
        'SoundPlayer: unexpected error in playCloseBox: $e',
        name: 'SoundPlayer',
      );
    }
  }

  /// Dispose players if the app needs to clean up.
  static Future<void> dispose() async {
    try {
      await _successPlayer.dispose();
    } catch (e) {
      developer.log(
        'SoundPlayer: dispose success player error: $e',
        name: 'SoundPlayer',
      );
    }
    try {
      await _errorPlayer.dispose();
    } catch (e) {
      developer.log(
        'SoundPlayer: dispose error player error: $e',
        name: 'SoundPlayer',
      );
    }
    try {
      await _closeBoxPlayer.dispose();
    } catch (e) {
      developer.log(
        'SoundPlayer: dispose close box player error: $e',
        name: 'SoundPlayer',
      );
    }
    _initialized = false;
  }
}
