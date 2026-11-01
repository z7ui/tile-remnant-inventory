import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/project_api.dart';
import '../../core/session.dart';
import '../../core/session_scope.dart';
import '../inventory/inventory_form_page.dart';
import '../inventory/inventory_page.dart';
import '../match/match_page.dart';
import '../movements/movements_page.dart';
import '../settings/project_settings_page.dart';

/// Bottom navigation shell: 库存 / 匹配 / 录入 / 流水 / 项目.
class ProjectShellPage extends StatefulWidget {
  const ProjectShellPage({super.key, required this.project});

  /// 路由名。溯源页「一键回到项目」靠它定位，
  /// 所以推这个页面时必须把 name 带上（见 project_list_page.dart）。
  static const String routeName = '/project';

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
        // pages 只有 4 个（库存/匹配/流水/项目），导航栏是 5 个：中间多一个「录入」。
        // 「录入」是动作不是常驻页，所以它不参与 currentIndex，点它直接推表单。
        currentIndex: _index < _entrySlot ? _index : _index + 1,
        onTap: (int slot) {
          if (slot == _entrySlot) {
            _openEntryForm();
            return;
          }
          setState(() => _index = slot > _entrySlot ? slot - 1 : slot);
        },
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2_outlined), activeIcon: Icon(Icons.inventory_2), label: '库存'),
          BottomNavigationBarItem(icon: Icon(Icons.search_outlined), activeIcon: Icon(Icons.search), label: '匹配'),
          BottomNavigationBarItem(icon: Icon(Icons.add_box_outlined), activeIcon: Icon(Icons.add_box), label: '录入'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), activeIcon: Icon(Icons.receipt_long), label: '流水'),
          BottomNavigationBarItem(icon: Icon(Icons.folder_outlined), activeIcon: Icon(Icons.folder), label: '项目'),
        ],
      ),
    );
  }

  /// 「录入」在导航栏里的位置（0 库存 / 1 匹配 / 2 录入 / 3 流水 / 4 项目）。
  static const int _entrySlot = 2;

  Future<void> _openEntryForm() async {
    final bool? created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => InventoryFormPage(api: _api)),
    );
    if (created == true && mounted) _bumpReload();
  }
}
