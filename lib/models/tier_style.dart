import 'package:flutter/material.dart';
import 'place.dart';

Color tierColor(Tier tier) {
  switch (tier) {
    case Tier.loved:
      return Colors.green.shade600;
    case Tier.liked:
      // A true, bright yellow - shade700 still read as gold in practice.
      return Colors.yellow.shade600;
    case Tier.meh:
      // Dark, not bright red - bright red draws the eye first on a map,
      // which is backwards for "the one to skip."
      return Colors.red.shade900;
    case Tier.toTry:
      return Colors.blueGrey.shade400;
    case Tier.unsorted:
      return Colors.grey.shade500;
  }
}

/// Map pins only: to-try dominates the map by sheer count, so it's toned
/// down to stay out of the way of anything actually rated.
double tierMapOpacity(Tier tier) => tier == Tier.toTry ? 0.6 : 1.0;
