/// Typed views over the API payloads.
library;

int _int(dynamic value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? fallback;
}

int? _intOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

double _double(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}') ?? fallback;
}

String _str(dynamic value, [String fallback = '']) =>
    value == null ? fallback : '$value';

bool _bool(dynamic value, [bool fallback = false]) =>
    value is bool ? value : fallback;

List<dynamic> _list(dynamic value) => value is List ? value : const <dynamic>[];

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

class ShapeRect {
  const ShapeRect(
      {required this.x, required this.y, required this.w, required this.h});

  final int x;
  final int y;
  final int w;
  final int h;

  factory ShapeRect.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return ShapeRect(
      x: _int(map['x']),
      y: _int(map['y']),
      w: _int(map['w']),
      h: _int(map['h']),
    );
  }

  int get area => w * h;
}

class Notch {
  const Notch({required this.w, required this.h, this.corner});

  final int w;
  final int h;
  final String? corner;

  factory Notch.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return Notch(
        w: _int(map['w']),
        h: _int(map['h']),
        corner: map['corner']?.toString());
  }

  String get label {
    switch (corner) {
      case 'bottom_left':
        return '左下缺口';
      case 'bottom_right':
        return '右下缺口';
      case 'top_left':
        return '左上缺口';
      case 'top_right':
        return '右上缺口';
      default:
        return '缺口';
    }
  }
}

class Batch {
  const Batch({
    required this.id,
    required this.code,
    required this.batchNo,
    required this.shapeType,
    required this.widthMm,
    required this.heightMm,
    required this.areaMm2,
    required this.quantity,
    required this.initialQuantity,
    required this.status,
    required this.sourceType,
    required this.location,
    required this.createdAt,
    this.note = '',
    this.parentBatchId,
    this.rootBatchId,
    this.cutOption,
    this.usedLengthMm,
    this.usedWidthMm,
    this.rects = const <ShapeRect>[],
    this.notch,
    this.composite = false,
    this.belowMinUsable = false,
  });

  final String id;
  final String code;
  final int batchNo;
  final String shapeType;
  final int widthMm;
  final int heightMm;
  final int areaMm2;
  final int quantity;
  final int initialQuantity;
  final String status;
  final String sourceType;
  final String location;
  final String createdAt;
  final String note;
  final String? parentBatchId;
  final String? rootBatchId;
  final String? cutOption;
  final int? usedLengthMm;
  final int? usedWidthMm;
  final List<ShapeRect> rects;
  final Notch? notch;
  final bool composite;
  final bool belowMinUsable;

  bool get isLShape => shapeType == 'l_shape';
  bool get isIrregular => shapeType == 'irregular';
  bool get isAvailable => status == 'available' && quantity > 0;
  int get shortMm => widthMm <= heightMm ? widthMm : heightMm;
  int get longMm => widthMm <= heightMm ? heightMm : widthMm;

  factory Batch.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return Batch(
      id: _str(map['id']),
      code: _str(
          map['code'], '#${_int(map['batch_no']).toString().padLeft(4, '0')}'),
      batchNo: _int(map['batch_no']),
      shapeType: _str(map['shape_type'], 'rectangle'),
      widthMm: _int(map['width_mm']),
      heightMm: _int(map['height_mm']),
      areaMm2: _int(map['area_mm2']),
      quantity: _int(map['quantity']),
      initialQuantity: _int(map['initial_quantity'], _int(map['quantity'])),
      status: _str(map['status'], 'available'),
      sourceType: _str(map['source_type'], 'manual'),
      location: _str(map['location']),
      createdAt: _str(map['created_at']),
      note: _str(map['note']),
      parentBatchId: map['parent_batch_id']?.toString(),
      rootBatchId: map['root_batch_id']?.toString(),
      cutOption: map['cut_option']?.toString(),
      usedLengthMm: _intOrNull(map['used_length_mm']),
      usedWidthMm: _intOrNull(map['used_width_mm']),
      rects:
          _list(map['rects']).map(ShapeRect.fromJson).toList(growable: false),
      notch: map['notch'] == null ? null : Notch.fromJson(map['notch']),
      composite: _bool(map['composite']),
      belowMinUsable: _bool(map['below_min_usable']),
    );
  }
}

