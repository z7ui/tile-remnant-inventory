import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/project_api.dart';
import '../../core/session.dart';
import '../../core/session_scope.dart';
import '../inventory/inventory_page.dart';
import '../match/match_page.dart';
import '../movements/movements_page.dart';
import '../settings/project_settings_page.dart';

/// Bottom navigation shell: 库存 / 匹配 / 流水 / 项目.
class ProjectShellPage extends StatefulWidget {
  const ProjectShellPage({super.key, required this.project});

  final JoinedProject project;

  @override
  State<ProjectShellPage> createState() => _ProjectShellPageState();
}

class _ProjectShellPageState extends State<ProjectShellPage> {
  int _index = 0;
  int _reloadToken = 0;
  late ProjectApi _api;
  bool _apiReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_apiReady) return;
    _apiReady = true;
    _api = ProjectApi(SessionScope.of(context), widget.project);
  }

  void _bumpReload() {
    setState(() => _reloadToken++);
    final Session? session = SessionScope.maybeOf(context);
    session?.refreshProjects().catchError((Object _) {});
  }

  void _switchToMatch() => setState(() => _index = 1);

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = <Widget>[
      InventoryPage(
        key: const ValueKey<String>('inventory'),
        api: _api,
        reloadToken: _reloadToken,
        onChanged: _bumpReload,
        onGoMatch: _switchToMatch,
      ),
      MatchPage(
        key: const ValueKey<String>('match'),
        api: _api,
        reloadToken: _reloadToken,
        onChanged: _bumpReload,
      ),
      MovementsPage(
        key: const ValueKey<String>('movements'),
        api: _api,
        reloadToken: _reloadToken,
      ),
      ProjectSettingsPage(
        key: const ValueKey<String>('settings'),
        api: _api,
        project: widget.project,
        onChanged: _bumpReload,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (int index) => setState(() => _index = index),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2_outlined), activeIcon: Icon(Icons.inventory_2), label: '库存'),
          BottomNavigationBarItem(icon: Icon(Icons.search_outlined), activeIcon: Icon(Icons.search), label: '匹配'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), activeIcon: Icon(Icons.receipt_long), label: '流水'),
          BottomNavigationBarItem(icon: Icon(Icons.folder_outlined), activeIcon: Icon(Icons.folder), label: '项目'),
        ],
      ),
    );
  }
}
