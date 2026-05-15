import 'dart:developer' as developer;
import 'package:audioplayers/audioplayers.dart';

/// Optimized SoundPlayer for rapid scanning feedback.
/// Uses a small pool of preloaded players to eliminate 'retard' (latency) 
/// and ensure sounds trigger even during high-speed scanning.
class SoundPlayer {
  // Success player pool (to handle rapid scans)
  static final List<AudioPlayer> _successPool = [AudioPlayer(), AudioPlayer()];
  static int _successIndex = 0;

  static final AudioPlayer _errorPlayer = AudioPlayer();
  static final AudioPlayer _boxCompletePlayer = AudioPlayer();
  static final AudioPlayer _finishOrderPlayer = AudioPlayer();
  static bool _initialized = false;
  static bool _initializing = false;

  static const String _okPath = 'sounds/ok.mp3';
  static const String _errPath = 'sounds/error.mp3';
  static const String _boxPath = 'sounds/box_complete.mp3';
  static const String _finishPath = 'sounds/finish_order.mp3';

  /// Preload all players to eliminate runtime loading latency
  static Future<void> _ensureInitialized() async {
    if (_initialized || _initializing) return;
    _initializing = true;
    try {
      for (final p in _successPool) {
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setVolume(1.0);
        await p.setSource(AssetSource(_okPath));
      }
      await _errorPlayer.setPlayerMode(PlayerMode.lowLatency);
      await _errorPlayer.setVolume(1.0);
      await _errorPlayer.setSource(AssetSource(_errPath));
      
      await _boxCompletePlayer.setPlayerMode(PlayerMode.lowLatency);
      await _boxCompletePlayer.setVolume(1.0);
      await _boxCompletePlayer.setSource(AssetSource(_boxPath));
      
      await _finishOrderPlayer.setPlayerMode(PlayerMode.lowLatency);
      await _finishOrderPlayer.setVolume(1.0);
      await _finishOrderPlayer.setSource(AssetSource(_finishPath));
      
      _initialized = true;
      developer.log('SoundPlayer: Preloaded all sounds and set volume successfully.', name: 'SoundPlayer');
    } catch (e) {
      developer.log('SoundPlayer: Preload failed: $e. Falling back to dynamic loading.', name: 'SoundPlayer');
    } finally {
      _initializing = false;
    }
  }

  /// Plays the success sound instantly using a cycling pool of players.
  static Future<void> playSuccess() async {
    try {
      await _ensureInitialized();
      final player = _successPool[_successIndex];
      // Move index for next call
      _successIndex = (_successIndex + 1) % _successPool.length;
      
      // Use play() instead of resume() to ensure it starts correctly every time
      await player.play(AssetSource(_okPath), mode: PlayerMode.lowLatency);
    } catch (e) {
      // Last resort fallback
      try { await AudioPlayer().play(AssetSource(_okPath), mode: PlayerMode.lowLatency); } catch (_) {}
    }
  }

  static Future<void> playError() async {
    try {
      await _ensureInitialized();
      await _errorPlayer.play(AssetSource(_errPath), mode: PlayerMode.lowLatency);
    } catch (_) {
      try { await AudioPlayer().play(AssetSource(_errPath), mode: PlayerMode.lowLatency); } catch (_) {}
    }
  }

  static Future<void> playCloseBox() async {
    await playBoxComplete();
  }

  static Future<void> playBoxComplete() async {
    try {
      await _ensureInitialized();
      await _boxCompletePlayer.play(AssetSource(_boxPath), mode: PlayerMode.lowLatency);
    } catch (e) {
      try { 
        await AudioPlayer().play(AssetSource(_boxPath), mode: PlayerMode.lowLatency); 
      } catch (_) {
        await playSuccess();
      }
    }
  }

  static Future<void> playFinishOrder() async {
    try {
      await _ensureInitialized();
      await _finishOrderPlayer.play(AssetSource(_finishPath), mode: PlayerMode.lowLatency);
    } catch (_) {
      try { await AudioPlayer().play(AssetSource(_finishPath), mode: PlayerMode.lowLatency); } catch (_) {}
    }
  }

  static Future<void> dispose() async {
    for (final p in _successPool) await p.dispose();
    await _errorPlayer.dispose();
    await _boxCompletePlayer.dispose();
    await _finishOrderPlayer.dispose();
    _initialized = false;
  }
}