class Remnant {
  const Remnant({
    required this.shapeType,
    required this.widthMm,
    required this.heightMm,
    required this.areaMm2,
    required this.rects,
    this.notch,
    this.notchCorner,
    this.composite = false,
    this.belowThreshold = false,
  });

  final String shapeType;
  final int widthMm;
  final int heightMm;
  final int areaMm2;
  final List<ShapeRect> rects;
  final Notch? notch;
  final String? notchCorner;
  final bool composite;
  final bool belowThreshold;

  bool get isLShape => shapeType == 'l_shape';
  bool get isIrregular => shapeType == 'irregular';

  factory Remnant.fromJson(dynamic json) {
    if (json == null)
      return const Remnant(
          shapeType: 'none',
          widthMm: 0,
          heightMm: 0,
          areaMm2: 0,
          rects: <ShapeRect>[]);
    final Map<String, dynamic> map = _map(json);
    return Remnant(
      shapeType: _str(map['shape_type'], 'rectangle'),
      widthMm: _int(map['width_mm']),
      heightMm: _int(map['height_mm']),
      areaMm2: _int(map['area_mm2']),
      rects:
          _list(map['rects']).map(ShapeRect.fromJson).toList(growable: false),
      notch: map['notch'] == null ? null : Notch.fromJson(map['notch']),
      notchCorner: map['notch_corner']?.toString(),
      composite: _bool(map['composite']),
      belowThreshold: _bool(map['below_threshold']),
    );
  }
}

class CutOptionPreview {
  const CutOptionPreview({
    required this.option,
    required this.feasible,
    this.reason,
    this.wasteMm2,
    this.utilization,
    this.rotation,
    this.placement,
    this.remnant,
  });

  final String option;
  final bool feasible;
  final String? reason;
  final int? wasteMm2;
  final double? utilization;
  final int? rotation;
  final ShapeRect? placement;
  final Remnant? remnant;

  bool get isLongSide => option == 'long_side_cut';
  String get label => isLongSide ? '长边切到底' : '短边切到底';

  factory CutOptionPreview.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return CutOptionPreview(
      option: _str(map['cut_option'], 'long_side_cut'),
      feasible: _bool(map['feasible']),
      reason: map['reason']?.toString(),
      wasteMm2: _intOrNull(map['waste_mm2']),
      utilization:
          map['utilization'] == null ? null : _double(map['utilization']),
      rotation: _intOrNull(map['rotation']),
      placement: map['placement'] == null
          ? null
          : ShapeRect.fromJson(map['placement']),
      remnant: map['remnant'] == null ? null : Remnant.fromJson(map['remnant']),
    );
  }
}

class MatchCandidate {
  const MatchCandidate({
    required this.batch,
    required this.cutOptions,
    required this.wasteMm2,
    required this.utilization,
    required this.rotation,
    required this.cutOption,
    required this.maxPieces,
    this.remnant,
    this.placement,
    this.remnantValue = 0,
  });

  final Batch batch;
  final List<CutOptionPreview> cutOptions;
  final int wasteMm2;
  final double utilization;
  final int rotation;
  final String cutOption;
  final int maxPieces;
  final Remnant? remnant;
  final ShapeRect? placement;
  final int remnantValue;

  bool get hasRemnant => remnant != null;
  String get cutLabel => cutOption == 'long_side_cut' ? '长边切到底' : '短边切到底';

  CutOptionPreview? previewFor(String option) {
    for (final CutOptionPreview preview in cutOptions) {
      if (preview.option == option) return preview;
    }
    return null;
  }

  factory MatchCandidate.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    final Map<String, dynamic> match = _map(map['match']);
    return MatchCandidate(
      batch: Batch.fromJson(map['batch']),
      cutOptions: _list(map['cut_options'])
          .map(CutOptionPreview.fromJson)
          .toList(growable: false),
      wasteMm2: _int(match['waste_mm2']),
      utilization: _double(match['utilization']),
      rotation: _int(match['rotation']),
      cutOption: _str(match['cut_option'], 'long_side_cut'),
      maxPieces: _int(match['max_pieces'], 1),
      remnant:
          match['remnant'] == null ? null : Remnant.fromJson(match['remnant']),
      placement: match['placement'] == null
          ? null
          : ShapeRect.fromJson(match['placement']),
      remnantValue: _int(match['remnant_value']),
    );
  }
}

