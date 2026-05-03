import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final AudioPlayer _bgmPlayer = AudioPlayer();
  final AudioPlayer _movePlayer = AudioPlayer(playerId: 'sfx_move');
  final AudioPlayer _capturePlayer = AudioPlayer(playerId: 'sfx_capture');
  final AudioPlayer _winPlayer = AudioPlayer(playerId: 'sfx_win');
  final AudioPlayer _losePlayer = AudioPlayer(playerId: 'sfx_lose');

  bool _isBgmMuted = false;
  bool _isSfxMuted = false;
  bool _isInitialized = false;
  bool _isBgmStarted = false;

  bool get isBgmMuted => _isBgmMuted;
  bool get isSfxMuted => _isSfxMuted;

  Future<void> init() async {
    if (_isInitialized) return;
    final prefs = await SharedPreferences.getInstance();
    _isBgmMuted = prefs.getBool('checkmath_is_bgm_muted') ?? false;
    _isSfxMuted = prefs.getBool('checkmath_is_sfx_muted') ?? false;

    await _bgmPlayer.setReleaseMode(ReleaseMode.loop);
    
    _isInitialized = true;
  }

  Future<void> _startBgm() async {
    try {
      // bgm.mp3 is bundled under assets/audio/
      _isBgmStarted = true;
      await _bgmPlayer.play(AssetSource('audio/bgm.mp3'), volume: 0.22);
    } catch (e) {
      // Ignored if file missing or unsupported
    }
  }

  Future<void> ensureBgmPlaying() async {
    if (!_isInitialized) {
      await init();
    }
    if (_isBgmMuted) return;
    if (_isBgmStarted && _bgmPlayer.state == PlayerState.playing) return;
    await _startBgm();
  }

  Future<void> stopBgm() async {
    try {
      _isBgmStarted = false;
      await _bgmPlayer.stop();
    } catch (_) {}
  }

  Future<void> toggleBgmMute() async {
    _isBgmMuted = !_isBgmMuted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('checkmath_is_bgm_muted', _isBgmMuted);

    if (_isBgmMuted) {
      await _bgmPlayer.pause();
    } else {
      await ensureBgmPlaying();
    }
  }

  Future<void> toggleSfxMute() async {
    _isSfxMuted = !_isSfxMuted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('checkmath_is_sfx_muted', _isSfxMuted);
  }

  set isBgmMuted(bool value) {
    if (_isBgmMuted == value) return;
    _isBgmMuted = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('checkmath_is_bgm_muted', _isBgmMuted);
    });
    if (_isBgmMuted) {
      _bgmPlayer.pause();
    } else {
      ensureBgmPlaying();
    }
  }

  set isSfxMuted(bool value) {
    if (_isSfxMuted == value) return;
    _isSfxMuted = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('checkmath_is_sfx_muted', _isSfxMuted);
    });
  }

  Future<void> playMove() async {
    if (_isSfxMuted) return;
    try {
      if (_movePlayer.state == PlayerState.playing) {
        await _movePlayer.stop();
      }
      await _movePlayer.play(AssetSource('audio/move.mp3'), volume: 0.65);
    } catch (_) {}
  }

  Future<void> playCapture() async {
    if (_isSfxMuted) return;
    try {
      if (_capturePlayer.state == PlayerState.playing) {
        await _capturePlayer.stop();
      }
      await _capturePlayer.play(AssetSource('audio/capture.mp3'), volume: 0.75);
    } catch (_) {}
  }

  Future<void> playWin() async {
    if (_isSfxMuted) return;
    try {
      if (_winPlayer.state == PlayerState.playing) {
        await _winPlayer.stop();
      }
      await _winPlayer.play(AssetSource('audio/winner.mp3'), volume: 0.8);
    } catch (_) {}
  }

  Future<void> playLose() async {
    if (_isSfxMuted) return;
    try {
      if (_losePlayer.state == PlayerState.playing) {
        await _losePlayer.stop();
      }
      await _losePlayer.play(AssetSource('audio/lost.mp3'), volume: 0.8);
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _bgmPlayer.dispose();
    } catch (_) {}
    try {
      await _movePlayer.dispose();
    } catch (_) {}
    try {
      await _capturePlayer.dispose();
    } catch (_) {}
    try {
      await _winPlayer.dispose();
    } catch (_) {}
    try {
      await _losePlayer.dispose();
    } catch (_) {}
  }
}
