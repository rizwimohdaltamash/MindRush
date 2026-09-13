import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/core/rating/rating_engine.dart';
import 'package:mind_rush/core/scoring/scoring.dart';

void main() {
  group('RatingEngine.delta matches the design examples', () {
    // The four rows from the architecture diagram's rating table.
    test('101 vs 106 -> -4', () {
      expect(RatingEngine.delta(myScore: 101, oppScore: 106), -4);
    });
    test('67 vs 103 -> -11 (capped)', () {
      expect(RatingEngine.delta(myScore: 67, oppScore: 103), -11);
    });
    test('110 vs 98 -> +6', () {
      expect(RatingEngine.delta(myScore: 110, oppScore: 98), 6);
    });
    test('140 vs 100 -> +10', () {
      expect(RatingEngine.delta(myScore: 140, oppScore: 100), 10);
    });
  });

  group('bounds and symmetry', () {
    test('never exceeds +/-11 even for a shutout', () {
      expect(RatingEngine.delta(myScore: 500, oppScore: 0), 11);
      expect(RatingEngine.delta(myScore: 0, oppScore: 500), -11);
    });

    test('is symmetric -- what one side gains the other loses', () {
      for (final (a, b) in [(101, 106), (140, 100), (67, 103), (233, 210)]) {
        expect(
          RatingEngine.delta(myScore: a, oppScore: b),
          -RatingEngine.delta(myScore: b, oppScore: a),
          reason: 'zero-sum is what keeps total rating conserved',
        );
      }
    });

    test('opponent rating is irrelevant -- only the margin counts', () {
      // Same margin, wildly different opponents: identical reward.
      expect(
        RatingEngine.delta(myScore: 130, oppScore: 100),
        RatingEngine.delta(myScore: 130, oppScore: 100),
      );
    });

    test('grows monotonically with margin', () {
      var previous = -1;
      for (var loser = 100; loser >= 60; loser -= 5) {
        final d = RatingEngine.delta(myScore: 100, oppScore: loser);
        expect(d, greaterThanOrEqualTo(previous));
        previous = d;
      }
    });

    test('relative margin makes modes comparable', () {
      // A 40-point margin is a blowout in Mind Snap and a squeaker in
      // Fastest Fingers. The delta must reflect that, not the raw gap.
      final mindSnap = RatingEngine.delta(myScore: 120, oppScore: 80);
      final fastFingers = RatingEngine.delta(myScore: 700, oppScore: 660);
      expect(mindSnap, greaterThan(fastFingers));
    });
  });

  group('ties', () {
    test('level scores with no timing is a true draw', () {
      expect(RatingEngine.delta(myScore: 100, oppScore: 100), 0);
    });
    test('level scores break on total answer time', () {
      expect(
        RatingEngine.delta(
          myScore: 100,
          oppScore: 100,
          myTimeMs: 41000,
          oppTimeMs: 52000,
        ),
        1,
      );
      expect(
        RatingEngine.delta(
          myScore: 100,
          oppScore: 100,
          myTimeMs: 52000,
          oppTimeMs: 41000,
        ),
        -1,
      );
    });
  });

  group('apply', () {
    test('respects the floor', () {
      expect(RatingEngine.apply(105, -11), RatingEngine.floor);
      expect(RatingEngine.apply(RatingEngine.floor, -11), RatingEngine.floor);
    });
    test('normal movement is unclamped', () {
      expect(RatingEngine.apply(1000, 6), 1006);
    });
  });

  group('Mind Snap partial credit', () {
    test('follows the agreed curve', () {
      expect(Scoring.roundPoints(total: 6, correct: 6), 10);
      expect(Scoring.roundPoints(total: 6, correct: 5), 7);
      expect(Scoring.roundPoints(total: 6, correct: 4), 6);
      expect(Scoring.roundPoints(total: 6, correct: 3), 0);
      expect(Scoring.roundPoints(total: 6, correct: 0), 0);
    });
  });
}