class AllocationSuggestion {
  const AllocationSuggestion({
    required this.batchId,
    required this.batchNo,
    required this.quantity,
    required this.cutOption,
    this.remnantAction,
  });

  final String batchId;
  final int batchNo;
  final int quantity;
  final String cutOption;
  final String? remnantAction;

  factory AllocationSuggestion.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return AllocationSuggestion(
      batchId: _str(map['batch_id']),
      batchNo: _int(map['batch_no']),
      quantity: _int(map['quantity'], 1),
      cutOption: _str(map['cut_option'], 'long_side_cut'),
      remnantAction: map['remnant_action']?.toString(),
    );
  }
}

class DemandInfo {
  const DemandInfo(
      {required this.shortMm,
      required this.longMm,
      required this.quantity,
      required this.areaMm2});

  final int shortMm;
  final int longMm;
  final int quantity;
  final int areaMm2;

  factory DemandInfo.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return DemandInfo(
      shortMm: _int(map['short_mm']),
      longMm: _int(map['long_mm']),
      quantity: _int(map['quantity'], 1),
      areaMm2: _int(map['area_mm2']),
    );
  }
}

class MatchResult {
  const MatchResult({
    required this.demand,
    required this.candidates,
    required this.allocation,
    required this.unfulfilledQuantity,
    required this.totalCandidates,
  });

  final DemandInfo demand;
  final List<MatchCandidate> candidates;
  final List<AllocationSuggestion> allocation;
  final int unfulfilledQuantity;
  final int totalCandidates;

  factory MatchResult.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return MatchResult(
      demand: DemandInfo.fromJson(map['demand']),
      candidates: _list(map['candidates'])
          .map(MatchCandidate.fromJson)
          .toList(growable: false),
      allocation: _list(map['allocation'])
          .map(AllocationSuggestion.fromJson)
          .toList(growable: false),
      unfulfilledQuantity: _int(map['unfulfilled_quantity']),
      totalCandidates: _int(map['total_candidates']),
    );
  }
}

/// 多需求里的一行（一个尺寸 + 数量 + 实际满足情况）。
class MultiDemandRow {
  const MultiDemandRow({
    required this.shortMm,
    required this.longMm,
    required this.quantity,
    required this.fulfilled,
    required this.missing,
  });

  final int shortMm;
  final int longMm;
  final int quantity;
  final int fulfilled;
  final int missing;

  factory MultiDemandRow.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return MultiDemandRow(
      shortMm: _int(map['short_mm']),
      longMm: _int(map['long_mm']),
      quantity: _int(map['quantity']),
      fulfilled: _int(map['fulfilled']),
      missing: _int(map['missing']),
    );
  }
}

/// 一块砖切出来的某一档尺寸。
class NestingPiece {
  const NestingPiece({
    required this.widthMm,
    required this.heightMm,
    required this.quantity,
    required this.areaMm2,
  });

  final int widthMm;
  final int heightMm;
  final int quantity;
  final int areaMm2;

  factory NestingPiece.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return NestingPiece(
      widthMm: _int(map['width_mm']),
      heightMm: _int(map['height_mm']),
      quantity: _int(map['quantity']),
      areaMm2: _int(map['area_mm2']),
    );
  }
}

/// 一块砖的混排计划。
class NestingBlock {
  const NestingBlock({
    required this.batchId,
    required this.batchNo,
    required this.widthMm,
    required this.heightMm,
    required this.pieces,
    required this.cuttings,
    required this.usedAreaMm2,
    required this.wasteAreaMm2,
    required this.totalPieces,
  });

  final String batchId;
  final int batchNo;
  final int widthMm;
  final int heightMm;
  final List<NestingPiece> pieces;

  /// 每一片的实际位置（画混排图用）。
  final List<ShapeRect> cuttings;
  final int usedAreaMm2;
  final int wasteAreaMm2;
  final int totalPieces;

  double get utilization =>
      widthMm * heightMm == 0 ? 0 : usedAreaMm2 / (widthMm * heightMm);

  factory NestingBlock.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    final Map<String, dynamic> plan = _map(map['plan']);
    return NestingBlock(
      batchId: '${map['batch_id'] ?? ''}',
      batchNo: _int(map['batch_no']),
      widthMm: _int(map['width_mm']),
      heightMm: _int(map['height_mm']),
      pieces: _list(plan['placed'])
          .map(NestingPiece.fromJson)
          .toList(growable: false),
      cuttings: _list(plan['pieces_rects'])
          .map(ShapeRect.fromJson)
          .toList(growable: false),
      usedAreaMm2: _int(plan['used_area_mm2']),
      wasteAreaMm2: _int(plan['waste_area_mm2']),
      totalPieces: _int(plan['total_pieces']),
    );
  }
}

