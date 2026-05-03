import 'package:flutter/material.dart';

import '../core/board_data.dart';

typedef BoardCellTap = void Function(int row, int col);

/// Row index 0 = bottom (matches backend). Visually row 7 is drawn at the top.
class CheckerBoard extends StatelessWidget {
  const CheckerBoard({
    super.key,
    required this.board,
    required this.onCellTap,
    this.selected,
    this.lastMoveFrom,
    this.lastMoveTo,
    this.hintFrom,
    this.hintTo,
    this.interactive = true,
    this.isFlipped = false,
  });

  final List<List<int>> board;
  final BoardCellTap onCellTap;
  final List<int>? selected;
  final List<int>? lastMoveFrom;
  final List<int>? lastMoveTo;
  final List<int>? hintFrom;
  final List<int>? hintTo;
  final bool interactive;
  final bool isFlipped;

  static bool isPlaySquare(int r, int c) => (r + c) % 2 == 1;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        final cell = side / 8;
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: Column(
              children: [
                // Board rows
                for (int renderRow = 0; renderRow < 8; renderRow++)
                  Expanded(
                    child: Row(
                      children: [
                        for (int renderCol = 0; renderCol < 8; renderCol++)
                          () {
                            final vr = isFlipped ? renderRow : 7 - renderRow;
                            final c = isFlipped ? 7 - renderCol : renderCol;
                            return Expanded(
                              child: _Cell(
                                row: vr,
                                col: c,
                                cellSize: cell,
                                piece: board[vr][c],
                                symbol: kBoardSymbols[vr][c],
                                isPlay: isPlaySquare(vr, c),
                                selected: selected != null &&
                                    selected![0] == vr &&
                                    selected![1] == c,
                                isLastMoveSquare: _isLastMove(vr, c),
                                isHintSquare: hintFrom != null && hintFrom![0] == vr && hintFrom![1] == c ||
                                               hintTo != null && hintTo![0] == vr && hintTo![1] == c,
                                interactive: interactive,
                                onTap: () => onCellTap(vr, c),
                              ),
                            );
                          }(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isLastMove(int r, int c) {
    if (lastMoveFrom != null &&
        lastMoveFrom![0] == r &&
        lastMoveFrom![1] == c) {
      return true;
    }
    if (lastMoveTo != null &&
        lastMoveTo![0] == r &&
        lastMoveTo![1] == c) {
      return true;
    }
    return false;
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.row,
    required this.col,
    required this.cellSize,
    required this.piece,
    required this.symbol,
    required this.isPlay,
    required this.selected,
    required this.isLastMoveSquare,
    this.isHintSquare = false,
    required this.interactive,
    required this.onTap,
  });

  final int row;
  final int col;
  final double cellSize;
  final int piece;
  final String symbol;
  final bool isPlay;
  final bool selected;
  final bool isLastMoveSquare;
  final bool isHintSquare;
  final bool interactive;
  final VoidCallback onTap;

  // Chess.com color palette
  static const Color _darkSquare = Color(0xFF739552);      // green play square
  static const Color _lightSquare = Color(0xFFEBECD0);     // cream non-play square
  static const Color _selectedTint = Color(0xFFF6F669);    // yellow selection

  // Operator badge colors
  static const Map<String, Color> _opColors = {
    '+': Color(0xFF2ECC71),  // green
    '-': Color(0xFFE74C3C),  // red
    '×': Color(0xFFF39C12),  // orange
    '÷': Color(0xFF3498DB),  // blue
  };

  @override
  Widget build(BuildContext context) {
    Color bg;
    if (selected) {
      bg = _selectedTint;
    } else if (isLastMoveSquare) {
      bg = isPlay
          ? const Color(0xFF8CA342)   // darker olive on dark square
          : const Color(0xFFCDD16E);  // olive on light square
    } else {
      bg = isPlay ? _darkSquare : _lightSquare;
    }

    final badgeColor = isPlay && symbol.isNotEmpty
        ? (_opColors[symbol] ?? Colors.white)
        : Colors.transparent;

    return Material(
      color: bg,
      child: InkWell(
        onTap: interactive ? onTap : null,
        splashColor: _selectedTint.withValues(alpha: 0.5),
        highlightColor: _selectedTint.withValues(alpha: 0.3),
        child: Stack(
          children: [
            // Piece (centered)
            if (piece != 0)
              Align(
                alignment: Alignment.center,
                child: _Piece(piece: piece, size: cellSize * 0.78),
              ),

            // Hint overlay
            if (isHintSquare)
              Container(
                width: double.infinity,
                height: double.infinity,
                color: const Color(0xFFF6F669).withValues(alpha: 0.35),
              ),

            // Math operator badge — always visible in bottom-right corner
            if (isPlay && symbol.isNotEmpty)
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    symbol,
                    style: TextStyle(
                      fontSize: cellSize * 0.22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Piece extends StatelessWidget {
  const _Piece({required this.piece, required this.size});

  final int piece;
  final double size;

  int get type => piece > 0 ? piece ~/ 100 : 0;
  int get value => piece > 0 ? piece % 100 : 0;

  bool get human => type == 1 || type == 2;
  bool get king => type == 2 || type == 4;

  @override
  Widget build(BuildContext context) {
    // Human = light pieces (cream/white), AI = dark pieces (near-black)
    final outerColor = human ? const Color(0xFFF0EDE0) : const Color(0xFF252220);
    final innerColor = human ? const Color(0xFFE8E4D4) : const Color(0xFF1A1816);
    final borderColor = human ? const Color(0xFFCFCBBB) : const Color(0xFF0A0908);
    final glintColor = human
        ? Colors.white.withValues(alpha: 0.6)
        : Colors.white.withValues(alpha: 0.08);

    final pieceSize = size * 0.72;

    return SizedBox(
      width: pieceSize,
      height: pieceSize,
      child: CustomPaint(
        painter: _PiecePainter(
          outerColor: outerColor,
          innerColor: innerColor,
          borderColor: borderColor,
          glintColor: glintColor,
          isKing: king,
          isHuman: human,
          value: value,
        ),
      ),
    );
  }
}

class _PiecePainter extends CustomPainter {
  const _PiecePainter({
    required this.outerColor,
    required this.innerColor,
    required this.borderColor,
    required this.glintColor,
    required this.isKing,
    required this.isHuman,
    required this.value,
  });

  final Color outerColor;
  final Color innerColor;
  final Color borderColor;
  final Color glintColor;
  final bool isKing;
  final bool isHuman;
  final int value;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.46;

    // Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(Offset(cx, cy + 2), r, shadowPaint);

    // Outer border
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()..color = borderColor,
    );

    // Main body (gradient-like via two circles)
    canvas.drawCircle(
      Offset(cx, cy),
      r - 1.5,
      Paint()..color = outerColor,
    );

    // Inner circle (inset ring effect)
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.65,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Glint highlight
    canvas.drawCircle(
      Offset(cx - r * 0.3, cy - r * 0.3),
      r * 0.22,
      Paint()..color = glintColor,
    );

    // Draw the piece value
    final textColor = isHuman ? const Color(0xFF444444) : const Color(0xFFD4D4D4);
    final valuePainter = TextPainter(
      text: TextSpan(
        text: '$value',
        style: TextStyle(
          fontSize: size.width * (isKing ? 0.32 : 0.4),
          fontWeight: FontWeight.w900,
          color: textColor,
          height: 1,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    
    // Offset slightly higher if it's a king so the crown fits above
    final textY = isKing ? cy : cy - valuePainter.height / 2;
    valuePainter.paint(
      canvas,
      Offset(cx - valuePainter.width / 2, textY),
    );

    // King crown overlay
    if (isKing) {
      final crownColor = isHuman ? const Color(0xFFB8860B) : const Color(0xFFDAA520);
      final textPainter = TextPainter(
        text: TextSpan(
          text: '♛',
          style: TextStyle(
            fontSize: size.width * 0.28,
            color: crownColor,
            height: 1,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      textPainter.paint(
        canvas,
        Offset(
          cx - textPainter.width / 2,
          cy - valuePainter.height / 2 - textPainter.height * 0.8,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_PiecePainter old) =>
      old.isKing != isKing || old.outerColor != outerColor || old.value != value;
}
