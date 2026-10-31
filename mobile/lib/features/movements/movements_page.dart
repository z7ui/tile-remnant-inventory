import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/project_api.dart';
import '../../widgets/common.dart';
import 'movement_detail_page.dart';

class MovementsPage extends StatefulWidget {
  const MovementsPage({super.key, required this.api, required this.reloadToken});

  final ProjectApi api;
  final int reloadToken;

  @override
  State<MovementsPage> createState() => _MovementsPageState();
}

class _MovementsPageState extends State<MovementsPage> {
  final ScrollController _scroll = ScrollController();

  MovementPage? _page;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _type;
  int _pageNo = 1;

  static const Map<String, String?> _types = <String, String?>{
    '全部': null,
    '入库': 'stock_in',
    '使用': 'usage',
    '余料入库': 'cut_remnant',
    '余料丢弃': 'remnant_discard',
    '调整': 'adjust',
    '作废': 'void',
  };

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didUpdateWidget(covariant MovementsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadToken != widget.reloadToken) _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) _loadMore();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final MovementPage page = await widget.api.movements(type: _type, page: 1);
      if (!mounted) return;
      setState(() {
        _page = page;
        _pageNo = 1;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorMessage(error);
      });
    }
  }

  Future<void> _loadMore() async {
    final MovementPage? page = _page;
    if (page == null || _loadingMore || !page.hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final MovementPage next = await widget.api.movements(type: _type, page: _pageNo + 1);
      if (!mounted) return;
      setState(() {
        _page = MovementPage(
          items: <Movement>[...page.items, ...next.items],
          total: next.total,
          page: next.page,
          hasMore: next.hasMore,
        );
        _pageNo = next.page;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final MovementPage? page = _page;
    return Scaffold(
      appBar: buildAppBar(
        context,
        '流水',
        actions: <Widget>[
          IconButton(tooltip: '刷新', onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: <Widget>[
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              children: _types.entries
                  .map(
                    (MapEntry<String, String?> entry) => Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm, top: 8, bottom: 8),
                      child: ChoiceChip(
                        label: Text(entry.key),
                        selected: _type == entry.value,
                        onSelected: (_) {
                          setState(() => _type = entry.value);
                          _load();
                        },
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const SkeletonList(itemCount: 5, itemHeight: 76)
                  : ListView(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
                      children: <Widget>[
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.md),
                            child: ErrorBanner(message: _error!, onRetry: _load),
                          ),
                        if ((page?.items.isEmpty ?? true))
                          Container(
                            margin: const EdgeInsets.only(top: AppSpacing.md),
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                            decoration: BoxDecoration(
                              color: AppColors.card(context),
                              borderRadius: BorderRadius.circular(AppRadius.card),
                              border: Border.all(color: AppColors.line(context)),
                            ),
                            child: const EmptyState(
                              title: '还没有流水',
                              message: '入库、使用、切割余料都会自动记录，且只追加不修改。',
                              icon: Icons.receipt_long_outlined,
                            ),
                          )
                        else
                          ..._buildGroups(page!.items),
                        if (_loadingMore)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                            child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4))),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGroups(List<Movement> items) {
    final List<Widget> widgets = <Widget>[];
    String? currentDay;
    for (final Movement movement in items) {
      final String day = formatDateHeader(movement.createdAt);
      if (day != currentDay) {
        currentDay = day;
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
            child: Text(day, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.sub(context))),
          ),
        );
      }
      widgets.add(
        _MovementTile(
          movement: movement,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => MovementDetailPage(api: widget.api, movement: movement),
            ),
          ),
        ),
      );
    }
    return widgets;
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement, required this.onTap});

  final Movement movement;
  final VoidCallback onTap;

  Color _color(BuildContext context) {
    switch (movement.type) {
      case 'usage':
        return AppColors.primary;
      case 'cut_remnant':
        return AppColors.remnant;
      case 'remnant_discard':
      case 'void':
        return AppColors.danger;
      case 'adjust':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  IconData get _icon {
    switch (movement.type) {
      case 'usage':
        return Icons.content_cut;
      case 'cut_remnant':
        return Icons.change_history;
      case 'remnant_discard':
        return Icons.delete_outline;
      case 'adjust':
        return Icons.tune;
      case 'void':
        return Icons.block;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color color = _color(context);
    final String delta = movement.quantityDelta == 0
        ? ''
        : (movement.quantityDelta > 0 ? '+${movement.quantityDelta}' : '${movement.quantityDelta}');

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line(context)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 4,
                  height: 44,
                  margin: const EdgeInsets.only(right: AppSpacing.md, top: 2),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                ),
                Icon(_icon, size: 20, color: color),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            movement.typeLabel,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
                          ),
                          const SizedBox(width: 6),
                          Text(movement.batchCode, style: TextStyle(fontSize: 12, color: AppColors.sub(context))),
                          const Spacer(),
                          Text(formatTime(movement.createdAt), style: TextStyle(fontSize: 12, color: AppColors.sub(context))),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(),
                        style: TextStyle(fontSize: 12.5, color: AppColors.sub(context), height: 1.35),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (delta.isNotEmpty) ...<Widget>[
                  const SizedBox(width: AppSpacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(delta, style: numberStyle(context, size: 18, color: color)),
                      Text('${movement.quantityBefore}→${movement.quantityAfter}',
                          style: TextStyle(fontSize: 11, color: AppColors.sub(context))),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    final List<String> parts = <String>[];
    if (movement.usedLengthMm != null && movement.usedWidthMm != null) {
      parts.add('使用 ${movement.usedLengthMm}×${movement.usedWidthMm}mm');
    }
    if (movement.cutOptionLabel != null) parts.add(movement.cutOptionLabel!);
    if (movement.remnantActionLabel != null) parts.add('余料${movement.remnantActionLabel}');
    if (parts.isEmpty) parts.add(movement.note.isEmpty ? '—' : movement.note);
    return parts.join(' · ');
  }
}