class MultiMatchSummary {
  const MultiMatchSummary({
    required this.blocksUsed,
    required this.demandPieces,
    required this.fulfilledPieces,
    required this.missingPieces,
    required this.utilization,
  });

  final int blocksUsed;
  final int demandPieces;
  final int fulfilledPieces;
  final int missingPieces;
  final double utilization;

  factory MultiMatchSummary.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return MultiMatchSummary(
      blocksUsed: _int(map['blocks_used']),
      demandPieces: _int(map['demand_pieces']),
      fulfilledPieces: _int(map['fulfilled_pieces']),
      missingPieces: _int(map['missing_pieces']),
      utilization: (map['utilization'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// 服务端公告里的一个按钮。
class AnnouncementButton {
  const AnnouncementButton({
    required this.label,
    required this.action,
    required this.target,
  });

  final String label;

  /// 白名单：open_url / dismiss / reload / open_about / copy / none
  final String action;
  final String target;

  bool get isVisible => label.trim().isNotEmpty && action != 'none';

  factory AnnouncementButton.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return AnnouncementButton(
      label: '${map['label'] ?? ''}',
      action: '${map['action'] ?? 'none'}',
      target: '${map['target'] ?? ''}',
    );
  }
}

/// 服务端下发的一条公告。
class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.dismissible,
    required this.buttons,
  });

  final String id;
  final String title;
  final String body;
  final bool dismissible;
  final List<AnnouncementButton> buttons;

  factory Announcement.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return Announcement(
      id: '${map['id'] ?? ''}',
      title: '${map['title'] ?? ''}',
      body: '${map['body'] ?? ''}',
      dismissible: map['dismissible'] != false,
      buttons: _list(map['buttons'])
          .map(AnnouncementButton.fromJson)
          .toList(growable: false),
    );
  }
}
/// 多尺寸匹配结果。
class MultiMatchResult {
  const MultiMatchResult({
    required this.demands,
    required this.blocks,
    required this.summary,
    required this.skipped,
  });

  final List<MultiDemandRow> demands;
  final List<NestingBlock> blocks;
  final MultiMatchSummary summary;
  final List<String> skipped;

  factory MultiMatchResult.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return MultiMatchResult(
      demands: _list(map['demands'])
          .map(MultiDemandRow.fromJson)
          .toList(growable: false),
      blocks: _list(map['blocks'])
          .map(NestingBlock.fromJson)
          .toList(growable: false),
      summary: MultiMatchSummary.fromJson(map['summary']),
      skipped: _list(map['skipped'])
          .map((dynamic e) => '${_map(e)['batch_no'] ?? '?'}（${_map(e)['reason'] ?? ''}）')
          .toList(growable: false),
    );
  }
}

class Movement {
  const Movement({
    required this.id,
    required this.type,
    required this.typeLabel,
    required this.batchId,
    required this.batchCode,
    required this.quantityDelta,
    required this.quantityBefore,
    required this.quantityAfter,
    required this.createdAt,
    this.widthBeforeMm,
    this.heightBeforeMm,
    this.widthAfterMm,
    this.heightAfterMm,
    this.usedLengthMm,
    this.usedWidthMm,
    this.cutOptionLabel,
    this.remnantActionLabel,
    this.remnantShape,
    this.remnantAreaMm2,
    this.producedBatchId,
    this.usageRecordId,
    this.deviceId = '',
    this.note = '',
    this.traceUrl,
  });

  final String id;
  final String type;
  final String typeLabel;
  final String batchId;
  final String batchCode;
  final int quantityDelta;
  final int quantityBefore;
  final int quantityAfter;
  final String createdAt;
  final int? widthBeforeMm;
  final int? heightBeforeMm;
  final int? widthAfterMm;
  final int? heightAfterMm;
  final int? usedLengthMm;
  final int? usedWidthMm;
  final String? cutOptionLabel;
  final String? remnantActionLabel;
  final String? remnantShape;
  final int? remnantAreaMm2;
  final String? producedBatchId;
  final String? usageRecordId;
  final String deviceId;
  final String note;
  final String? traceUrl;

