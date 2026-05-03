/// SciDAMA / CheckMath game engine — pure Dart, no network required.
///
/// Rules:
/// - Play squares: (row + col) % 2 == 1
/// - Row 0 = bottom; human pieces start on rows 0-2, AI on rows 5-7
/// - Captures are OPTIONAL on the first move of a turn (strategic choice)
/// - Once a capture chain is started, the player MUST continue if more
///   captures are available from the landing square (chain-continuation)
/// - SciDama scoring: the landing square's operator is applied between
///   the taker's value and the captured piece's value
library;

import 'dart:math';

import 'board_data.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const int kEmpty = 0;
const int kHumanMan = 1;
const int kHumanKing = 2;
const int kAiMan = 3;
const int kAiKing = 4;

// ---------------------------------------------------------------------------
// Piece helpers
// ---------------------------------------------------------------------------
int pieceType(int p) => p > 0 ? p ~/ 100 : 0;
int pieceValue(int p) => p > 0 ? p % 100 : 0;
int makePiece(int type, int value) => type * 100 + value;

bool isPlaySquare(int r, int c) =>
    r >= 0 && r < 8 && c >= 0 && c < 8 && (r + c) % 2 == 1;

bool isHumanPiece(int p) {
  final t = pieceType(p);
  return t == kHumanMan || t == kHumanKing;
}

bool isAiPiece(int p) {
  final t = pieceType(p);
  return t == kAiMan || t == kAiKing;
}

bool isKing(int p) {
  final t = pieceType(p);
  return t == kHumanKing || t == kAiKing;
}

/// Returns diagonal direction vectors for a piece.
List<List<int>> directionsFor(int p, bool human) {
  if (isKing(p)) return [[-1, -1], [-1, 1], [1, -1], [1, 1]];
  return human ? [[1, -1], [1, 1]] : [[-1, -1], [-1, 1]];
}

int maybePromote(int r, int c, int p) {
  final t = pieceType(p);
  final v = pieceValue(p);
  if (t == kHumanMan && r == 7) return makePiece(kHumanKing, v);
  if (t == kAiMan && r == 0) return makePiece(kAiKing, v);
  return p;
}

// ---------------------------------------------------------------------------
// Board initialisation
// ---------------------------------------------------------------------------
List<List<int>> initialBoard() {
  final rng = Random();
  final b = List.generate(8, (_) => List.filled(8, kEmpty));
  final humanVals = List<int>.generate(12, (i) => i + 1)..shuffle(rng);
  final aiVals = List<int>.generate(12, (i) => i + 1)..shuffle(rng);
  int hIdx = 0, aIdx = 0;
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      if (!isPlaySquare(r, c)) continue;
      if (r < 3) {
        b[r][c] = makePiece(kHumanMan, humanVals[hIdx++]);
      } else if (r > 4) {
        b[r][c] = makePiece(kAiMan, aiVals[aIdx++]);
      }
    }
  }
  return b;
}

// ---------------------------------------------------------------------------
// GameState
// ---------------------------------------------------------------------------
class GameState {
  List<List<int>> board;
  String currentTurn; // 'human' | 'ai'
  double humanScore;
  double aiScore;
  String difficulty;
  bool gameOver;
  String gameMode;
  String player1Name;
  String player2Name;
  String? winner;
  bool lastCapture; // true if last move was a capture (chain may continue)
  List<int>? lastMovedPiece; // [r, c] of piece that must continue chain
  List<String> calculations;
  bool playerCaptured;
  String gameId;

  GameState({
    required this.board,
    required this.currentTurn,
    required this.humanScore,
    required this.aiScore,
    required this.difficulty,
    required this.gameId,
    this.gameOver = false,
    this.gameMode = 'vs_ai',
    this.player1Name = 'Player 1',
    this.player2Name = 'Bot',
    this.winner,
    this.lastCapture = false,
    this.lastMovedPiece,
    List<String>? calculations,
    this.playerCaptured = false,
  }) : calculations = calculations ?? [];

