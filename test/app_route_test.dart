// BI26101513: web addresses. Paths name views, a study module is /study/<course>/<file>, the old #/view still works,
// and nothing that is not a plain id can pick a view.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/ui/app_route.dart';

void main() {
  test('a path names a view; the root is the hub', () {
    expect(AppRoute.parse(Uri.parse('https://x.test/')).view, 'hub');
    expect(AppRoute.parse(Uri.parse('https://x.test/inbox')).view, 'inbox');
    expect(AppRoute.parse(Uri.parse('https://x.test/rhythm/')).view, 'rhythm');
  });

  test('the old fragment form still opens its view, and a path wins over it', () {
    expect(AppRoute.parse(Uri.parse('https://x.test/#/inbox')).view, 'inbox');
    expect(AppRoute.parse(Uri.parse('https://x.test/#inbox')).view, 'inbox');
    expect(AppRoute.parse(Uri.parse('https://x.test/rhythm#/inbox')).view, 'rhythm');
  });

  test('a study module carries its course and file, including a nested file and encoded characters', () {
    final r = AppRoute.parse(Uri.parse('https://x.test/study/ai%20basics/week1/lesson%202.md'));
    expect(r.view, 'learning');
    expect(r.course, 'ai basics');
    expect(r.file, 'week1/lesson 2.md');
    expect(r.isModule, isTrue);
    expect(AppRoute.parse(Uri.parse('https://x.test/study')).isModule, isFalse);
    expect(AppRoute.parse(Uri.parse('https://x.test/study/only-course')).isModule, isFalse);
  });

  test('a crafted address picks nothing: traversal, odd characters and over-long ids open the hub', () {
    expect(AppRoute.parse(Uri.parse('https://x.test/study/c/../secret.md')).isModule, isFalse);
    expect(AppRoute.parse(Uri.parse('https://x.test/in%20box')).view, 'hub');
    expect(AppRoute.parse(Uri.parse('https://x.test/${'a' * 60}')).view, 'hub');
    expect(AppRoute.parse(Uri.parse('https://x.test/#/<script>')).view, 'hub');
  });

  test('toUri round-trips a view and a module', () {
    for (final r in const [AppRoute(), AppRoute(view: 'inbox'), AppRoute(view: 'learning'), AppRoute(view: 'learning', course: 'ai basics', file: 'week1/lesson 2.md')]) {
      expect(AppRoute.parse(r.toUri()), r, reason: '${r.toUri()}');
    }
    expect(const AppRoute(view: 'inbox').toUri().toString(), '/inbox');
    expect(const AppRoute().toUri().toString(), '/');
  });

  testWidgets('the browser moving the route (back, forward) reaches the app state, and a chosen view reaches the browser', (t) async {
    final state = AppRouteState();
    final delegate = AppRouterDelegate(home: const Text('home'), state: state);
    const parser = AppRouteParser();
    await t.pumpWidget(MaterialApp.router(routerDelegate: delegate, routeInformationParser: parser, routeInformationProvider: PlatformRouteInformationProvider(initialRouteInformation: RouteInformation(uri: Uri.parse('/inbox')))));
    await t.pump();
    expect(find.text('home'), findsOneWidget);
    expect(state.value.view, 'inbox', reason: 'the opening address becomes the route');
    state.navigate(const AppRoute(view: 'rhythm'));
    expect(delegate.currentConfiguration.toUri().toString(), '/rhythm', reason: 'the shell choosing a view is what the address bar follows');
    await delegate.setNewRoutePath(const AppRoute(view: 'hub'));
    expect(state.value.view, 'hub', reason: 'back or forward sets the state the shell listens to');
  });
}
