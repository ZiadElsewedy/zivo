import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/util/bidi.dart';

/// The three tools in `bidi.dart` answer three different questions, and using
/// the wrong one is silently wrong rather than visibly wrong — which is why
/// each has its own case here.
void main() {
  group('ltr', () {
    test('wraps a run in an LTR isolate', () {
      expect(ltr('8–10'), '\u2066' '8–10' '\u2069');
    });

    test('leaves an empty string alone rather than planting bare controls', () {
      expect(ltr(''), '');
    });

    test('round-trips through stripBidi', () {
      expect(stripBidi(ltr('3 × 8–10 · rest 1:30')), '3 × 8–10 · rest 1:30');
    });
  });

  group('isolate', () {
    test('uses a first-strong isolate, so the run decides its own direction', () {
      expect(isolate('Push · Pull'), '\u2068' 'Push · Pull' '\u2069');
      expect(isolate('دفع · سحب'), '\u2068' 'دفع · سحب' '\u2069');
    });

    test('leaves an empty string alone', () {
      expect(isolate(''), '');
    });

    test('is stripped by stripBidi too', () {
      expect(stripBidi(isolate('Arnold Split')), 'Arnold Split');
    });
  });

  group('ltrFor', () {
    testWidgets('is a no-op under LTR, so English strings are untouched', (
      tester,
    ) async {
      late String out;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              out = ltrFor(context, 'rest 1:30');
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(out, 'rest 1:30');
    });

    testWidgets('pins the run under RTL', (tester) async {
      late String out;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (context) {
              out = ltrFor(context, '1:30');
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(out, ltr('1:30'));
      expect(stripBidi(out), '1:30');
    });
  });

  group('directionOf — a paragraph asks its own text', () {
    test('an English string is left-to-right whatever the app is set to', () {
      expect(
        directionOf('Ask me anything.', fallback: TextDirection.rtl),
        TextDirection.ltr,
      );
    });

    test('an Arabic string is right-to-left whatever the app is set to', () {
      expect(
        directionOf('اسألني أي شيء.', fallback: TextDirection.ltr),
        TextDirection.rtl,
      );
    });

    test('the FIRST strong character decides, not the majority', () {
      // A reply that opens in English and continues in Arabic reads as an
      // English paragraph with an Arabic run in it — which is what bidi does
      // with it anyway. What matters is that the two agree.
      expect(
        directionOf('ZIVO يقول', fallback: TextDirection.rtl),
        TextDirection.ltr,
      );
      expect(
        directionOf('يقول ZIVO', fallback: TextDirection.ltr),
        TextDirection.rtl,
      );
    });

    test('a string with no strong character keeps the surrounding direction', () {
      for (final text in const ['1270', '· 12/15 ·', '', '???']) {
        expect(
          directionOf(text, fallback: TextDirection.rtl),
          TextDirection.rtl,
          reason: '"$text" has no direction of its own to offer',
        );
        expect(directionOf(text, fallback: TextDirection.ltr), TextDirection.ltr);
      }
    });

    testWidgets('directionOfFor falls back to the ambient Directionality', (
      tester,
    ) async {
      late TextDirection english;
      late TextDirection digits;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (context) {
              english = directionOfFor(context, 'Balanced');
              digits = directionOfFor(context, '500');
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(english, TextDirection.ltr);
      expect(digits, TextDirection.rtl);
    });
  });
}