  /// Convert to the same JSON shape the HTTP backend returns,
  /// so the rest of the app can consume it identically.
  Map<String, dynamic> toResponseMap() => {
        'game_id': gameId,
        'board': board,
        'current_turn': currentTurn,
        'human_score': humanScore,
        'ai_score': aiScore,
        'game_mode': gameMode,
        'player1_name': player1Name,
        'player2_name': player2Name,
        'difficulty': difficulty,
        'game_over': gameOver,
        'winner': winner,
        'last_capture': lastCapture,
        'player_captured': playerCaptured,
        'board_symbols': kBoardSymbols,
        'calculations': calculations,
      };

  /// Serialise to a plain Map for use with Flutter's compute() isolate.
  Map<String, dynamic> toIsolateMap() => {
        'board': board.map((r) => List<int>.from(r)).toList(),
        'current_turn': currentTurn,
        'human_score': humanScore,
        'ai_score': aiScore,
        'difficulty': difficulty,
        'game_over': gameOver,
        'game_mode': gameMode,
        'player1_name': player1Name,
        'player2_name': player2Name,
        'winner': winner,
        'last_capture': lastCapture,
        'last_moved_piece': lastMovedPiece,
        'calculations': List<String>.from(calculations),
        'player_captured': playerCaptured,
        'game_id': gameId,
      };

  /// Reconstruct from an isolate map.
  factory GameState.fromIsolateMap(Map<String, dynamic> m) {
    final rawBoard = m['board'] as List;
    final board = rawBoard
        .map((row) => List<int>.from((row as List).map((e) => e as int)))
        .toList();
    final rawLmp = m['last_moved_piece'];
    return GameState(
      board: board,
      currentTurn: m['current_turn'] as String,
      humanScore: (m['human_score'] as num).toDouble(),
      aiScore: (m['ai_score'] as num).toDouble(),
      difficulty: m['difficulty'] as String,
      gameOver: m['game_over'] as bool,
      gameMode: m['game_mode'] as String,
      player1Name: m['player1_name'] as String,
      player2Name: m['player2_name'] as String,
      winner: m['winner'] as String?,
      lastCapture: m['last_capture'] as bool,
      lastMovedPiece: rawLmp != null
          ? List<int>.from((rawLmp as List).map((e) => e as int))
          : null,
      calculations: List<String>.from(m['calculations'] as List),
      playerCaptured: m['player_captured'] as bool,
      gameId: m['game_id'] as String,
    );
  }

  GameState copy() => GameState(
        board: board.map((row) => List<int>.from(row)).toList(),
        currentTurn: currentTurn,
        humanScore: humanScore,
        aiScore: aiScore,
        difficulty: difficulty,
        gameOver: gameOver,
        gameMode: gameMode,
        player1Name: player1Name,
        player2Name: player2Name,
        winner: winner,
        lastCapture: lastCapture,
        lastMovedPiece:
            lastMovedPiece != null ? List<int>.from(lastMovedPiece!) : null,
        calculations: List<String>.from(calculations),
        playerCaptured: playerCaptured,
        gameId: gameId,
      );
}

// ---------------------------------------------------------------------------
// SciDAMA scoring
// ---------------------------------------------------------------------------
double calculateScore(double taker, String symbol, double taken) {
  switch (symbol) {
    case '+':
      return taker + taken;
    case '-':
      return taker - taken;
    case '×':
    case 'x':
    case 'X':
    case '*':
      return taker * taken;
    case '÷':
    case '/':
      return taken != 0 ? taker / taken : taker;
    default:
      return taker;
  }
}

// ---------------------------------------------------------------------------
// Move generation
// ---------------------------------------------------------------------------

/// Returns all multi-jump capture paths reachable from (r, c) in one sequence.
List<List<Map<String, dynamic>>> getAllPathsFrom(
  List<List<int>> board,
  int r,
  int c,
  bool human,
) {
  final p = board[r][c];
  final dirs = directionsFor(p, human);
  final paths = <List<Map<String, dynamic>>>[];

  for (final d in dirs) {
    final dr = d[0] * 2;
    final dc = d[1] * 2;
    final nr = r + dr;
    final nc = c + dc;
    if (nr < 0 || nr >= 8 || nc < 0 || nc >= 8) continue;
    if (board[nr][nc] != kEmpty) continue;

    final midR = (r + nr) ~/ 2;
    final midC = (c + nc) ~/ 2;
    final cap = board[midR][midC];
    final isEnemy = human ? isAiPiece(cap) : isHumanPiece(cap);
    if (!isEnemy) continue;

    final move = <String, dynamic>{
      'from': [r, c],
      'to': [nr, nc],
      'capture': true,
      'captured_r': midR,
      'captured_c': midC,
    };

    // Simulate capture and recurse
    final nb = board.map((row) => List<int>.from(row)).toList();
    nb[nr][nc] = nb[r][c];
    nb[r][c] = kEmpty;
    nb[midR][midC] = kEmpty;

    final subPaths = getAllPathsFrom(nb, nr, nc, human);
    if (subPaths.isEmpty) {
      paths.add([move]);
    } else {
      for (final sub in subPaths) {
        paths.add([move, ...sub]);
      }
    }
  }
  return paths;
}

