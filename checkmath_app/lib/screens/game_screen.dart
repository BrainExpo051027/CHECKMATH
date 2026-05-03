import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../core/ai_engine.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../widgets/checker_board.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.difficulty,
    required this.username,
    required this.gameMode,
    this.opponentName,
    this.roomCode,
    this.isOnlineHost,
  });

  final String difficulty;
  final String username;
  final String gameMode;
  final String? opponentName;
  final String? roomCode;
  final bool? isOnlineHost;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  String? _gameId;
  List<List<int>> _board = List.generate(8, (_) => List.filled(8, 0));
  String _turn = 'human';
  double _humanScore = 0;
  double _aiScore = 0;
  bool _gameOver = false;
  String? _winner;
  List<int>? _selected;
  bool _loading = true;
  String? _error;
  bool _scoreSubmitted = false;
  late bool _isPvP;
  bool _botThinking = false;
  bool _gameEndShown = false;

  // Last move highlighting
  List<int>? _lastMoveFrom;
  List<int>? _lastMoveTo;

  String _statusMsg = 'Your move';
  bool _playerCaptured = false;
  List<String> _calculations = [];

  // Resolved opponent name (updated from WebSocket messages for online mode)
  late String _opponentName;

  // Pulse animation for active player
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // AI hints (max 3 per AI match)
  int _hintsRemaining = 3;
  bool _hintLoading = false;  // spinner on hint button only
  List<int>? _hintFrom;
  List<int>? _hintTo;

  // Online multiplayer
  MultiplayerClient? _mpClient;
  bool _isOnline = false;
  // Server-confirmed role for this client: 'host' or 'guest'
  String _myOnlineRole = 'guest';
  // Whose turn in online mode: 'host' or 'guest' (set from server state)
  String _onlineWhoseTurn = 'host';
  bool get _isMyTurnOnline {
    if (!_isOnline) return true;
    return _onlineWhoseTurn == _myOnlineRole;
  }

  // Lobby state (online only)
  bool _showLobby = false;          // true while waiting for game to start
  bool _opponentInLobby = false;    // true once opponent connected to room

  // Coin Toss state
  bool _showCoinToss = false;
  String _coinTossPhase = 'choosing'; // 'choosing' | 'spinning' | 'result'
  String? _coinResult;
  String? _coinTossWinner;

  /// True when the game should run entirely on-device (no HTTP).
  bool get _isLocal =>
      widget.gameMode == 'vs_ai' || widget.gameMode == 'local_pvp';

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _isPvP = widget.gameMode == 'local_pvp';
    _isOnline = widget.gameMode == 'online_pvp';
    // Initialise role from the UI flag; will be overridden once WebSocket confirms.
    _myOnlineRole = widget.isOnlineHost == true ? 'host' : 'guest';
    // Initialise opponent name; will be updated when server broadcasts it.
    _opponentName = widget.opponentName ?? (_isOnline ? (_myOnlineRole == 'host' ? 'Guest' : 'Host') : 'Player 2');
    if (widget.gameMode == 'vs_ai') {
      _hintsRemaining = 3;
    }
    _bootstrap();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _mpClient?.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Bootstrap
  // ---------------------------------------------------------------------------
  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
      _gameEndShown = false;
      _scoreSubmitted = false;
      if (_isOnline) {
        // Reset lobby state on each bootstrap (e.g. rematch)
        _showLobby = true;
        _opponentInLobby = false;
        _gameId = null;
        _board = List.generate(8, (_) => List.filled(8, 0));
      }
    });
    try {
      if (_isOnline) {
        try {
          await _connectMultiplayer();
          setState(() => _loading = false);
          return;
        } catch (e) {
          setState(() {
            _error = 'Failed to connect to online match. $e';
            _loading = false;
            _showLobby = false;
          });
          return;
        }
      }

      // For local PvP, trigger coin toss before actually starting the game
      if (_isLocal && _isPvP) {
        setState(() {
          _loading = false;
          _showCoinToss = true;
          _coinTossPhase = 'choosing';
          _coinResult = null;
          _coinTossWinner = null;
          _board = List.generate(8, (_) => List.filled(8, 0));
        });
        return;
      }

      // For vs_ai or HTTP modes, start the game normally
      final data = _isLocal
          ? await localStartGame(
              difficulty: widget.difficulty,
              username: widget.username,
              gameMode: widget.gameMode,
              opponentName: widget.opponentName,
            )
          : await startGame(
              difficulty: widget.difficulty,
              username: widget.username,
              gameMode: widget.gameMode,
              opponentName: widget.opponentName,
            );
      _applyState(data);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _startLocalMatchAfterToss(String st) async {
    setState(() => _loading = true);
    try {
      final data = await localStartGame(
        difficulty: widget.difficulty,
        username: widget.username,
        gameMode: widget.gameMode,
        opponentName: widget.opponentName,
        startingTurn: st,
      );
      _applyState(data);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _connectMultiplayer() async {
    final wsUrl = await resolveWsUrl();
    final code = widget.roomCode ?? _generateRoomCode();
    
    final encodedName = Uri.encodeComponent(widget.username);
    final roleParam = _myOnlineRole == 'host' ? 'host' : 'guest';
    final wsUrlWithName = '$wsUrl/ws/matchmaking/$code?name=$encodedName&role=$roleParam';
    
    _mpClient = MultiplayerClient()
      ..onMessage = _onWsMessage
      ..onDisconnect = () {
        if (mounted) {
          if (_showLobby) {
            // Socket disconnected while still in lobby (e.g. room not found)
            setState(() {
              _showLobby = false;
              _error = 'Connection lost. This usually happens if the room code is invalid, the host left, or there is a network issue (wrong IP address).';
            });
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Disconnected from online match'),
                backgroundColor: Color(0xFF8B3A3A),
              ),
            );
          }
        }
      };
    await _mpClient!.connectRaw(wsUrlWithName);
    // Host always starts
    _onlineWhoseTurn = 'host';
  }

  String _generateRoomCode() {
    final r = Random();
    return List.generate(4, (_) => r.nextInt(10)).join();
  }

  void _onWsMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;

    // ── Server confirms our connection role ──────────────────────────────
    if (type == 'joined') {
      final serverRole = msg['role'] as String?;
      final opponentName = msg['opponent_name'] as String?;
      if (mounted) {
        setState(() {
          if (serverRole != null) _myOnlineRole = serverRole;
          // Guest receives host's name immediately on join
          if (opponentName != null && opponentName.isNotEmpty) {
            _opponentName = opponentName;
            _opponentInLobby = true;  // guest knows host is there
          }
          _showLobby = true;
        });
      }
      return;
    }

    // ── Coin toss sequence ──────────────────────────────────────────────────
    if (type == 'coin_toss_start') {
      if (mounted) {
        setState(() {
          _showLobby = false;
          _showCoinToss = true;
          _coinTossPhase = 'choosing';
          _coinResult = null;
          _coinTossWinner = null;
        });
      }
      return;
    }

    if (type == 'coin_toss_result') {
      final res = msg['result'] as String?;
      final winner = msg['winner'] as String?;
      if (mounted) {
        setState(() {
          _coinTossPhase = 'spinning';
          _coinResult = res;
        });
        // Delay before showing the result to simulate the coin flipping
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              _coinTossPhase = 'result';
              _coinTossWinner = winner;
            });
          }
        });
      }
      return;
    }

    // ── Actual game state from server (game started) ─────────────────────
    if (type == 'state') {
      final whoseTurn = msg['whose_turn'] as String?;
      // Also capture player names if server includes them
      final hostName = msg['host_name'] as String?;
      final guestName = msg['guest_name'] as String?;
      if (mounted) {
        setState(() {
          if (whoseTurn != null) _onlineWhoseTurn = whoseTurn;
          // Update opponent name from server-authoritative data
          if (_myOnlineRole == 'host' && guestName != null && guestName.isNotEmpty) {
            _opponentName = guestName;
          } else if (_myOnlineRole == 'guest' && hostName != null && hostName.isNotEmpty) {
            _opponentName = hostName;
          }
          _showLobby = false;  // game is starting — hide lobby
          _showCoinToss = false; // hide coin toss overlay
        });
      }
      _applyState(msg);

    } else if (type == 'move') {
      // Fallback relay
      final fr = msg['from_row'] as int?;
      final fc = msg['from_col'] as int?;
      final tr = msg['to_row'] as int?;
      final tc = msg['to_col'] as int?;
      if (fr != null && fc != null && tr != null && tc != null && mounted) {
        setState(() {
          _lastMoveFrom = [fr, fc];
          _lastMoveTo = [tr, tc];
        });
      }

    } else if (type == 'error') {
      final errMsg = msg['message'] as String? ?? 'Invalid action';
      
      if (_showLobby) {
        // Error received before game starts (e.g. room full/not found)
        if (mounted) {
          setState(() {
            _showLobby = false;
            _error = errMsg;
            _mpClient?.close();
          });
        }
        return;
      }
      
      if (mounted) {
        setState(() {
          _loading = false;
          _onlineWhoseTurn = _myOnlineRole; // revert optimistic turn swap
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $errMsg'),
            backgroundColor: const Color(0xFF8B3A3A),
            duration: const Duration(seconds: 3),
          ),
        );
      }

    } else if (type == 'opponent_joined') {
      // Host receives this when guest connects to the lobby
      final opponentName = msg['opponent_name'] as String?;
      if (mounted) {
        setState(() {
          _opponentInLobby = true;
          if (opponentName != null && opponentName.isNotEmpty) {
            _opponentName = opponentName;
          }
        });
      }

    } else if (type == 'opponent_left') {
      if (mounted) {
        setState(() => _opponentInLobby = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Opponent left the match'),
            backgroundColor: Color(0xFF8B3A3A),
          ),
        );
      }
    }
  }

  /// Host presses "Start Game" in the lobby.
  void _startOnlineGame() {
    if (!_opponentInLobby || _myOnlineRole != 'host') return;
    _mpClient?.send({'type': 'start'});
  }

  void _sendMoveWs(int fromRow, int fromCol, int toRow, int toCol) {
    _mpClient?.send({
      'type': 'move',
      'game_id': _gameId,
      'from_row': fromRow,
      'from_col': fromCol,
      'to_row': toRow,
      'to_col': toCol,
    });
  }

  // ---------------------------------------------------------------------------
  // State application
  // ---------------------------------------------------------------------------
  Future<void> _useHint() async {
    if (_hintLoading || _hintsRemaining <= 0 || _gameOver ||
        _turn != 'human' || widget.gameMode != 'vs_ai') { return; }

    final state = getLocalGameState(_gameId!);
    if (state == null) { return; }

    setState(() => _hintLoading = true);
    try {
      // Run minimax for the human player in a background isolate
      final hintMove = await computeBestHumanMove(state);

      if (hintMove != null && mounted) {
        final fr = (hintMove['from'] as List)[0] as int;
        final fc = (hintMove['from'] as List)[1] as int;
        final tr = (hintMove['to'] as List)[0] as int;
        final tc = (hintMove['to'] as List)[1] as int;
        final reason = hintMove['reason'] as String? ?? 'This is an optimal move.';
        
        setState(() {
          _hintsRemaining--;
          _hintFrom = [fr, fc];
          _hintTo = [tr, tc];
        });

        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.lightbulb, color: Color(0xFFEBC134), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    reason,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF262421),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFEBC134), width: 1.5),
            ),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Clear highlight after 4 seconds
        await Future.delayed(const Duration(seconds: 4));
        if (mounted) {
          setState(() {
            _hintFrom = null;
            _hintTo = null;
          });
        }
      }
    } catch (e) {
      debugPrint('Hint error: $e');
    } finally {
      if (mounted) setState(() => _hintLoading = false);
    }
  }

  void _applyState(Map<String, dynamic> data) {
    final raw = data['board'];
    final board = <List<int>>[];
    if (raw is List) {
      for (final row in raw) {
        board.add(List<int>.from((row as List).map((e) => (e as num).toInt())));
      }
    }
    setState(() {
      _gameId = data['game_id'] as String? ?? _gameId;
      if (board.length == 8) _board = board;

      final ct = data['current_turn'] as String? ?? _turn;
      _turn = ct;

      // For online mode, prefer the server-broadcast whose_turn field.
      // If missing, derive it from current_turn as a fallback.
      if (_isOnline) {
        final wt = data['whose_turn'] as String?;
        if (wt != null) {
          _onlineWhoseTurn = wt;
        } else {
          // Fallback: 'human' = host's turn, 'ai' = guest's turn
          _onlineWhoseTurn = ct == 'human' ? 'host' : 'guest';
        }
      }

      if (_isOnline && _myOnlineRole == 'guest') {
        _humanScore = (data['ai_score'] as num?)?.toDouble() ?? _humanScore;
        _aiScore = (data['human_score'] as num?)?.toDouble() ?? _aiScore;
      } else {
        _humanScore = (data['human_score'] as num?)?.toDouble() ?? _humanScore;
        _aiScore = (data['ai_score'] as num?)?.toDouble() ?? _aiScore;
      }
      _gameOver = data['game_over'] as bool? ?? false;

      // Interpret winner from each player's perspective.
      // host controls human pieces (type 1/2); guest controls ai pieces (type 3/4).
      if (_isOnline && data['winner'] != null) {
        final winner = data['winner'] as String;
        if (_myOnlineRole == 'host') {
          // Host wins when 'human' wins
          _winner = winner == 'human' ? 'human' : (winner == 'ai' ? 'ai' : null);
        } else {
          // Guest wins when 'ai' wins (guest plays the ai-piece side)
          _winner = winner == 'ai' ? 'human' : (winner == 'human' ? 'ai' : null);
        }
      } else {
        _winner = data['winner'] as String?;
      }

      _playerCaptured = data['player_captured'] == true;
      _calculations = (data['calculations'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      _loading = false;
    });

    if (_gameOver) {
      _finalizeGameEnd();
    } else {
      _updateStatusMsg();
      // Only trigger bot in vs_ai mode
      if (!_isPvP && !_isOnline && _turn == 'ai' && !_botThinking) {
        _runBotSequence();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Bot sequence
  // ---------------------------------------------------------------------------
  Future<void> _runBotSequence() async {
    if (_botThinking || _gameOver || _isPvP) return;
    if (!mounted) return;

    setState(() {
      _botThinking = true;
      _loading = true;
    });

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    try {
      final res = _isLocal
          ? await localBotMove(_gameId!)
          : await triggerBotMove(_gameId!);
      if (!mounted) return;

      if (res['last_bot_move'] != null) {
        final fromArr = res['last_bot_move']['from'] as List;
        final toArr = res['last_bot_move']['to'] as List;
        setState(() {
          _lastMoveFrom = [fromArr[0] as int, fromArr[1] as int];
          _lastMoveTo = [toArr[0] as int, toArr[1] as int];
        });
      }

      setState(() => _botThinking = false);
      _applyState(res);
    } catch (e) {
      setState(() {
        _botThinking = false;
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bot error: ${_extractMessage(e.toString())}'),
            backgroundColor: const Color(0xFF8B3A3A),
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Status message
  // ---------------------------------------------------------------------------
  void _updateStatusMsg() {
    if (_gameOver) return;
    if (_isOnline) {
      if (_isMyTurnOnline) {
        _statusMsg = '${widget.username}\'s turn — select a piece.';
      } else {
        _statusMsg = '⏳ Waiting for $_opponentName…';
      }
      return;
    }
    if (_turn == 'human') {
      _statusMsg = _playerCaptured
          ? '🎯 Great capture! Keep going.'
          : '${widget.username}\'s turn — select a piece.';
    } else {
      if (_isPvP) {
        _statusMsg = _playerCaptured
            ? '🎯 Great capture! Keep going.'
            : '$_opponentName\'s turn — select a piece.';
      } else {
        _statusMsg = '🤖 AI is thinking…';
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Game end: score save + popup
  // ---------------------------------------------------------------------------
  Future<void> _finalizeGameEnd() async {
    if (_scoreSubmitted) return;
    _scoreSubmitted = true;

    // Play win/lose sound effect
    if (_winner == 'human') {
      AudioService().playWin();
    } else if (_winner == 'ai') {
      AudioService().playLose();
    }

    setState(() {
      if (_winner == 'human') {
        _statusMsg = '🏆 ${widget.username} wins! Outstanding!';
      } else if (_winner == 'ai') {
        _statusMsg =
            _isPvP || _isOnline ? '🏆 $_opponentName wins!' : '💀 Bot wins this round.';
      } else {
        _statusMsg = '🤝 It\'s a draw!';
      }
    });

    final name = widget.username.trim();
    final result = _winner == 'human'
        ? 'win'
        : _winner == 'ai'
            ? 'loss'
            : 'draw';

    // Save local score + check achievements (always offline-safe)
    if (name.isNotEmpty) {
      try {
        // saveLocalScore returns the updated record — pass it to avoid a
        // second SharedPreferences read inside checkAndUnlockAchievements
        final updatedRecord = await saveLocalScore(
          username: name,
          result: result,
          score: _humanScore,
        );
        await checkAndUnlockAchievements(
          username: name,
          result: result,
          score: _humanScore,
          difficulty: widget.difficulty,
          updatedRecord: updatedRecord,
        );
      } catch (_) {}
    }

    // Try to also sync to backend (silently ignore failure)
    if (name.isNotEmpty) {
      try {
        final res = await updateScore(
          username: name,
          result: result,
          score: _humanScore.round().clamp(0, 1 << 30),
        );
        final uid = res['user_id'];
        if (uid is num) {
          final p = await SharedPreferences.getInstance();
          await p.setInt('checkmath_user_id', uid.toInt());
        }
      } catch (_) {/* offline — score saved locally */}
    }

    // Show the game-end popup (delayed slightly so the UI settles)
    if (mounted && !_gameEndShown) {
      _gameEndShown = true;
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) _showGameEndDialog();
    }
  }

  // ---------------------------------------------------------------------------
  // Game-end popup
  // ---------------------------------------------------------------------------
  void _showGameEndDialog() {
    final isWin = _winner == 'human';
    final isDraw = _winner == null || _winner == 'draw';

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF262421),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDraw
                  ? const Color(0xFF3E3B37)
                  : isWin
                      ? const Color(0xFF739552)
                      : const Color(0xFF8B3A3A),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 32,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                decoration: BoxDecoration(
                  color: isDraw
                      ? const Color(0xFF3B3B3B)
                      : isWin
                          ? const Color(0xFF2D4A1E)
                          : const Color(0xFF4A1E1E),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                ),
                child: Column(
                  children: [
                    Text(
                      isDraw ? '🤝' : isWin ? '🏆' : '💀',
                      style: const TextStyle(fontSize: 44),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _statusMsg,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDraw
                            ? const Color(0xFFD4D4D4)
                            : isWin
                                ? const Color(0xFF9FCE6C)
                                : const Color(0xFFD4574B),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Score summary
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Row(
                  children: [
                    _scoreCard(
                      widget.username,
                      _humanScore,
                      isWinner: _winner == 'human',
                      isHuman: true,
                    ),
                    const SizedBox(width: 12),
                    _scoreCard(
                      _isPvP || _isOnline
                          ? _opponentName
                          : 'Bot (${widget.difficulty})',
                      _aiScore,
                      isWinner: _winner == 'ai',
                      isHuman: false,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Calculation log
              if (_calculations.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: const Text(
                      'CALCULATION LOG',
                      style: TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  height: 160,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1C1A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF3E3B37)),
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: _calculations.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        _calculations[i],
                        style: const TextStyle(
                          color: Color(0xFF9FCE6C),
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ),
              ],

              // Buttons
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    if (!_isOnline) ...[
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF888888),
                            side: const BorderSide(color: Color(0xFF3E3B37)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _bootstrap();
                          },
                          child: const Text('🔄 Rematch'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF739552),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          Navigator.of(context).pop();
                        },
                        child: const Text('🏠 Menu'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scoreCard(
    String name,
    double score, {
    required bool isWinner,
    required bool isHuman,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: isWinner
              ? const Color(0xFF739552).withValues(alpha: 0.15)
              : const Color(0xFF302E2B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isWinner
                ? const Color(0xFF739552).withValues(alpha: 0.5)
                : const Color(0xFF3E3B37),
          ),
        ),
        child: Column(
          children: [
            Icon(
              isHuman ? Icons.person : Icons.smart_toy,
              color: isWinner
                  ? const Color(0xFF9FCE6C)
                  : const Color(0xFF888888),
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              name,
              style: TextStyle(
                color: isWinner
                    ? const Color(0xFFD4D4D4)
                    : const Color(0xFF888888),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              score.toStringAsFixed(1),
              style: TextStyle(
                color: isWinner
                    ? const Color(0xFF9FCE6C)
                    : const Color(0xFF666666),
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'pts',
              style: TextStyle(
                color: isWinner
                    ? const Color(0xFF739552)
                    : const Color(0xFF555555),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Cell tap handler
  // ---------------------------------------------------------------------------
  Future<void> _onCell(int row, int col) async {
    if (_loading || _gameOver || _gameId == null) return;
    if (!_isPvP && !_isOnline && _turn != 'human') return;
    if (_isOnline && !_isMyTurnOnline) return;

    final p = _board[row][col];
    final type = p > 0 ? p ~/ 100 : 0;

    // Piece ownership:
    //   Host  → controls human pieces (type 1=man, 2=king)
    //   Guest → controls AI pieces    (type 3=man, 4=king)
    //   Local PvP → whoever's turn it is
    final p1Piece = type == 1 || type == 2; // human-coded pieces
    final p2Piece = type == 3 || type == 4; // ai-coded pieces

    final bool isMyPiece;
    if (_isOnline) {
      // Use server-confirmed role, not the static UI flag
      isMyPiece = _myOnlineRole == 'host' ? p1Piece : p2Piece;
    } else if (_isPvP) {
      isMyPiece = _turn == 'human' ? p1Piece : p2Piece;
    } else {
      isMyPiece = _turn == 'human' ? p1Piece : p2Piece;
    }

    if (_selected == null) {
      if (!isMyPiece) return;
      setState(() => _selected = [row, col]);
      return;
    }

    if (_selected![0] == row && _selected![1] == col) {
      setState(() => _selected = null);
      return;
    }

    // Re-select another of own pieces
    if (isMyPiece) {
      setState(() => _selected = [row, col]);
      return;
    }

    final fromRow = _selected![0];
    final fromCol = _selected![1];

    setState(() => _loading = true);
    try {
      final prevCapturedFlag = _playerCaptured;
      final moveData = {
        'game_id': _gameId,
        'from_row': fromRow,
        'from_col': fromCol,
        'to_row': row,
        'to_col': col,
      };

      if (_isOnline) {
        // Send move over WebSocket; server validates and broadcasts updated state
        _sendMoveWs(fromRow, fromCol, row, col);
        setState(() {
          _lastMoveFrom = [fromRow, fromCol];
          _lastMoveTo = [row, col];
          _selected = null;
          _loading = false;
          // Optimistically assume it's now opponent's turn until server confirms
          _onlineWhoseTurn = _myOnlineRole == 'host' ? 'guest' : 'host';
        });
        return;
      }

      final res = _isLocal
          ? await localSendMove(moveData)
          : await sendMove(moveData);

      setState(() {
        _lastMoveFrom = [fromRow, fromCol];
        _lastMoveTo = [row, col];
        _selected = null;
      });
      _applyState(res);

      // Play SFX after applying the new state.
      // Prefer server/game-logic authoritative capture flag.
      final didCapture = (res['player_captured'] == true) || prevCapturedFlag;
      if (didCapture) {
        AudioService().playCapture();
      } else {
        AudioService().playMove();
      }
    } catch (e) {
      setState(() => _loading = false);
      try {
        final canVibrate = await Vibration.hasVibrator() ?? false;
        if (canVibrate) {
          await Vibration.vibrate(duration: 200);
        } else {
          HapticFeedback.mediumImpact();
        }
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid move: ${_extractMessage(e.toString())}'),
            duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFF8B3A3A),
          ),
        );
        setState(() => _selected = null);
      }
    }
  }

  String _extractMessage(String err) {
    if (err.contains('detail')) {
      final start = err.indexOf('"detail":');
      if (start != -1) {
        final sub = err.substring(start + 10);
        final end = sub.indexOf('"');
        final end2 = sub.indexOf('}');
        final cut = end == -1 ? end2 : end;
        if (cut != -1) return sub.substring(0, cut).replaceAll('"', '');
      }
    }
    if (err.contains('Illegal')) return 'Illegal move';
    if (err.contains('capture')) return 'Must continue capture';
    return 'Try another square';
  }

  int _countPieces(bool human) {
    int c = 0;
    for (final row in _board) {
      for (final p in row) {
        if (p == 0) continue;
        final type = p ~/ 100;
        if (human && (type == 1 || type == 2)) c++;
        if (!human && (type == 3 || type == 4)) c++;
      }
    }
    return c;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_error != null && _gameId == null) return _buildErrorScreen();

    // Online lobby — show before game begins
    if (_isOnline && _showLobby && !_loading) {
      return _buildLobbyScreen();
    }

    if (_loading && _gameId == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF302E2B),
        appBar: _buildAppBar(),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF739552)),
              SizedBox(height: 16),
              Text(
                'Setting up the board…',
                style: TextStyle(color: Color(0xFF888888)),
              ),
            ],
          ),
        ),
      );
    }


    final humanPieces = _countPieces(true);
    final aiPieces = _countPieces(false);
    final captured = 12 - aiPieces;
    final lostByHuman = 12 - humanPieces;

    return Scaffold(
      backgroundColor: const Color(0xFF302E2B),
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 700) {
                  return _buildWideLayout(
                      humanPieces, aiPieces, captured, lostByHuman);
                }
                return _buildNarrowLayout(
                    humanPieces, aiPieces, captured, lostByHuman);
              },
            ),
            if (_showCoinToss) _buildCoinTossScreen(),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF262421),
      foregroundColor: const Color(0xFFD4D4D4),
      elevation: 0,
      title: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF739552),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'CheckMath',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(0xFFD4D4D4)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF302E2B),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              widget.difficulty.toUpperCase(),
              style: const TextStyle(fontSize: 10, color: Color(0xFF888888)),
            ),
          ),
          if (_isLocal)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A1E),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'OFFLINE',
                style: TextStyle(
                    fontSize: 9,
                    color: Color(0xFF5C9E3A),
                    fontWeight: FontWeight.bold),
              ),
            )
          else if (_isOnline)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF3A1E3A),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'ONLINE',
                style: TextStyle(
                    fontSize: 9,
                    color: Color(0xFF9E5CA3),
                    fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNarrowLayout(
      int humanPieces, int aiPieces, int captured, int lostByHuman) {
    return Column(
      children: [
        _buildPlayerBar(
            isHuman: false, pieces: aiPieces, capturedByOther: lostByHuman),
        _buildStatusBanner(),
        Expanded(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: CheckerBoard(
                  board: _board,
                  selected: _selected,
                  lastMoveFrom: _lastMoveFrom,
                  lastMoveTo: _lastMoveTo,
                  hintFrom: _hintFrom,
                  hintTo: _hintTo,
                  interactive: !_loading && !_gameOver,
                  isFlipped: _isOnline && _myOnlineRole == 'guest',
                  onCellTap: _onCell,
                ),
              ),
              // Hint button — only shown for vs_ai mode on narrow (mobile) layout
              if (widget.gameMode == 'vs_ai')
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: _buildMobileHintButton(),
                ),
            ],
          ),
        ),
        _buildPlayerBar(
            isHuman: true, pieces: humanPieces, capturedByOther: captured),
      ],
    );
  }

  Widget _buildMobileHintButton() {
    final available = _hintsRemaining > 0 && !_gameOver &&
        _turn == 'human' && !_hintLoading;
    return AnimatedOpacity(
      opacity: available ? 1.0 : 0.45,
      duration: const Duration(milliseconds: 200),
      child: FloatingActionButton.extended(
        heroTag: 'hint_fab',
        onPressed: available ? _useHint : null,
        backgroundColor: available
            ? const Color(0xFF739552)
            : const Color(0xFF3E3B37),
        icon: _hintLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.lightbulb_outline, size: 18, color: Colors.white),
        label: Text(
          _hintLoading ? 'Thinking…' : 'Hint ($_hintsRemaining)',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildWideLayout(
      int humanPieces, int aiPieces, int captured, int lostByHuman) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _buildPlayerBar(
                  isHuman: false,
                  pieces: aiPieces,
                  capturedByOther: lostByHuman),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: CheckerBoard(
                    board: _board,
                    selected: _selected,
                    lastMoveFrom: _lastMoveFrom,
                    lastMoveTo: _lastMoveTo,
                    hintFrom: _hintFrom,
                    hintTo: _hintTo,
                    interactive: !_loading && !_gameOver,
                    isFlipped: _isOnline && _myOnlineRole == 'guest',
                    onCellTap: _onCell,
                  ),
                ),
              ),
              _buildPlayerBar(
                  isHuman: true,
                  pieces: humanPieces,
                  capturedByOther: captured),
            ],
          ),
        ),
        Container(width: 1, color: const Color(0xFF3E3B37)),
        SizedBox(width: 220, child: _buildSidePanel()),
      ],
    );
  }

  Widget _buildPlayerBar({
    required bool isHuman,
    required int pieces,
    required int capturedByOther,
  }) {
    // Resolve player name safely (opponentName may be null)
    final String name;
    if (isHuman) {
      name = widget.username;
    } else if (_isPvP || _isOnline) {
      name = _opponentName;
    } else {
      name = 'Bot (${widget.difficulty})';
    }

    final avatarIcon =
        isHuman ? Icons.person : (_isPvP || _isOnline ? Icons.person_outline : Icons.smart_toy);
    final avatarColor =
        isHuman ? const Color(0xFFEBECD0) : const Color(0xFF2B2B2B);
    final avatarIconColor =
        isHuman ? const Color(0xFF302E2B) : const Color(0xFFD4D4D4);

    // In online mode the bar labelled 'isHuman' is always the local player's bar.
    // Determine if it's the active turn for whoever this bar represents.
    final bool isActive;
    if (_isOnline) {
      // isHuman=true → this is MY (local player's) bar
      // isHuman=false → this is the opponent's bar
      isActive = !_gameOver &&
          (isHuman ? _isMyTurnOnline : !_isMyTurnOnline);
    } else {
      isActive = (_turn == (isHuman ? 'human' : 'ai')) && !_gameOver;
    }

    return Container(
      height: 56,
      color: const Color(0xFF262421),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: const Color(0xFF739552)
                                .withValues(alpha: _pulseAnim.value),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: child,
              );
            },
            child: CircleAvatar(
              radius: 18,
              backgroundColor: avatarColor,
              child: Icon(avatarIcon, color: avatarIconColor, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                      color: Color(0xFFD4D4D4),
                      fontWeight: FontWeight.w600,
                      fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    for (int i = 0; i < capturedByOther.clamp(0, 12); i++)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isHuman
                              ? const Color(0xFF2B2B2B).withValues(alpha: 0.8)
                              : const Color(0xFFF8F8F8).withValues(alpha: 0.8),
                          border: Border.all(
                            color: isHuman
                                ? const Color(0xFF1A1A1A)
                                : const Color(0xFFD4D4D4),
                            width: 0.5,
                          ),
                        ),
                      ),
                    if (capturedByOther == 0)
                      const Text(
                        '0 captured',
                        style:
                            TextStyle(color: Color(0xFF888888), fontSize: 10),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (isActive)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF739552).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color:
                        const Color(0xFF739552).withValues(alpha: 0.5)),
              ),
              child: Text(
                // In online/PvP modes, the active bar always means 'Your turn'
                // or the opponent's turn — use a simple label.
                (_isOnline || _isPvP)
                    ? (isHuman ? 'Your turn' : 'Opponent')
                    : (isHuman ? 'Your turn' : 'Thinking…'),
                style: const TextStyle(
                    color: Color(0xFF739552),
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Score: ${isHuman ? _humanScore.toStringAsFixed(1) : _aiScore.toStringAsFixed(1)}',
                style: const TextStyle(
                    color: Color(0xFF9FCE6C),
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
              Text(
                '✦ $pieces chips',
                style: TextStyle(
                    color: isActive
                        ? const Color(0xFFD4D4D4)
                        : const Color(0xFF666666),
                    fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    if (_gameOver) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: const Color(0xFF302E2B),
      child: Text(
        _statusMsg,
        style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
      ),
    );
  }


  Widget _buildSidePanel() {
    return Container(
      color: const Color(0xFF262421),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'GAME INFO',
            style: TextStyle(
                color: Color(0xFF888888),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2),
          ),
          const SizedBox(height: 16),
          _sideInfoRow('Your Score', _humanScore.toStringAsFixed(1)),
          const SizedBox(height: 8),
          _sideInfoRow(
              _isPvP || _isOnline
                  ? '$_opponentName Score'
                  : 'Bot Score',
              _aiScore.toStringAsFixed(1)),
          const SizedBox(height: 8),
          _sideInfoRow(
            'Turn',
            _isOnline
                ? (_isMyTurnOnline ? widget.username : _opponentName)
                : (_turn == 'human'
                    ? widget.username
                    : (_isPvP ? _opponentName : 'AI Bot')),
          ),
          const SizedBox(height: 8),
          if (!_isPvP && !_isOnline) ...[
            _sideInfoRow('Difficulty', widget.difficulty.toUpperCase()),
            const SizedBox(height: 8),
            if (widget.gameMode == 'vs_ai') ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _hintsRemaining > 0 ? const Color(0xFF739552) : const Color(0xFF555555),
                        side: BorderSide(color: _hintsRemaining > 0 ? const Color(0xFF739552) : const Color(0xFF3E3B37)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: _hintsRemaining > 0 && !_gameOver && _turn == 'human' && !_hintLoading
                          ? _useHint
                          : null,
                      icon: _hintLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF739552),
                              ),
                            )
                          : Icon(
                              Icons.lightbulb_outline,
                              size: 16,
                              color: _hintsRemaining > 0 ? const Color(0xFF739552) : const Color(0xFF555555),
                            ),
                      label: Text(_hintLoading
                          ? 'Thinking…'
                          : 'Hint ($_hintsRemaining left)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            const Divider(color: Color(0xFF3E3B37), height: 32),
          ] else ...[
            const Divider(color: Color(0xFF3E3B37), height: 32),
          ],
          const Text(
            'CALCULATION LOG',
            style: TextStyle(
                color: Color(0xFF888888),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1C1A),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF3E3B37)),
              ),
              child: _calculations.isEmpty
                  ? const Center(
                      child: Text(
                        'No captures yet',
                        style: TextStyle(
                            color: Color(0xFF555555), fontSize: 12),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _calculations.length,
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          _calculations[i],
                          style: const TextStyle(
                              color: Color(0xFF9FCE6C),
                              fontSize: 12,
                              fontFamily: 'monospace'),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          _buildStatusBanner(),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF888888),
                side: const BorderSide(color: Color(0xFF3E3B37)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('← Back to Menu'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sideInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(color: Color(0xFF888888), fontSize: 13)),
        Text(value,
            style: const TextStyle(
                color: Color(0xFFD4D4D4),
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF302E2B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF262421),
        foregroundColor: const Color(0xFFD4D4D4),
        title: const Text('CheckMath'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 72, color: Color(0xFF888888)),
              const SizedBox(height: 20),
              const Text(
                'Cannot start game',
                style: TextStyle(
                    color: Color(0xFFD4D4D4),
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _isLocal
                    ? 'Unexpected error:\n$_error'
                    : 'Make sure the backend is running (run_backend.cmd)\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF888888), fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF739552),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                onPressed: _bootstrap,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Lobby Screen (Online mode)
  // ---------------------------------------------------------------------------
  Widget _buildLobbyScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF302E2B),
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: const Color(0xFF262421),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF3E3B37)),
              ),
              margin: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'ROOM CODE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.roomCode ?? _mpClient?.roomCode ?? '----',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFD4D4D4),
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 8,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildLobbyPlayerCard(
                    isHost: true,
                    name: _myOnlineRole == 'host' ? widget.username : _opponentName,
                    isReady: true,
                  ),
                  const SizedBox(height: 16),
                  _buildLobbyPlayerCard(
                    isHost: false,
                    name: _myOnlineRole == 'guest' ? widget.username : (_opponentInLobby ? _opponentName : 'Waiting for player...'),
                    isReady: _opponentInLobby || _myOnlineRole == 'guest',
                  ),
                  const SizedBox(height: 48),
                  if (_myOnlineRole == 'host')
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF739552),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF3E3B37),
                        disabledForegroundColor: const Color(0xFF888888),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _opponentInLobby ? _startOnlineGame : null,
                      child: Text(_opponentInLobby ? 'Start Game' : 'Waiting for Opponent...'),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3E3B37),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Waiting for host to start...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFD4D4D4),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLobbyPlayerCard({required bool isHost, required String name, required bool isReady}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF302E2B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isReady ? const Color(0xFF739552) : const Color(0xFF3E3B37),
          width: isReady ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isReady ? const Color(0xFF739552) : const Color(0xFF3E3B37),
            child: Icon(
              isHost ? Icons.local_police : Icons.person,
              color: isReady ? Colors.white : const Color(0xFF888888),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isHost ? 'HOST' : 'GUEST',
                  style: const TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  name,
                  style: TextStyle(
                    color: isReady ? const Color(0xFFD4D4D4) : const Color(0xFF888888),
                    fontSize: 16,
                    fontWeight: isReady ? FontWeight.bold : null,
                  ),
                ),
              ],
            ),
          ),
          if (isReady)
            const Icon(Icons.check_circle, color: Color(0xFF739552)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Coin Toss Overlay
  // ---------------------------------------------------------------------------
  Widget _buildCoinTossScreen() {
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          margin: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: const Color(0xFF262421),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF3E3B37), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                spreadRadius: 5,
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Coin Toss',
                style: TextStyle(
                  color: Color(0xFFD4D4D4),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              
              if (_coinTossPhase == 'choosing') ...[
                if (_myOnlineRole == 'guest' || (_isLocal && _isPvP)) ...[
                  Text(
                    _isLocal && _isPvP ? '${widget.opponentName ?? 'Player 2'}, choose your side:' : 'Choose your side to see who goes first:',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _coinButton('Heads', 'heads'),
                      const SizedBox(width: 20),
                      _coinButton('Tails', 'tails'),
                    ],
                  ),
                ] else ...[
                  const CircularProgressIndicator(color: Color(0xFF739552)),
                  const SizedBox(height: 24),
                  Text(
                    'Waiting for $_opponentName to pick...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 16),
                  ),
                ]
              ] else if (_coinTossPhase == 'spinning') ...[
                // 3D Flipping Animation
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (context, child) {
                    final angle = _pulseCtrl.value * 3.14159 * 10; // Spin 5 times
                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.001) // perspective
                        ..rotateX(angle),
                      child: Container(
                        width: 100, height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFE5A93D),
                          border: Border.all(color: const Color(0xFFC78D26), width: 4),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 10, offset: const Offset(0, 5),
                            )
                          ]
                        ),
                        child: Center(
                          child: Text(
                            // Alternate sides visually based on angle
                            (angle % (3.14159 * 2)) > 3.14159 ? 'T' : 'H', 
                            style: const TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold)
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                const Text('Flipping coin...', style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 18)),
              ] else if (_coinTossPhase == 'result') ...[
                Container(
                  width: 100, height: 100,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFE5A93D),
                  ),
                  child: Center(
                    child: Text(
                      _coinResult == 'heads' ? 'H' : 'T', 
                      style: const TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold)
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Result: ${_coinResult?.toUpperCase()}',
                  style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  _isLocal && _isPvP
                      ? (_coinTossWinner == 'guest' ? '${widget.opponentName} goes first!' : '${widget.username} goes first!')
                      : (_coinTossWinner == _myOnlineRole ? 'You go first!' : '$_opponentName goes first!'),
                  style: TextStyle(
                    color: _coinTossWinner == _myOnlineRole || (_isLocal && _isPvP && _coinTossWinner == 'host')
                        ? const Color(0xFF739552) 
                        : const Color(0xFF8B3A3A), 
                    fontSize: 20, 
                    fontWeight: FontWeight.w600
                  ),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _coinButton(String label, String value) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF3E3B37),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () async {
        if (_isLocal && _isPvP) {
          setState(() {
            _coinTossPhase = 'spinning';
          });
          await Future.delayed(const Duration(seconds: 2));
          if (!mounted) return;
          final res = (DateTime.now().millisecond % 2 == 0) ? 'heads' : 'tails';
          final wRole = (res == value) ? 'guest' : 'host';
          setState(() {
            _coinResult = res;
            _coinTossWinner = wRole;
            _coinTossPhase = 'result';
          });
          await Future.delayed(const Duration(seconds: 3));
          if (!mounted) return;
          setState(() {
            _showCoinToss = false;
          });
          final st = wRole == 'guest' ? 'ai' : 'human';
          _startLocalMatchAfterToss(st);
          return;
        }

        _mpClient?.send({
          'type': 'coin_toss_choose',
          'choice': value,
        });
        setState(() {
          _coinTossPhase = 'waiting_sync';
        });
      },
      child: Text(label, style: const TextStyle(fontSize: 18)),
    );
  }
}