  bool get isPositive => quantityDelta > 0;

  factory Movement.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return Movement(
      id: _str(map['id']),
      type: _str(map['type']),
      typeLabel: _str(map['type_label'], _str(map['type'])),
      batchId: _str(map['batch_id']),
      batchCode: _str(map['batch_code']),
      quantityDelta: _int(map['quantity_delta']),
      quantityBefore: _int(map['quantity_before']),
      quantityAfter: _int(map['quantity_after']),
      createdAt: _str(map['created_at']),
      widthBeforeMm: _intOrNull(map['width_before_mm']),
      heightBeforeMm: _intOrNull(map['height_before_mm']),
      widthAfterMm: _intOrNull(map['width_after_mm']),
      heightAfterMm: _intOrNull(map['height_after_mm']),
      usedLengthMm: _intOrNull(map['used_length_mm']),
      usedWidthMm: _intOrNull(map['used_width_mm']),
      cutOptionLabel: map['cut_option_label']?.toString(),
      remnantActionLabel: map['remnant_action_label']?.toString(),
      remnantShape: map['remnant_shape']?.toString(),
      remnantAreaMm2: _intOrNull(map['remnant_area_mm2']),
      producedBatchId: map['produced_batch_id']?.toString(),
      usageRecordId: map['usage_record_id']?.toString(),
      deviceId: _str(map['device_id']),
      note: _str(map['note']),
      traceUrl: map['trace_url']?.toString(),
    );
  }
}

class BatchPage {
  const BatchPage({
    required this.items,
    required this.total,
    required this.page,
    required this.hasMore,
    required this.pieces,
    required this.areaMm2,
    required this.locations,
  });

  final List<Batch> items;
  final int total;
  final int page;
  final bool hasMore;
  final int pieces;
  final int areaMm2;
  final List<String> locations;

  factory BatchPage.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    final Map<String, dynamic> summary = _map(map['summary']);
    final Map<String, dynamic> filters = _map(map['filters']);
    return BatchPage(
      items: _list(map['items']).map(Batch.fromJson).toList(growable: false),
      total: _int(map['total']),
      page: _int(map['page'], 1),
      hasMore: _bool(map['has_more']),
      pieces: _int(summary['pieces']),
      areaMm2: _int(summary['area_mm2']),
      locations: _list(filters['locations'])
          .map((dynamic e) => '$e')
          .toList(growable: false),
    );
  }
}

class MovementPage {
  const MovementPage(
      {required this.items,
      required this.total,
      required this.page,
      required this.hasMore});

  final List<Movement> items;
  final int total;
  final int page;
  final bool hasMore;

  factory MovementPage.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return MovementPage(
      items: _list(map['items']).map(Movement.fromJson).toList(growable: false),
      total: _int(map['total']),
      page: _int(map['page'], 1),
      hasMore: _bool(map['has_more']),
    );
  }
}

class UsageLine {
  const UsageLine({
    required this.batchId,
    required this.batchNo,
    required this.quantity,
    required this.cutOptionLabel,
    required this.wasteMm2,
    this.remnantActionLabel,
    this.remnant,
    this.remnantBatch,
    this.quantityBefore,
    this.quantityAfter,
  });

  final String batchId;
  final int batchNo;
  final int quantity;
  final String cutOptionLabel;
  final int wasteMm2;
  final String? remnantActionLabel;
  final Remnant? remnant;
  final Batch? remnantBatch;
  final int? quantityBefore;
  final int? quantityAfter;

  factory UsageLine.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return UsageLine(
      batchId: _str(map['batch_id']),
      batchNo: _int(map['batch_no']),
      quantity: _int(map['quantity'], 1),
      cutOptionLabel: _str(map['cut_option_label'], '—'),
      wasteMm2: _int(map['waste_mm2']),
      remnantActionLabel: map['remnant_action_label']?.toString(),
      remnant: map['remnant'] == null ? null : Remnant.fromJson(map['remnant']),
      remnantBatch: map['remnant_batch'] == null
          ? null
          : Batch.fromJson(map['remnant_batch']),
      quantityBefore: _intOrNull(map['quantity_before']),
      quantityAfter: _intOrNull(map['quantity_after']),
    );
  }
}

