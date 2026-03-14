import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class AppRouteTracker extends NavigatorObserver {
  static final ValueNotifier<String?> currentRoute = ValueNotifier<String?>(null);

  static void setRouteName(String? routeName) {
    if (routeName == null || routeName.isEmpty) return;
    currentRoute.value = routeName;
  }

  void _sync(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name != null && name.isNotEmpty) {
      currentRoute.value = name;
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _sync(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _sync(previousRoute);
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _sync(newRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

final AppRouteTracker appRouteTracker = AppRouteTracker();
