import 'package:flutter/widgets.dart';

import 'session.dart';

/// Exposes the [Session] to the widget tree and rebuilds on change.
class SessionScope extends InheritedNotifier<Session> {
  const SessionScope({super.key, required Session session, required super.child}) : super(notifier: session);

  static Session of(BuildContext context) {
    final SessionScope? scope = context.dependOnInheritedWidgetOfExactType<SessionScope>();
    assert(scope != null, 'SessionScope is missing above this widget');
    return scope!.notifier!;
  }

  static Session? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>()?.notifier;
}
