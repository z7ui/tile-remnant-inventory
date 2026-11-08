import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/project_api.dart';
import '../../core/session.dart';
import '../../core/session_scope.dart';
import '../../widgets/common.dart';
import '../../widgets/stock_card.dart';
import '../inventory/inventory_form_page.dart';
import '../projects/invite_page.dart';
import '../trace/trace_page.dart';

class InventoryFilter {
  const InventoryFilter({
    this.shapeType,
    this.sourceType,
    this.minQuantity,
    this.maxQuantity,
    this.minLongMm,
    this.maxLongMm,
    this.location,
    this.sort = 'created_desc',
  });

  final String? shapeType;
  final String? sourceType;
  final int? minQuantity;
  final int? maxQuantity;
  final int? minLongMm;
  final int? maxLongMm;
  final String? location;
  final String sort;

  bool get isEmpty =>
      shapeType == null &&
      sourceType == null &&
      minQuantity == null &&
      maxQuantity == null &&
      minLongMm == null &&
      maxLongMm == null &&
      location == null &&
      sort == 'created_desc';

  int get activeCount {
    int count = 0;
    if (shapeType != null) count++;
    if (sourceType != null) count++;
    if (minQuantity != null || maxQuantity != null) count++;
    if (minLongMm != null || maxLongMm != null) count++;
    if (location != null) count++;
    if (sort != 'created_desc') count++;
    return count;
  }

  InventoryFilter copyWith({
    String? shapeType,
    String? sourceType,
    int? minQuantity,
    int? maxQuantity,
    int? minLongMm,
    int? maxLongMm,
    String? location,
    String? sort,
    bool clear = false,
  }) {
    if (clear) return const InventoryFilter();
    return InventoryFilter(
      shapeType: shapeType,
      sourceType: sourceType,
      minQuantity: minQuantity,
      maxQuantity: maxQuantity,
      minLongMm: minLongMm,
      maxLongMm: maxLongMm,
      location: location,
      sort: sort ?? this.sort,
    );
  }

  String get summary {
    final List<String> parts = <String>[];
    if (shapeType != null) {
      parts.add(shapeType == 'irregular'
          ? '异形'
          : (shapeType == 'l_shape' ? 'L 形' : '矩形'));
    }
    if (sourceType != null) parts.add(sourceType == 'cut' ? '切割余料' : '原始录入');
    if (minQuantity != null || maxQuantity != null) parts.add('片数');
    if (minLongMm != null || maxLongMm != null) parts.add('尺寸');
    if (location != null) parts.add(location!);
    return parts.join(' · ');
  }
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({
    super.key,
    required this.api,
    required this.reloadToken,
    required this.onChanged,
    required this.onGoMatch,
  });

  final ProjectApi api;
  final int reloadToken;
  final VoidCallback onChanged;
  final VoidCallback onGoMatch;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  BatchPage? _page;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  InventoryFilter _filter = const InventoryFilter();
  int _pageNo = 1;