/// Returns all legal moves for the given side.
///
/// **Optional-capture rule (player-facing):**
/// When [mustStartAt] is null (first move of a turn), both sliding moves
/// AND capture moves are returned — the player is NOT forced to capture.
///
/// **Chain-capture enforcement:**
/// When [mustStartAt] is set (mid-sequence), only capture continuations
/// from that specific square are returned, enforcing the chain.
///
/// The AI internally uses this same function, so it sees all options and
/// can greedily/optimally choose captures via its evaluation logic.
List<Map<String, dynamic>> allLegalMoves(
  List<List<int>> board,
  bool human, {
  List<int>? mustStartAt,
}) {
  final moves = <Map<String, dynamic>>[];

  // --- Mid-capture chain: must continue from the piece that already jumped ---
  if (mustStartAt != null) {
    final r = mustStartAt[0];
    final c = mustStartAt[1];
    final capPaths = getAllPathsFrom(board, r, c, human);
    for (final path in capPaths) {
      final mv = path[0];
      final f = mv['from'] as List;
      final t = mv['to'] as List;
      if (!moves.any((m) =>
          (m['from'] as List)[0] == f[0] &&
          (m['from'] as List)[1] == f[1] &&
          (m['to'] as List)[0] == t[0] &&
          (m['to'] as List)[1] == t[1])) {
        moves.add(mv);
      }
    }
    return moves;
  }

  // --- Normal turn: ALL moves are available (sliding + captures) ---
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      final p = board[r][c];
      if (human && !isHumanPiece(p)) continue;
      if (!human && !isAiPiece(p)) continue;

      // Capture moves (added first so UI / AI can detect them easily)
      final capPaths = getAllPathsFrom(board, r, c, human);
      for (final path in capPaths) {
        final mv = path[0];
        final f = mv['from'] as List;
        final t = mv['to'] as List;
        if (!moves.any((m) =>
            (m['from'] as List)[0] == f[0] &&
            (m['from'] as List)[1] == f[1] &&
            (m['to'] as List)[0] == t[0] &&
            (m['to'] as List)[1] == t[1])) {
          moves.add(mv);
        }
      }

      // Sliding moves
      final dirs = directionsFor(p, human);
      for (final d in dirs) {
        final nr = r + d[0];
        final nc = c + d[1];
        if (nr >= 0 && nr < 8 && nc >= 0 && nc < 8 && board[nr][nc] == kEmpty) {
          moves.add({'from': [r, c], 'to': [nr, nc], 'capture': false});
        }
      }
    }
  }
  return moves;
}

// ---------------------------------------------------------------------------
// Move application
// ---------------------------------------------------------------------------

