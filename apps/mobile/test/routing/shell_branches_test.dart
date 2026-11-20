import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/routing/router.dart';

void main() {
  testWidgets('a toast during a route change has one hero across tabs', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    Widget tab(String name) => Navigator(
      onGenerateRoute: (_) =>
          MaterialPageRoute<void>(builder: (_) => Scaffold(body: Text(name))),
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (context) =>
              ShellBranches(index: 1, children: [tab('Rak'), tab('Atur')]),
        ),
      ),
    );

    ScaffoldMessenger.of(navigator.currentContext!)
        .showSnackBar(const SnackBar(content: Text('Udah keluar')));
    await tester.pump();
    // Both tabs' Scaffolds show it; only the visible one may take part in the flight.
    expect(find.text('Udah keluar', skipOffstage: false), findsNWidgets(2));

    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold()),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