  String get _unit => SessionScope.of(context).current?.defaultUnit ?? 'mm';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didUpdateWidget(covariant InventoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadToken != widget.reloadToken) {
      _load();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _pageNo = 1;
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final BatchPage page = await widget.api.inventory(
        page: 1,
        q: _search.text,
        shapeType: _filter.shapeType,
        sourceType: _filter.sourceType,
        minQuantity: _filter.minQuantity,
        maxQuantity: _filter.maxQuantity,
        minLongMm: _filter.minLongMm,
        maxLongMm: _filter.maxLongMm,
        location: _filter.location,
        sort: _filter.sort,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _pageNo = 1;
        _loading = false;
        _error = null;
      });
      final Session? session = SessionScope.maybeOf(context);
      session?.updateStats(
        widget.api.project.id,
        ProjectStats(
          pieces: page.pieces,
          batches: page.total,
          lShapeBatches: session.current?.stats.lShapeBatches ?? 0,
          availableBatches: page.total,
          areaMm2: page.areaMm2,
          lastActivityAt: session.current?.stats.lastActivityAt,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorMessage(error);
      });
    }
  }

  Future<void> _loadMore() async {
    final BatchPage? page = _page;
    if (page == null || _loadingMore || !page.hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final BatchPage next = await widget.api.inventory(
        page: _pageNo + 1,
        q: _search.text,
        shapeType: _filter.shapeType,
        sourceType: _filter.sourceType,
        minQuantity: _filter.minQuantity,
        maxQuantity: _filter.maxQuantity,
        minLongMm: _filter.minLongMm,
        maxLongMm: _filter.maxLongMm,
        location: _filter.location,
        sort: _filter.sort,
      );
      if (!mounted) return;
      setState(() {
        _page = BatchPage(
          items: <Batch>[...page.items, ...next.items],
          total: next.total,
          page: next.page,
          hasMore: next.hasMore,
          pieces: next.pieces,
          areaMm2: next.areaMm2,
          locations: next.locations,
        );
        _pageNo = next.page;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _openForm() async {
    final bool? created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => InventoryFormPage(
          api: widget.api,
          knownLocations: _page?.locations ?? const <String>[],
        ),
      ),
    );
    if (created == true) {
      widget.onChanged();
      await _load(reset: true);
    }
  }

  Future<void> _openTrace(Batch batch) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (_) =>
              TracePage(api: widget.api, batchId: batch.id, title: batch.code)),
    );
  }

  /// 弹一个数字输入框，返回用户输入的整数（取消返回 null）。
  Future<int?> _askCount({
    required String title,
    required String hint,
    required int initial,
    required int max,
    required String actionLabel,
  }) async {
    final TextEditingController controller =
        TextEditingController(text: '$initial');
    final int? result = await showDialog<int>(
      context: context,
      builder: (BuildContext dialogContext) {
        String? error;
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: hint,
                  suffixText: '片',
                  errorText: error,
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final int? value = int.tryParse(controller.text);
                    if (value == null || value < 0 || value > max) {
                      setDialogState(() => error = '请输入 0 ~ $max 之间的整数');
                      return;
                    }
                    Navigator.of(dialogContext).pop(value);
                  },
                  child: Text(actionLabel),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _consume(Batch batch) async {
    final int? count = await _askCount(
      title: '用掉整砖',
      hint: '这次用掉几片（当前 ${batch.quantity} 片）',
      initial: batch.quantity,
      max: batch.quantity,
      actionLabel: '扣掉',
    );
    if (count == null || count < 1) return;
    try {
      await widget.api
          .consumeBatch(batch.id, quantity: count, note: '整砖批量使用');
      if (!mounted) return;
      showSnack(context, '已用掉 $count 片');
      await _load(reset: true);
    } catch (error) {
      if (!mounted) return;
      showSnack(context, errorMessage(error), error: true);
    }
  }

  Future<void> _adjust(Batch batch) async {
    final int? count = await _askCount(
      title: '调整片数',
      hint: '盘点后的实际片数',
      initial: batch.quantity,
      max: 20000,
      actionLabel: '保存',
    );
    if (count == null || count == batch.quantity) return;
    try {
      await widget.api.updateBatch(batch.id, <String, dynamic>{
        'quantity': count,
        'adjust_reason': '手动调整为 $count 片',
      });
      if (!mounted) return;
      showSnack(context, '片数已改为 $count');
      await _load(reset: true);
    } catch (error) {
      if (!mounted) return;
      showSnack(context, errorMessage(error), error: true);
    }
  }

  Future<void> _openFilters() async {    final InventoryFilter? result = await showModalBottomSheet<InventoryFilter>(
      context: context,
      isScrollControlled: true,
      builder: (_) => InventoryFilterSheet(
        initial: _filter,
        locations: _page?.locations ?? const <String>[],
      ),
    );
    if (result != null && mounted) {
      setState(() => _filter = result);
      await _load(reset: true);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 400), () => _load(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    final Session session = SessionScope.of(context);
    final BatchPage? page = _page;
    final String unit = _unit;

    return Scaffold(
      appBar: buildAppBar(
        context,
        '库存',
        actions: <Widget>[
          IconButton(
            tooltip: '邀请工友',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => InvitePage(project: widget.api.project),
              ),
            ),
            icon: const Icon(Icons.qr_code_2),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: () => _load(reset: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
          children: <Widget>[
            _Overview(
              projectName: widget.api.project.name,
              stats: page == null
                  ? widget.api.project.stats
                  : ProjectStats(
                      pieces: page.pieces,
                      batches: page.total,
                      lShapeBatches: widget.api.project.stats.lShapeBatches,
                      areaMm2: page.areaMm2,
                      lastActivityAt: widget.api.project.stats.lastActivityAt,
                    ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: widget.onGoMatch,
                      icon: const Icon(Icons.search),
                      label: const Text('快速匹配'),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: _openForm,
                      icon: const Icon(Icons.add_box_outlined),
                      label: const Text('录入库存'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索批次号 / 存放位置 / 备注',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空搜索',
                        onPressed: () {
                          _search.clear();
                          _load(reset: true);
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        ActionChip(
                          avatar: Badge(
                            isLabelVisible: _filter.activeCount > 0,
                            label: Text('${_filter.activeCount}'),
                            child: const Icon(Icons.tune, size: 18),
                          ),
                          label: Text(_filter.isEmpty ? '筛选' : _filter.summary),
                          onPressed: _openFilters,
                        ),
                        if (!_filter.isEmpty) ...<Widget>[
                          const SizedBox(width: AppSpacing.sm),
                          TextButton(
                            onPressed: () {
                              setState(() => _filter = const InventoryFilter());
                              _load(reset: true);
                            },
                            child: const Text('清除全部'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (!_loading)
                  Text(
                    '${page?.total ?? 0} 个批次',
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.sub(context)),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (session.offline)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: ErrorBanner(message: '离线：显示的是上次加载的数据。'),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: ErrorBanner(
                    message: _error!, onRetry: () => _load(reset: true)),
              ),
            if (_loading)
              const SkeletonList(itemCount: 4)
            else if ((page?.items.isEmpty ?? true))
              Container(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                decoration: BoxDecoration(
                  color: AppColors.card(context),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.line(context)),
                ),
                child: _filter.isEmpty && _search.text.isEmpty
                    ? EmptyState(
                        title: '还没有余砖',
                        message: '录入第一块余砖，之后就能按尺寸快速匹配。\n只支持矩形：长、宽、片数。',
                        icon: Icons.grid_view_rounded,
                        actionLabel: '录入第一块余砖',
                        onAction: _openForm,
                      )
                    : EmptyState(
                        title: '没有符合条件的余砖',
                        message: '换个筛选条件，或者清除全部筛选再看看。',
                        icon: Icons.filter_alt_off_outlined,
                        actionLabel: '清除筛选',
                        onAction: () {
                          _search.clear();
                          setState(() => _filter = const InventoryFilter());
                          _load(reset: true);
                        },
                      ),
              )
            else ...<Widget>[
              ...page!.items.map(
                (Batch batch) => StockCard(
                  batch: batch,
                  unit: unit,
                  onTap: () => _openTrace(batch),
                  onTrace: () => _openTrace(batch),
                  onConsume: () => _consume(batch),
                  onAdjust: () => _adjust(batch),
                ),
              ),
              if (_loadingMore)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Center(
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.4))),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.projectName, required this.stats});

  final String projectName;
  final ProjectStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            AppColors.accent(context),
            AppColors.accent(context).withValues(alpha: 0.82),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            projectName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              _Stat(value: '${stats.pieces}', label: '可用片数'),
              _Divider(),
              _Stat(
                  value:
                      '${stats.availableBatches == 0 ? stats.batches : stats.availableBatches}',
                  label: '可用批次'),
              _Divider(),
              _Stat(value: '${stats.lShapeBatches}', label: '异形批次'),
              _Divider(),
              _Stat(
                  value: formatArea(stats.areaMm2), label: '总面积', small: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.small = false});

  final String value;
  final String label;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: small ? 16 : 24,
                fontWeight: FontWeight.w700,
                fontFeatures: const <ui.FontFeature>[
                  ui.FontFeature.tabularFigures()
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.86), fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      color: Colors.white.withValues(alpha: 0.25),
    );
  }
}

class InventoryFilterSheet extends StatefulWidget {
  const InventoryFilterSheet(
      {super.key, required this.initial, required this.locations});

  final InventoryFilter initial;
  final List<String> locations;

  @override
  State<InventoryFilterSheet> createState() => _InventoryFilterSheetState();
}

class _InventoryFilterSheetState extends State<InventoryFilterSheet> {
  late String? _shape = widget.initial.shapeType;
  late String? _source = widget.initial.sourceType;
  late String? _quantityBand =
      _bandFrom(widget.initial.minQuantity, widget.initial.maxQuantity);
  late String? _sizeBand = _sizeBandFrom(widget.initial.minLongMm);
  late String? _location = widget.initial.location;
  late String _sort = widget.initial.sort;

  static String? _bandFrom(int? min, int? max) {
    if (min == null && max == null) return null;
    if (min == 1 && max == 1) return 'one';
    if (min == 2) return 'few';
    if (min == 4) return 'many';
    return null;
  }

  static String? _sizeBandFrom(int? min) {
    if (min == null) return null;
    if (min >= 800) return 'large';
    if (min >= 400) return 'medium';
    return 'small';
  }

  void _apply() {
    int? minQty;
    int? maxQty;
    switch (_quantityBand) {
      case 'one':
        minQty = 1;
        maxQty = 1;
        break;
      case 'few':
        minQty = 2;
        maxQty = 3;
        break;
      case 'many':
        minQty = 4;
        break;
    }
    int? minLong;
    switch (_sizeBand) {
      case 'large':
        minLong = 800;
        break;
      case 'medium':
        minLong = 400;
        break;
      case 'small':
        minLong = 1;
        break;
    }
    Navigator.of(context).pop(
      InventoryFilter(
        shapeType: _shape,
        sourceType: _source,
        minQuantity: minQty,
        maxQuantity: maxQty,
        minLongMm: minLong,
        location: _location,
        sort: _sort,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('筛选', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.lg),
              _group(
                  '形状',
                  <String, String?>{
                    '全部': null,
                    '矩形': 'rectangle',
                    'L 形': 'l_shape',
                    '异形': 'irregular'
                  },
                  _shape,
                  (String? value) => setState(() => _shape = value)),
              _group(
                  '来源',
                  <String, String?>{
                    '全部': null,
                    '原始录入': 'manual',
                    '切割余料': 'cut'
                  },
                  _source,
                  (String? value) => setState(() => _source = value)),
              _group(
                  '片数',
                  <String, String?>{
                    '全部': null,
                    '1 片': 'one',
                    '2–3 片': 'few',
                    '4 片以上': 'many'
                  },
                  _quantityBand,
                  (String? value) => setState(() => _quantityBand = value)),
              _group(
                  '长边尺寸',
                  <String, String?>{
                    '全部': null,
                    '≥ 80cm': 'large',
                    '40–80cm': 'medium',
                    '< 40cm': 'small'
                  },
                  _sizeBand,
                  (String? value) => setState(() => _sizeBand = value)),
              if (widget.locations.isNotEmpty)
                _group(
                  '存放位置',
                  <String, String?>{
                    '全部': null,
                    for (final String location in widget.locations)
                      location: location
                  },
                  _location,
                  (String? value) => setState(() => _location = value),
                ),
              _group(
                '排序',
                <String, String?>{
                  '最新在前': 'created_desc',
                  '面积从大到小': 'area_desc',
                  '片数从多到少': 'quantity_desc'
                },
                _sort,
                (String? value) =>
                    setState(() => _sort = value ?? 'created_desc'),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(label: '应用筛选', onPressed: _apply),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(const InventoryFilter()),
                  child: const Text('清除全部筛选'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _group(String title, Map<String, String?> options, String? selected,
      ValueChanged<String?> onSelected) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.sub(context))),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: options.entries.map((MapEntry<String, String?> entry) {
              final bool isSelected = entry.value == selected;
              return ChoiceChip(
                label: Text(entry.key),
                selected: isSelected,
                onSelected: (_) => onSelected(entry.value),
              );
            }).toList(growable: false),
          ),
        ],
      ),
    );
  }
}
