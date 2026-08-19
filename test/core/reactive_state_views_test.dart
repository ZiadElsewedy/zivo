import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:zivo/core/widgets/reactive_state_views.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('LoadingStateView shows the branded loading animation', (tester) async {
    await tester.pumpWidget(_host(const LoadingStateView()));
    expect(find.byType(Lottie), findsOneWidget);
  });

  testWidgets('EmptyStateView shows its message', (tester) async {
    await tester.pumpWidget(_host(const EmptyStateView('Nothing here yet.')));
    expect(find.text('Nothing here yet.'), findsOneWidget);
  });

  testWidgets('ErrorStateView shows the default message and an icon', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const ErrorStateView()));
    expect(find.text("Couldn't load this."), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
  });

  testWidgets('ErrorStateView accepts a custom message', (tester) async {
    await tester.pumpWidget(_host(const ErrorStateView(message: 'Boom.')));
    expect(find.text('Boom.'), findsOneWidget);
  });
}
