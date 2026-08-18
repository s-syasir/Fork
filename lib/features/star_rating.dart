import 'package:flutter/material.dart';

/// A row of 10 tappable stars backed by a 0-10 double score, in 0.5
/// increments - tapping the left half of a star sets it to N-0.5, the
/// right half to N. Tapping the already-set value clears the rating.
class StarRating extends StatelessWidget {
  final double? score;
  final ValueChanged<double?> onChanged;

  const StarRating({super.key, required this.score, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      children: [
        for (var i = 1; i <= 10; i++) _Star(index: i, score: score, onChanged: onChanged),
      ],
    );
  }
}

class _Star extends StatelessWidget {
  final int index;
  final double? score;
  final ValueChanged<double?> onChanged;

  const _Star({required this.index, required this.score, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    if (score != null && score! >= index) {
      icon = Icons.star;
      color = Colors.amber.shade700;
    } else if (score != null && score! >= index - 0.5) {
      icon = Icons.star_half;
      color = Colors.amber.shade700;
    } else {
      icon = Icons.star_border;
      color = Colors.grey;
    }

    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        children: [
          Center(child: Icon(icon, color: color, size: 22)),
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => onChanged(score == index - 0.5 ? null : index - 0.5),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => onChanged(score == index ? null : index.toDouble()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
