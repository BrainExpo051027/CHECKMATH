import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/ai_engine.dart';
import '../core/game_logic.dart';

// ---------------------------------------------------------------------------
// SharedPreferences cache — call initPrefsCache() once at app start
// ---------------------------------------------------------------------------
SharedPreferences? _prefsCache;

/// Must be awaited once in main() before the app runs.
Future<void> initPrefsCache() async {
  _prefsCache = await SharedPreferences.getInstance();
}

/// Returns the cached prefs instance (falls back to a fresh one if needed).
Future<SharedPreferences> _prefs() async {
  return _prefsCache ??= await SharedPreferences.getInstance();
}

// ---------------------------------------------------------------------------
// API base URL resolution
// ---------------------------------------------------------------------------
const String _prefsKeyBaseUrl = 'checkmath_api_base';
const int kDefaultApiPort = 8765;

Future<String> resolveBaseUrl() async {
  final p = await _prefs();
  final custom = p.getString(_prefsKeyBaseUrl);
  if (custom != null && custom.isNotEmpty) return custom;
  if (!kIsWeb) return 'http://127.0.0.1:$kDefaultApiPort';
  return 'http://127.0.0.1:$kDefaultApiPort';
}

Future<void> setApiBaseUrl(String url) async {
  final p = await _prefs();
  await p.setString(_prefsKeyBaseUrl, url);
}

// ---------------------------------------------------------------------------
// In-memory local game store (keyed by gameId)
// ---------------------------------------------------------------------------
final Map<String, GameState> _localGames = {};

GameState? getLocalGameState(String gameId) => _localGames[gameId];

// ---------------------------------------------------------------------------
// LOCAL game functions — no network, pure Dart engine
// ---------------------------------------------------------------------------

/// Create a new local game. Returns the same JSON shape as the HTTP backend.
Future<Map<String, dynamic>> localStartGame({
  required String difficulty,
  String? username,
  String gameMode = 'vs_ai',
  String? opponentName,
  String startingTurn = 'human',
}) async {
  final gameId = _uuid();
  final state = GameState(
    board: initialBoard(),
    currentTurn: startingTurn,
    humanScore: 0.0,
    aiScore: 0.0,
    difficulty: difficulty,
    gameId: gameId,
    gameMode: gameMode,
    player1Name: username ?? 'Player 1',
    player2Name: gameMode == 'local_pvp'
        ? (opponentName ?? 'Player 2')
        : 'Bot ($difficulty)',
  );
  _localGames[gameId] = state;
  return state.toResponseMap();
}

/// Apply a human (or PvP second-player) move locally.
Future<Map<String, dynamic>> localSendMove(Map<String, dynamic> moveData) async {
  final gameId = moveData['game_id'] as String;
  final state = _localGames[gameId];
  if (state == null || state.gameOver) {
    throw ApiException(400, 'Invalid or finished game');
  }

  final fr = moveData['from_row'] as int;
  final fc = moveData['from_col'] as int;
  final tr = moveData['to_row'] as int;
  final tc = moveData['to_col'] as int;

  // In PvP mode, the "human" flag tracks whose turn it actually is
  final isHumanTurn = state.currentTurn == 'human';
  final (ok, msg) = applyMove(state, fr, fc, tr, tc, isHumanTurn);
  if (!ok) throw ApiException(400, '{"detail":"$msg"}');

  checkGameEnd(state);
  final map = state.toResponseMap();
  map['last_bot_move'] = null;
  return map;
}

/// Run the AI move locally (for vs_ai mode).
Future<Map<String, dynamic>> localBotMove(String gameId) async {
  final state = _localGames[gameId];
  if (state == null || state.gameOver) {
    throw ApiException(400, 'Invalid or finished game');
  }

  Map<String, dynamic>? move;

  if (state.difficulty == 'hard') {
    // Run minimax in an isolate so the UI stays responsive
    move = await computeAiMove(state);
  } else {
    // Easy / medium are fast — run inline
    move = getAiMove(state);
  }

  if (move == null) {
    checkGameEnd(state);
    return state.toResponseMap();
  }

  final fr = (move['from'] as List)[0] as int;
  final fc = (move['from'] as List)[1] as int;
  final tr = (move['to'] as List)[0] as int;
  final tc = (move['to'] as List)[1] as int;

  applyMove(state, fr, fc, tr, tc, false);

  // Handle chain captures for the AI
  while (state.lastCapture &&
      state.currentTurn == 'ai' &&
      !state.gameOver) {
    final nextMove = getAiMove(state); // greedy continuation
    if (nextMove == null) break;
    final nfr = (nextMove['from'] as List)[0] as int;
    final nfc = (nextMove['from'] as List)[1] as int;
    final ntr = (nextMove['to'] as List)[0] as int;
    final ntc = (nextMove['to'] as List)[1] as int;
    final (ok, _) = applyMove(state, nfr, nfc, ntr, ntc, false);
    if (!ok) break;
  }

  checkGameEnd(state);

  final map = state.toResponseMap();
  map['last_bot_move'] = {
    'from': [fr, fc],
    'to': [tr, tc],
  };
  return map;
}