class UsageResult {
  const UsageResult({
    required this.usageId,
    required this.replayed,
    required this.totalWasteMm2,
    required this.lines,
    required this.piecesAfter,
  });

  final String usageId;
  final bool replayed;
  final int totalWasteMm2;
  final List<UsageLine> lines;
  final int piecesAfter;

  factory UsageResult.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    final Map<String, dynamic> after = _map(map['inventory_after']);
    return UsageResult(
      usageId: _str(map['usage_id']),
      replayed: _bool(map['replayed']),
      totalWasteMm2: _int(map['total_waste_mm2']),
      lines:
          _list(map['results']).map(UsageLine.fromJson).toList(growable: false),
      piecesAfter: _int(after['pieces']),
    );
  }
}

class TraceNode {
  const TraceNode(
      {required this.id,
      required this.code,
      required this.widthMm,
      required this.heightMm,
      required this.areaMm2,
      required this.quantity,
      required this.isCurrent});

  final String id;
  final String code;
  final int widthMm;
  final int heightMm;
  final int areaMm2;
  final int quantity;
  final bool isCurrent;

  factory TraceNode.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return TraceNode(
      id: _str(map['id']),
      code: _str(map['code']),
      widthMm: _int(map['width_mm']),
      heightMm: _int(map['height_mm']),
      areaMm2: _int(map['area_mm2']),
      quantity: _int(map['quantity']),
      isCurrent: _bool(map['is_current']),
    );
  }
}

class TraceComparison {
  const TraceComparison({required this.original, this.demand, this.remnant});

  final Map<String, dynamic> original;
  final Map<String, dynamic>? demand;
  final Map<String, dynamic>? remnant;

  factory TraceComparison.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return TraceComparison(
      original: _map(map['original']),
      demand: map['demand'] == null ? null : _map(map['demand']),
      remnant: map['remnant'] == null ? null : _map(map['remnant']),
    );
  }
}

class TraceData {
  const TraceData({
    required this.batch,
    required this.comparison,
    required this.ancestors,
    required this.children,
    required this.movements,
    required this.nodes,
    required this.currentIndex,
  });

  final Batch batch;
  final TraceComparison comparison;
  final List<TraceNode> ancestors;
  final List<TraceNode> children;
  final List<Movement> movements;
  final List<TraceNode> nodes;
  final int currentIndex;

  factory TraceData.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    final Map<String, dynamic> chain = _map(map['chain']);
    return TraceData(
      batch: Batch.fromJson(map['batch']),
      comparison: TraceComparison.fromJson(map['comparison']),
      ancestors: _list(map['ancestors'])
          .map(TraceNode.fromJson)
          .toList(growable: false),
      children: _list(map['children'])
          .map(TraceNode.fromJson)
          .toList(growable: false),
      movements: _list(map['movements'])
          .map(Movement.fromJson)
          .toList(growable: false),
      nodes:
          _list(chain['nodes']).map(TraceNode.fromJson).toList(growable: false),
      currentIndex: _int(chain['current_index']),
    );
  }
}

class InviteInfo {
  const InviteInfo({
    required this.code,
    required this.status,
    required this.qrPayload,
    required this.generation,
    this.joinUrl,
  });

  final String? code;
  final String status;
  final String? qrPayload;
  final String? joinUrl;
  final int generation;

  bool get isActive => status == 'active' && (code?.isNotEmpty ?? false);

  factory InviteInfo.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return InviteInfo(
      code: map['code']?.toString(),
      status: _str(map['status'], 'active'),
      qrPayload: map['qr_payload']?.toString(),
      joinUrl: map['join_url']?.toString(),
      generation: _int(map['generation'], 1),
    );
  }
}

class MemberInfo {
  const MemberInfo(
      {required this.deviceId,
      required this.name,
      required this.role,
      required this.isCurrent,
      required this.joinedAt,
      this.lastSeenAt});

  final String deviceId;
  final String name;
  final String role;
  final bool isCurrent;
  final String joinedAt;
  final String? lastSeenAt;

  bool get isOwner => role == 'owner';

  factory MemberInfo.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return MemberInfo(
      deviceId: _str(map['device_id']),
      name: _str(map['name'], '施工设备'),
      role: _str(map['role'], 'member'),
      isCurrent: _bool(map['is_current']),
      joinedAt: _str(map['joined_at']),
      lastSeenAt: map['last_seen_at']?.toString(),
    );
  }
}

