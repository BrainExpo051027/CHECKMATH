/// AI bot engine — pure Dart, no network required.
///
/// Difficulty levels:
/// - Easy   → random legal move
/// - Medium → greedy (always captures if available, random otherwise)
/// - Hard   → minimax with alpha-beta pruning (depth 5)
///
/// The AI is run inside a Flutter Isolate via compute() so the UI thread
/// is never blocked during the minimax search.
library;

import 'package:flutter/foundation.dart' show compute;

import 'game_logic.dart';

// ---------------------------------------------------------------------------
// Material evaluation
// ---------------------------------------------------------------------------
double _evaluateMaterial(List<List<int>> board) {
  double v = 0;
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      final p = board[r][c];
      if (p == kEmpty) continue;
      final t = pieceType(p);
      final val = pieceValue(p);
      switch (t) {
        case kHumanMan:
          v -= (3.0 + 0.1 * r + val * 0.01);
        case kHumanKing:
          v -= (5.0 + val * 0.01);
        case kAiMan:
          v += (3.0 + 0.1 * (7 - r) + val * 0.01);
        case kAiKing:
          v += (5.0 + val * 0.01);
      }
    }
  }
  return v;
}

double _evaluateState(GameState state) {
  if (state.gameOver) {
    if (state.winner == 'ai') return 1e6;
    if (state.winner == 'human') return -1e6;
    return 0;
  }
  return _evaluateMaterial(state.board);
}

// ---------------------------------------------------------------------------
// Minimax with alpha-beta pruning
// ---------------------------------------------------------------------------
double _minimax(GameState state, int depth, double alpha, double beta) {
  if (depth == 0 || state.gameOver) return _evaluateState(state);

  final humanSide = state.currentTurn == 'human';
  final moves = allLegalMoves(
    state.board,
    humanSide,
    mustStartAt: state.lastCapture ? state.lastMovedPiece : null,
  );
  if (moves.isEmpty) return _evaluateState(state);

  if (humanSide) {
    // Minimising player
    double val = double.infinity;
    for (final m in moves) {
      final ns = state.copy();
      final fr = (m['from'] as List)[0] as int;
      final fc = (m['from'] as List)[1] as int;
      final tr = (m['to'] as List)[0] as int;
      final tc = (m['to'] as List)[1] as int;
      final (ok, _) = applyMove(ns, fr, fc, tr, tc, true);
      if (!ok) continue;
      checkGameEnd(ns);
      val = val < _minimax(ns, depth - 1, alpha, beta)
          ? val
          : _minimax(ns, depth - 1, alpha, beta);
      beta = beta < val ? beta : val;
      if (beta <= alpha) break;
    }
    return val;
  } else {
    // Maximising player (AI)
    double val = double.negativeInfinity;
    for (final m in moves) {
      final ns = state.copy();
      final fr = (m['from'] as List)[0] as int;
      final fc = (m['from'] as List)[1] as int;
      final tr = (m['to'] as List)[0] as int;
      final tc = (m['to'] as List)[1] as int;
      final (ok, _) = applyMove(ns, fr, fc, tr, tc, false);
      if (!ok) continue;
      checkGameEnd(ns);
      final score = _minimax(ns, depth - 1, alpha, beta);
      if (score > val) val = score;
      if (val > alpha) alpha = val;
      if (beta <= alpha) break;
    }
    return val;
  }
}

// ---------------------------------------------------------------------------
// Move selectors
// ---------------------------------------------------------------------------
Map<String, dynamic>? _randomMove(List<List<int>> board) {
  final moves = allLegalMoves(board, false);
  if (moves.isEmpty) return null;
  moves.shuffle();
  return moves.first;
}

Map<String, dynamic>? _greedyMove(List<List<int>> board) {
  final moves = allLegalMoves(board, false);
  if (moves.isEmpty) return null;
  final captures = moves.where((m) => m['capture'] == true).toList();
  if (captures.isNotEmpty) {
    captures.shuffle();
    return captures.first;
  }
  moves.shuffle();
  return moves.first;
}

