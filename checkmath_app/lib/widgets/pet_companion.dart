import 'package:flutter/material.dart';

/// Simple animated mascot with taunt / cheer messages.
class PetCompanion extends StatefulWidget {
  const PetCompanion({
    super.key,
    required this.message,
    this.mood = PetMood.neutral,
  });

  final String message;
  final PetMood mood;

  @override
  State<PetCompanion> createState() => _PetCompanionState();
}

enum PetMood { neutral, happy, smug, tease }

class _PetCompanionState extends State<PetCompanion>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (widget.mood) {
      PetMood.happy => Colors.amber.shade700,
      PetMood.smug => Colors.deepPurple,
      PetMood.tease => Colors.orange.shade800,
      PetMood.neutral => Colors.blueGrey,
    };

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final bounce = 4 * (0.5 - (_c.value - 0.5).abs());
        return Transform.translate(
          offset: Offset(0, -bounce),
          child: child,
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.pets, size: 36, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.message,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