class ProjectStats {
  const ProjectStats({
    this.pieces = 0,
    this.batches = 0,
    this.lShapeBatches = 0,
    this.availableBatches = 0,
    this.areaMm2 = 0,
    this.lastActivityAt,
  });

  final int pieces;
  final int batches;
  final int lShapeBatches;
  final int availableBatches;
  final int areaMm2;
  final String? lastActivityAt;

  factory ProjectStats.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return ProjectStats(
      pieces: _int(map['total_pieces']),
      batches: _int(map['batch_count']),
      lShapeBatches: _int(map['l_shape_batches']),
      availableBatches: _int(map['available_batches']),
      areaMm2: _int(map['total_area_mm2']),
      lastActivityAt: map['last_activity_at']?.toString(),
    );
  }
}

class JoinedProject {
  JoinedProject({
    required this.id,
    required this.name,
    required this.token,
    this.code = '',
    this.role = 'member',
    this.defaultUnit = 'mm',
    this.minUsableMm = 50,
    this.stats = const ProjectStats(),
  });

  final String id;
  final String name;
  final String token;

  /// 项目特征码（4 位）：项目名允许重复，界面上靠它区分同名项目
  final String code;
  final String role;
  final String defaultUnit;
  final int minUsableMm;
  final ProjectStats stats;

  bool get isOwner => role == 'owner';

  /// 展示用：「金域蓝湾 3 栋 1802 · K7M2」
  String get title => code.isEmpty ? name : '$name · $code';

  JoinedProject copyWith(
      {String? name,
      String? role,
      String? defaultUnit,
      int? minUsableMm,
      ProjectStats? stats}) {
    return JoinedProject(
      id: id,
      name: name ?? this.name,
      token: token,
      code: code,
      role: role ?? this.role,
      defaultUnit: defaultUnit ?? this.defaultUnit,
      minUsableMm: minUsableMm ?? this.minUsableMm,
      stats: stats ?? this.stats,
    );
  }

  factory JoinedProject.fromApi(dynamic json, String token) {
    final Map<String, dynamic> map = _map(json);
    return JoinedProject(
      id: _str(map['id']),
      name: _str(map['name'], '未命名项目'),
      token: token,
      code: _str(map['code']),
      role: _str(map['role'], 'member'),
      defaultUnit: _str(map['default_unit'], 'mm'),
      minUsableMm: _int(map['min_usable_mm'], 50),
      stats: ProjectStats.fromJson(map['stats']),
    );
  }

  factory JoinedProject.fromStorage(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return JoinedProject(
      id: _str(map['id']),
      name: _str(map['name'], '未命名项目'),
      token: _str(map['token']),
      code: _str(map['code']),
      role: _str(map['role'], 'member'),
      defaultUnit: _str(map['default_unit'], 'mm'),
      minUsableMm: _int(map['min_usable_mm'], 50),
      stats: ProjectStats.fromJson(map['stats']),
    );
  }

  Map<String, dynamic> toStorage() => <String, dynamic>{
        'id': id,
        'name': name,
        'code': code,
        'token': token,
        'role': role,
        'default_unit': defaultUnit,
        'min_usable_mm': minUsableMm,
        'stats': <String, dynamic>{
          'total_pieces': stats.pieces,
          'batch_count': stats.batches,
          'l_shape_batches': stats.lShapeBatches,
          'available_batches': stats.availableBatches,
          'total_area_mm2': stats.areaMm2,
          'last_activity_at': stats.lastActivityAt,
        },
      };
}

class ProjectHome {
  const ProjectHome(
      {required this.stats,
      required this.recentMovements,
      required this.knownLocations,
      required this.role});

  final ProjectStats stats;
  final List<Movement> recentMovements;
  final List<String> knownLocations;
  final String role;

  factory ProjectHome.fromJson(dynamic json) {
    final Map<String, dynamic> map = _map(json);
    return ProjectHome(
      stats: ProjectStats.fromJson(map['stats']),
      recentMovements: _list(map['recent_movements'])
          .map(Movement.fromJson)
          .toList(growable: false),
      knownLocations: _list(map['known_locations'])
          .map((dynamic e) => '$e')
          .toList(growable: false),
      role: _str(_map(map['project'])['role'], 'member'),
    );
  }
}
