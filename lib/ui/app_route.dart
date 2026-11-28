import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_nav.dart';

/// BI26101513: the web console's addresses. A path names a view (`/inbox`, `/rhythm`) and a study module is
/// `/study/<course>/<module file>`; the old `#/inbox` fragment still opens its view. Anything that is not a plain id
/// opens the hub, so a crafted address can only ever pick a known view.
class AppRoute {
  const AppRoute({this.view = 'hub', this.course = '', this.file = ''});
  final String view;

  /// Set only for a study module deep link.
  final String course, file;

  bool get isModule => course.isNotEmpty && file.isNotEmpty;

  static final _id = RegExp(r'^[A-Za-z0-9_-]{1,40}$');

  /// `/study/<course>/<module>` opens the Study view's `learning` id with the module on top.
  static AppRoute parse(Uri uri) {
    final seg = [for (final s in uri.pathSegments) if (s.isNotEmpty) s];
    if (seg.isEmpty) {
      // The old fragment form: `#/inbox`.
      final f = uri.fragment.startsWith('/') ? uri.fragment.substring(1) : uri.fragment;
      return _id.hasMatch(f) ? AppRoute(view: f) : const AppRoute();
    }
    if (seg.first == 'study') {
      if (seg.length >= 3 && seg[1].length <= 120) {
        final file = seg.sublist(2).join('/');
        if (!file.contains('..') && file.length <= 240) return AppRoute(view: 'learning', course: seg[1], file: file);
      }
      return const AppRoute(view: 'learning');
    }
    return _id.hasMatch(seg.first) ? AppRoute(view: seg.first) : const AppRoute();
  }

  Uri toUri() {
    if (isModule) return Uri(pathSegments: ['study', course, ...file.split('/')]);
    if (view == 'learning') return Uri(path: '/study');
    return Uri(path: view == 'hub' ? '/' : '/$view');
  }

  @override
  bool operator ==(Object other) => other is AppRoute && other.view == view && other.course == course && other.file == file;

  @override
  int get hashCode => Object.hash(view, course, file);

  @override
  String toString() => 'AppRoute(${toUri()})';
}

/// The route the web app is on. The desktop shell writes it when a view is chosen and reads it when the browser's
/// back and forward buttons move it.
class AppRouteState extends ValueNotifier<AppRoute> {
  AppRouteState() : super(const AppRoute());
  static final AppRouteState instance = AppRouteState();

  /// True when a Router drives the app (web), so the shell reports views through it instead of the engine directly.
  bool active = false;

  void navigate(AppRoute r) => value = r;
}

class AppRouteParser extends RouteInformationParser<AppRoute> {
  const AppRouteParser();

  @override
  Future<AppRoute> parseRouteInformation(RouteInformation info) async => AppRoute.parse(info.uri);

  @override
  RouteInformation restoreRouteInformation(AppRoute configuration) => RouteInformation(uri: configuration.toUri());
}

/// One page, the root gate; the browser's history is the [AppRouteState]. Imperative pushes (a lesson, a sheet) sit
/// on top of it as before.
class AppRouterDelegate extends RouterDelegate<AppRoute> with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppRoute> {
  AppRouterDelegate({required this.home, AppRouteState? state}) : state = state ?? AppRouteState.instance {
    this.state.addListener(notifyListeners);
  }

  final Widget home;
  final AppRouteState state;

  @override
  GlobalKey<NavigatorState> get navigatorKey => rootNavigatorKey;

  @override
  AppRoute get currentConfiguration => state.value;

  @override
  Future<void> setNewRoutePath(AppRoute configuration) async {
    if (state.value != configuration) state.value = configuration;
  }

  @override
  Widget build(BuildContext context) => Navigator(
        key: navigatorKey,
        pages: [MaterialPage<void>(key: const ValueKey('root'), child: home)],
        onDidRemovePage: (_) {},
      );

  @override
  void dispose() {
    state.removeListener(notifyListeners);
    super.dispose();
  }
}