/// Applies a move to [state]. Returns `(ok, message)`.
/// Mutates [state] in place.
(bool, String) applyMove(
  GameState state,
  int fr,
  int fc,
  int tr,
  int tc,
  bool human,
) {
  final b = state.board;
  if (!isPlaySquare(fr, fc) || !isPlaySquare(tr, tc)) {
    return (false, 'Invalid squares');
  }
  final piece = b[fr][fc];
  if (human && !isHumanPiece(piece)) return (false, 'Not your piece');
  if (!human && !isAiPiece(piece)) return (false, 'Not your piece');

  final mustStart = state.lastCapture ? state.lastMovedPiece : null;
  final legal = allLegalMoves(b, human, mustStartAt: mustStart);

  final match = legal.firstWhere(
    (m) =>
        (m['from'] as List)[0] == fr &&
        (m['from'] as List)[1] == fc &&
        (m['to'] as List)[0] == tr &&
        (m['to'] as List)[1] == tc,
    orElse: () => {},
  );

  if (match.isEmpty) return (false, 'Illegal move');

  state.playerCaptured = match['capture'] == true;

  if (match['capture'] != true) {
    // Simple slide
    b[tr][tc] = maybePromote(tr, tc, piece);
    b[fr][fc] = kEmpty;
    state.currentTurn = human ? 'ai' : 'human';
    state.lastCapture = false;
    state.lastMovedPiece = null;
    return (true, 'ok');
  }

  // Capture
  final midR = match['captured_r'] as int;
  final midC = match['captured_c'] as int;
  final capturedPiece = b[midR][midC];

  b[midR][midC] = kEmpty;
  b[tr][tc] = maybePromote(tr, tc, piece);
  b[fr][fc] = kEmpty;

  // SciDama scoring
  final sym = kBoardSymbols[tr][tc];
  if (sym.isNotEmpty) {
    final takerVal = pieceValue(piece).toDouble();
    final takenVal = pieceValue(capturedPiece).toDouble();
    final result = calculateScore(takerVal, sym, takenVal);

    int multiplier = 1;
    String desc = '';
    if (isKing(piece) && isKing(capturedPiece)) {
      multiplier = 4;
      desc = ' (Dama×Dama x4)';
    } else if (isKing(piece) || isKing(capturedPiece)) {
      multiplier = 2;
      desc = ' (Dama ×2)';
    }

    final finalAdded = result.abs() * multiplier;

    if (human) {
      state.humanScore += finalAdded;
      state.calculations.insert(
        0,
        '👤 ${state.player1Name}: ${ takerVal.toInt()} $sym ${takenVal.toInt()} = ${result.toStringAsFixed(1)}$desc  (+${finalAdded.toStringAsFixed(1)})',
      );
    } else {
      state.aiScore += finalAdded;
      final av = state.gameMode == 'vs_ai' ? '🤖' : '👤';
      state.calculations.insert(
        0,
        '$av ${state.player2Name}: ${takerVal.toInt()} $sym ${takenVal.toInt()} = ${result.toStringAsFixed(1)}$desc  (+${finalAdded.toStringAsFixed(1)})',
      );
    }
    if (state.calculations.length > 20) state.calculations.removeLast();
  }

  // Check for chain continuation
  state.lastCapture = true;
  state.lastMovedPiece = [tr, tc];

  final nextMoves = allLegalMoves(b, human, mustStartAt: [tr, tc]);
  if (nextMoves.isNotEmpty && nextMoves.first['capture'] == true) {
    // Same side continues the chain
    state.currentTurn = human ? 'human' : 'ai';
  } else {
    state.currentTurn = human ? 'ai' : 'human';
    state.lastCapture = false;
    state.lastMovedPiece = null;
  }

  return (true, 'ok');
}

// ---------------------------------------------------------------------------
// Piece counting + game-end
// ---------------------------------------------------------------------------
int countPieces(List<List<int>> board, bool human) {
  int n = 0;
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      final p = board[r][c];
      if (human && isHumanPiece(p)) n++;
      if (!human && isAiPiece(p)) n++;
    }
  }
  return n;
}

void checkGameEnd(GameState state) {
  final h = countPieces(state.board, true);
  final a = countPieces(state.board, false);

  bool hasLegalMoves = false;
  if (h > 0 && a > 0) {
    final legal = allLegalMoves(
      state.board,
      state.currentTurn == 'human',
      mustStartAt: state.lastCapture ? state.lastMovedPiece : null,
    );
    hasLegalMoves = legal.isNotEmpty;
  }

  if (h == 0 || a == 0 || !hasLegalMoves) {
    state.gameOver = true;

    // Add remaining chip values to their owners' scores
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final p = state.board[r][c];
        if (p == kEmpty) continue;
        final val = pieceValue(p).toDouble();
        final mult = isKing(p) ? 2.0 : 1.0;
        if (isHumanPiece(p)) {
          state.humanScore += val * mult;
        } else {
          state.aiScore += val * mult;
        }
      }
    }

    if (state.humanScore > state.aiScore) {
      state.winner = 'human';
    } else if (state.aiScore > state.humanScore) {
      state.winner = 'ai';
    } else {
      state.winner = 'draw';
    }
  }
}