// ---------------------------------------------------------------------------
// HTTP game functions (unchanged — used for cross-device PvP)
// ---------------------------------------------------------------------------
Future<Map<String, dynamic>> startGame({
  required String difficulty,
  String? username,
  String gameMode = 'vs_ai',
  String? opponentName,
}) async {
  final base = await resolveBaseUrl();
  final uri = Uri.parse('$base/start-game');
  final body = <String, dynamic>{
    'difficulty': difficulty,
    'game_mode': gameMode,
  };
  if (username != null) body['username'] = username;
  if (opponentName != null) body['opponent_name'] = opponentName;
  final response = await http.post(
    uri,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(body),
  );
  if (response.statusCode >= 400) {
    throw ApiException(response.statusCode, response.body);
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> sendMove(Map<String, dynamic> moveData) async {
  final base = await resolveBaseUrl();
  final uri = Uri.parse('$base/move');
  final response = await http.post(
    uri,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(moveData),
  );
  if (response.statusCode >= 400) {
    throw ApiException(response.statusCode, response.body);
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> triggerBotMove(String gameId) async {
  final base = await resolveBaseUrl();
  final uri = Uri.parse('$base/bot-move');
  final response = await http.post(
    uri,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'game_id': gameId}),
  );
  if (response.statusCode >= 400) {
    throw ApiException(response.statusCode, response.body);
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> getGameState(String gameId) async {
  final base = await resolveBaseUrl();
  final uri =
      Uri.parse('$base/game-state').replace(queryParameters: {'game_id': gameId});
  final response = await http.get(uri);
  if (response.statusCode >= 400) {
    throw ApiException(response.statusCode, response.body);
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> resolveUser(String username) async {
  final base = await resolveBaseUrl();
  final uri = Uri.parse('$base/resolve-user')
      .replace(queryParameters: {'username': username});
  final response = await http.get(uri);
  if (response.statusCode >= 400) {
    throw ApiException(response.statusCode, response.body);
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> getLeaderboard() async {
  final base = await resolveBaseUrl();
  final uri = Uri.parse('$base/leaderboard');
  final response = await http.get(uri);
  if (response.statusCode >= 400) {
    throw ApiException(response.statusCode, response.body);
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> updateScore({
  required String username,
  required String result,
  required int score,
}) async {
  final base = await resolveBaseUrl();
  final uri = Uri.parse('$base/update-score');
  final response = await http.post(
    uri,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'username': username, 'result': result, 'score': score}),
  );
  if (response.statusCode >= 400) {
    throw ApiException(response.statusCode, response.body);
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> getAchievements(int userId) async {
  final base = await resolveBaseUrl();
  final uri = Uri.parse('$base/achievements')
      .replace(queryParameters: {'user_id': '$userId'});
  final response = await http.get(uri);
  if (response.statusCode >= 400) {
    throw ApiException(response.statusCode, response.body);
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}

// ---------------------------------------------------------------------------
// Auth API
// ---------------------------------------------------------------------------
Future<Map<String, dynamic>> register(String username, String password) async {
  final base = await resolveBaseUrl();
  final uri = Uri.parse('$base/register');
  final response = await http.post(
    uri,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'username': username, 'password': password}),
  );
  if (response.statusCode >= 400) {
    throw ApiException(response.statusCode, response.body);
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> login(String username, String password) async {
  final base = await resolveBaseUrl();
  final uri = Uri.parse('$base/login');
  final response = await http.post(
    uri,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'username': username, 'password': password}),
  );
  if (response.statusCode >= 400) {
    throw ApiException(response.statusCode, response.body);
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> updateUsername(int userId, String newUsername) async {
  final base = await resolveBaseUrl();
  final uri = Uri.parse('$base/update-username');
  final response = await http.post(
    uri,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'user_id': userId, 'new_username': newUsername}),
  );
  if (response.statusCode >= 400) {
    throw ApiException(response.statusCode, response.body);
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> fetchProfile(int userId) async {
  final base = await resolveBaseUrl();
  final uri = Uri.parse('$base/profile')
      .replace(queryParameters: {'user_id': '$userId'});
  final response = await http.get(uri);
  if (response.statusCode >= 400) {
    throw ApiException(response.statusCode, response.body);
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}

// ---------------------------------------------------------------------------
// WebSocket Multiplayer
// ---------------------------------------------------------------------------
class MultiplayerClient {
  WebSocketChannel? _channel;
  String? roomCode;
  String? role;

  void Function(Map<String, dynamic>)? onMessage;
  void Function()? onDisconnect;

  Future<void> connect(String wsUrl, String code) async {
    roomCode = code;
    final url = '$wsUrl/ws/matchmaking/$code';
    _channel = WebSocketChannel.connect(Uri.parse(url));
    _channel!.stream.listen(
      (data) {
        final msg = jsonDecode(data as String) as Map<String, dynamic>;
        if (msg['type'] == 'joined') {
          role = msg['role'] as String?;
        }
        onMessage?.call(msg);
      },
      onDone: () => onDisconnect?.call(),
      onError: (_) => onDisconnect?.call(),
    );
  }

  /// Connect using a pre-built full URL (e.g. with query parameters).
  Future<void> connectRaw(String fullUrl) async {
    _channel = WebSocketChannel.connect(Uri.parse(fullUrl));
    _channel!.stream.listen(
      (data) {
        final msg = jsonDecode(data as String) as Map<String, dynamic>;
        if (msg['type'] == 'joined') {
          role = msg['role'] as String?;
        }
        onMessage?.call(msg);
      },
      onDone: () => onDisconnect?.call(),
      onError: (_) => onDisconnect?.call(),
    );
  }

  void send(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  void close() {
    _channel?.sink.close();
    _channel = null;
  }

  bool get isHost => role == 'host';
  bool get isConnected => _channel != null;
}

Future<String> resolveWsUrl() async {
  final base = await resolveBaseUrl();
  // Convert http(s) to ws(s)
  if (base.startsWith('https://')) {
    return base.replaceFirst('https://', 'wss://');
  }
  return base.replaceFirst('http://', 'ws://');
}

// ---------------------------------------------------------------------------
// LOCAL Leaderboard (SharedPreferences)
// ---------------------------------------------------------------------------
const String _localLeaderboardKey = 'checkmath_local_leaderboard';

Future<List<Map<String, dynamic>>> getLocalLeaderboard() async {
  final p = await _prefs();
  final raw = p.getString(_localLeaderboardKey);
  if (raw == null || raw.isEmpty) return [];
  final list = jsonDecode(raw) as List;
  return list.cast<Map<String, dynamic>>();
}

Future<void> updateLocalUsername(String oldName, String newName) async {
  final p = await _prefs();
  
  // Update Leaderboard
  final raw = p.getString(_localLeaderboardKey);
  if (raw != null && raw.isNotEmpty) {
    final list = jsonDecode(raw) as List;
    final records = list.cast<Map<String, dynamic>>();
    for (var r in records) {
      if (r['username'] == oldName) {
        r['username'] = newName;
      }
    }
    await p.setString(_localLeaderboardKey, jsonEncode(records));
  }
  
  // Update achievements key
  final oldAchievKey = _localAchievKey(oldName);
  final newAchievKey = _localAchievKey(newName);
  final achRaw = p.getString(oldAchievKey);
  if (achRaw != null) {
    await p.setString(newAchievKey, achRaw);
    await p.remove(oldAchievKey);
  }
}

/// Save a local score and return the updated record for this user so callers
/// can pass the stats directly to [checkAndUnlockAchievements].
Future<Map<String, dynamic>> saveLocalScore({
  required String username,
  required String result, // 'win' | 'loss' | 'draw'
  required double score,
}) async {
  final p = await _prefs();
  final raw = p.getString(_localLeaderboardKey);
  final List list =
      raw != null && raw.isNotEmpty ? jsonDecode(raw) as List : [];

  final records = list.cast<Map<String, dynamic>>();
  final idx = records.indexWhere((r) => r['username'] == username);

  Map<String, dynamic> rec;
  if (idx == -1) {
    rec = {
      'username': username,
      'total_score': score,
      'wins': result == 'win' ? 1 : 0,
      'losses': result == 'loss' ? 1 : 0,
      'draws': result == 'draw' ? 1 : 0,
      'games': 1,
    };
    records.add(rec);
  } else {
    rec = Map<String, dynamic>.from(records[idx]);
    rec['total_score'] = ((rec['total_score'] as num).toDouble() + score);
    rec['wins'] = (rec['wins'] as int) + (result == 'win' ? 1 : 0);
    rec['losses'] = (rec['losses'] as int) + (result == 'loss' ? 1 : 0);
    rec['draws'] = (rec['draws'] as int) + (result == 'draw' ? 1 : 0);
    rec['games'] = ((rec['games'] as int?) ?? 0) + 1;
    records[idx] = rec;
  }

  // Sort by total_score descending
  records.sort((a, b) =>
      (b['total_score'] as num).compareTo(a['total_score'] as num));

  await p.setString(_localLeaderboardKey, jsonEncode(records));
  return rec;
}

// ---------------------------------------------------------------------------
// LOCAL Achievements (SharedPreferences)
// ---------------------------------------------------------------------------
const _allLocalAchievements = [
  {
    'id': 'first_win',
    'title': 'First Victory',
    'desc': 'Win your first local game',
    'icon': 'military_tech',
  },
  {
    'id': 'hat_trick',
    'title': 'Hat Trick',
    'desc': 'Win 3 local games',
    'icon': 'local_fire_department',
  },
  {
    'id': 'math_master',
    'title': 'Math Master',
    'desc': 'Accumulate 100+ total score locally',
    'icon': 'calculate',
  },
  {
    'id': 'unbeatable',
    'title': 'Unbeatable',
    'desc': 'Win 10 local games',
    'icon': 'emoji_events',
  },
  {
    'id': 'hard_winner',
    'title': 'Hard Knockout',
    'desc': 'Beat the Hard AI bot',
    'icon': 'smart_toy',
  },
];

String _localAchievKey(String username) =>
    'checkmath_achievements_${username.toLowerCase()}';

Future<List<Map<String, dynamic>>> getLocalAchievements(String username) async {
  final p = await _prefs();
  final raw = p.getString(_localAchievKey(username));
  final Map<String, bool> unlocked =
      raw != null && raw.isNotEmpty
          ? Map<String, bool>.from(
              (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, v as bool)))
          : {};

  return _allLocalAchievements.map((a) {
    return {
      'title': a['title'],
      'desc': a['desc'],
      'icon': a['icon'],
      'unlocked': unlocked[a['id']] ?? false,
    };
  }).toList();
}

/// Call this after a game ends to unlock any newly earned achievements.
/// Pass [updatedRecord] (the return value of saveLocalScore) to avoid a
/// redundant disk read — the stats are already in memory.
/// Returns the list of newly unlocked achievement titles.
Future<List<String>> checkAndUnlockAchievements({
  required String username,
  required String result, // 'win' | 'loss' | 'draw'
  required double score,
  required String difficulty,
  Map<String, dynamic>? updatedRecord, // pre-read stats from saveLocalScore
}) async {
  final p = await _prefs();
  final key = _localAchievKey(username);
  final raw = p.getString(key);
  final Map<String, bool> unlocked =
      raw != null && raw.isNotEmpty
          ? Map<String, bool>.from(
              (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, v as bool)))
          : {};

  // Use passed-in stats if available (avoids extra disk read)
  final int wins;
  final double totalScore;
  if (updatedRecord != null) {
    wins = (updatedRecord['wins'] as int?) ?? 0;
    totalScore = (updatedRecord['total_score'] as num?)?.toDouble() ?? 0.0;
  } else {
    final records = await getLocalLeaderboard();
    final rec = records.firstWhere(
      (r) => r['username'] == username,
      orElse: () => {'wins': 0, 'total_score': 0.0},
    );
    wins = (rec['wins'] as int?) ?? 0;
    totalScore = (rec['total_score'] as num?)?.toDouble() ?? 0.0;
  }

  final newlyUnlocked = <String>[];

  void tryUnlock(String id, String title, bool condition) {
    if (condition && !(unlocked[id] ?? false)) {
      unlocked[id] = true;
      newlyUnlocked.add(title);
    }
  }

  tryUnlock('first_win', 'First Victory', wins >= 1);
  tryUnlock('hat_trick', 'Hat Trick', wins >= 3);
  tryUnlock('math_master', 'Math Master', totalScore >= 100);
  tryUnlock('unbeatable', 'Unbeatable', wins >= 10);
  tryUnlock(
    'hard_winner',
    'Hard Knockout',
    result == 'win' && difficulty == 'hard',
  );

  await p.setString(key, jsonEncode(unlocked));
  return newlyUnlocked;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
String _uuid() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int b) => b.toRadixString(16).padLeft(2, '0');
  final h = bytes.map(hex).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
      '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  String toString() => 'ApiException($statusCode): $body';
}