Map<String, dynamic>? _minimaxMove(GameState state) {
  final moves = allLegalMoves(
    state.board,
    false,
    mustStartAt: state.lastCapture ? state.lastMovedPiece : null,
  );
  if (moves.isEmpty) return null;

  Map<String, dynamic>? best;
  double bestScore = double.negativeInfinity;

  for (final m in moves) {
    final ns = state.copy();
    final fr = (m['from'] as List)[0] as int;
    final fc = (m['from'] as List)[1] as int;
    final tr = (m['to'] as List)[0] as int;
    final tc = (m['to'] as List)[1] as int;
    final (ok, _) = applyMove(ns, fr, fc, tr, tc, false);
    if (!ok) continue;
    checkGameEnd(ns);
    final score = _minimax(ns, 5, double.negativeInfinity, double.infinity);
    if (score > bestScore) {
      bestScore = score;
      best = m;
    }
  }
  return best ?? moves.first;
}

/// Finds the best move for the HUMAN player (used by the hint system).
/// Picks the move that leads to the lowest evaluation score (human minimises).
Map<String, dynamic>? getBestHumanMove(GameState state) {
  final moves = allLegalMoves(
    state.board,
    true, // human pieces
    mustStartAt: state.lastCapture ? state.lastMovedPiece : null,
  );
  if (moves.isEmpty) return null;

  Map<String, dynamic>? best;
  double bestScore = double.infinity; // human minimises

  for (final m in moves) {
    final ns = state.copy();
    final fr = (m['from'] as List)[0] as int;
    final fc = (m['from'] as List)[1] as int;
    final tr = (m['to'] as List)[0] as int;
    final tc = (m['to'] as List)[1] as int;
    final (ok, _) = applyMove(ns, fr, fc, tr, tc, true);
    if (!ok) continue;
    checkGameEnd(ns);
    // After human moves it's the AI turn — next minimax level is maximising
    final score = _minimax(ns, 4, double.negativeInfinity, double.infinity);
    if (score < bestScore) {
      bestScore = score;
      best = m;
    }
  }
  final bestMoveToReturn = best ?? moves.first;

  // Generate a reason for the hint
  final ns = state.copy();
  final fr = (bestMoveToReturn['from'] as List)[0] as int;
  final fc = (bestMoveToReturn['from'] as List)[1] as int;
  final tr = (bestMoveToReturn['to'] as List)[0] as int;
  final tc = (bestMoveToReturn['to'] as List)[1] as int;
  applyMove(ns, fr, fc, tr, tc, true);

  final scoreGain = ns.humanScore - state.humanScore;
  if (bestMoveToReturn['capture'] == true) {
    if (scoreGain > 0) {
      bestMoveToReturn['reason'] = 'Optimal capture! You will gain ${scoreGain.toStringAsFixed(1)} points.';
    } else {
      bestMoveToReturn['reason'] = 'This capture is necessary to break the opponent\'s defense.';
    }
  } else {
    bestMoveToReturn['reason'] = 'This is the safest sliding move to construct a strong defense or setup future attacks.';
  }

  return bestMoveToReturn;
}

/// Top-level dispatcher used both directly and via compute().
Map<String, dynamic>? getAiMove(GameState state) {
  switch ((state.difficulty).toLowerCase()) {
    case 'easy':
      return _randomMove(state.board);
    case 'hard':
      return _minimaxMove(state);
    default: // 'medium' and anything else
      return _greedyMove(state.board);
  }
}

// ---------------------------------------------------------------------------
// Isolate wrapper — call this from the UI layer
// ---------------------------------------------------------------------------

/// Top-level function required by compute() — must be a free function.
Map<String, dynamic>? _isolateAiMove(Map<String, dynamic> stateMap) {
  final state = GameState.fromIsolateMap(stateMap);
  return getAiMove(state);
}

/// Runs [getAiMove] in a background isolate so the UI thread stays smooth.
/// Returns the chosen move map, or null if the AI has no moves.
Future<Map<String, dynamic>?> computeAiMove(GameState state) {
  return compute(_isolateAiMove, state.toIsolateMap());
}

/// Top-level free function for compute() — finds the best HUMAN move.
Map<String, dynamic>? _isolateBestHumanMove(Map<String, dynamic> stateMap) {
  final state = GameState.fromIsolateMap(stateMap);
  return getBestHumanMove(state);
}

/// Runs [getBestHumanMove] in a background isolate (used by the hint button).
Future<Map<String, dynamic>?> computeBestHumanMove(GameState state) {
  return compute(_isolateBestHumanMove, state.toIsolateMap());
}
