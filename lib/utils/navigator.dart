import 'package:flutter/cupertino.dart';

// Add a helper class to handle navigation with animations
class AppNavigator {
  static Future<T?> push<T>(BuildContext context, Widget page, {String? routeName}) {
    return Navigator.push<T>(
      context,
      CupertinoPageRoute<T>(
        builder: (context) => page,
        settings: RouteSettings(name: routeName),
      ),
    );
  }

  static Future<T?> pushReplacement<T>(BuildContext context, Widget page, {String? routeName}) {
    return Navigator.pushReplacement(
      context,
      CupertinoPageRoute<T>(
        builder: (context) => page,
        settings: RouteSettings(name: routeName),
      ),
    );
  }
}