import 'api_client.dart';
import 'formatters.dart';
import 'models.dart';
import 'session.dart';

/// Typed gateway for one project — keeps pages free of path/query strings.
class ProjectApi {
  ProjectApi(this.session, this.project);

  final Session session;
  final JoinedProject project;

  ApiClient get _api => session.api;
  String get _base => '/api/projects/${project.id}';

  Future<ProjectHome> home() async {
    final dynamic json = await _api.get('$_base/summary', projectToken: project.token);
    return ProjectHome.fromJson(json);
  }

  Future<BatchPage> inventory({
    String? q,
    String? shapeType,
    String? sourceType,
    String? location,
    int? minQuantity,
    int? maxQuantity,
    int? minShortMm,
    int? maxShortMm,
    int? minLongMm,
    int? maxLongMm,
    bool onlyAvailable = true,
    String sort = 'created_desc',
    int page = 1,
    int pageSize = 20,
  }) async {
    final Map<String, String> query = <String, String>{
      'page': '$page',
      'page_size': '$pageSize',
      'sort': sort,
      'only_available': '$onlyAvailable',
    };
    if (q != null && q.trim().isNotEmpty) query['q'] = q.trim();
    if (shapeType != null) query['shape_type'] = shapeType;
    if (sourceType != null) query['source_type'] = sourceType;
    if (location != null && location.isNotEmpty) query['location'] = location;
    if (minQuantity != null) query['min_quantity'] = '$minQuantity';
    if (maxQuantity != null) query['max_quantity'] = '$maxQuantity';
    if (minShortMm != null) query['min_short_mm'] = '$minShortMm';
    if (maxShortMm != null) query['max_short_mm'] = '$maxShortMm';
    if (minLongMm != null) query['min_long_mm'] = '$minLongMm';
    if (maxLongMm != null) query['max_long_mm'] = '$maxLongMm';
    final dynamic json = await _api.get('$_base/inventory', query: query, projectToken: project.token);
    return BatchPage.fromJson(json);
  }

  Future<Batch> createBatch({
    required String length,
    required String width,
    required int quantity,
    required String unit,
    String? location,
    String? note,
  }) async {
    final dynamic json = await _api.post(
      '$_base/inventory',
      body: <String, dynamic>{
        'length': length,
        'width': width,
        'quantity': quantity,
        'unit': unit,
        'location': location ?? '',
        'note': note ?? '',
      },
      projectToken: project.token,
    );
    return Batch.fromJson((json as Map)['batch']);
  }

  /// 修改项目设置。只传要改的字段，其余留 null 表示不动。
  /// 后端 PATCH 只允许拥有者调用。
  Future<JoinedProject> updateProject({
    String? name,
    String? defaultUnit,
    int? minUsableMm,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (defaultUnit != null) body['default_unit'] = defaultUnit;
    if (minUsableMm != null) body['min_usable_mm'] = minUsableMm;
    final dynamic json =
        await _api.patch(_base, body: body, projectToken: project.token);
    return JoinedProject.fromApi((json as Map)['project'], project.token);
  }

  Future<Batch> updateBatch(String batchId, Map<String, dynamic> payload) async {
    final dynamic json = await _api.patch('$_base/inventory/$batchId', body: payload, projectToken: project.token);
    return Batch.fromJson((json as Map)['batch']);
  }

  /// 整砖批量使用（不切割）：一次扣 N 片。
  Future<Batch> consumeBatch(
    String batchId, {
    required int quantity,
    String note = '',
  }) async {
    final dynamic json = await _api.post(
      '$_base/inventory/$batchId/consume',
      body: <String, dynamic>{'quantity': quantity, 'note': note},
      projectToken: project.token,
    );
    return Batch.fromJson((json as Map)['batch']);
  }

  Future<MatchResult> match({
    required String length,
    required String width,
    required int quantity,
    required String unit,
    int limit = 20,
  }) async {
    final dynamic json = await _api.post(
      '$_base/match',
      body: <String, dynamic>{
        'length': length,
        'width': width,
        'quantity': quantity,
        'unit': unit,
        'limit': limit,
      },
      projectToken: project.token,
    );
    return MatchResult.fromJson(json);
  }

  /// 多尺寸一起匹配（大件优先 + 一块砖混排）。
  Future<MultiMatchResult> matchMulti({
    required List<Map<String, dynamic>> demands,
    required String unit,
  }) async {
    final dynamic json = await _api.post(
      '$_base/match-multi',
      body: <String, dynamic>{'unit': unit, 'demands': demands},
      projectToken: project.token,
    );
    return MultiMatchResult.fromJson(json);
  }

  /// 多尺寸一次确认：一次扣多块砖，每块可切多种尺寸。
  Future<Map<String, dynamic>> confirmMulti({
    required List<Map<String, dynamic>> blocks,
    String note = '',
  }) async {
    final dynamic json = await _api.post(
      '$_base/usage/confirm-multi',
      body: <String, dynamic>{
        'idempotency_key': newIdempotencyKey(),
        'blocks': blocks,
        'note': note,
      },
      projectToken: project.token,
    );
    return Map<String, dynamic>.from(json as Map);
  }

  Future<UsageResult> confirm({
    required String idempotencyKey,
    required String length,
    required String width,
    required int quantity,
    required String unit,
    required List<Map<String, dynamic>> allocations,
    String note = '',
  }) async {
    final dynamic json = await _api.post(
      '$_base/usage/confirm',
      body: <String, dynamic>{
        'idempotency_key': idempotencyKey,
        'length': length,
        'width': width,
        'quantity': quantity,
        'unit': unit,
        'allocations': allocations,
        'note': note,
      },
      projectToken: project.token,
      timeout: const Duration(seconds: 30),
    );
    return UsageResult.fromJson(json);
  }

  Future<MovementPage> movements({String? type, String? batchId, int page = 1, int pageSize = 20}) async {
    final Map<String, String> query = <String, String>{'page': '$page', 'page_size': '$pageSize'};
    if (type != null && type.isNotEmpty) query['type'] = type;
    if (batchId != null && batchId.isNotEmpty) query['batch_id'] = batchId;
    final dynamic json = await _api.get('$_base/movements', query: query, projectToken: project.token);
    return MovementPage.fromJson(json);
  }

  Future<TraceData> trace(String batchId) async {
    final dynamic json = await _api.get('$_base/trace/$batchId', projectToken: project.token);
    return TraceData.fromJson(json);
  }

  Future<InviteInfo> invite() async {
    final dynamic json = await _api.get('$_base/invite', projectToken: project.token);
    return InviteInfo.fromJson((json as Map)['invite']);
  }

  Future<InviteInfo> revokeInvite() async {
    final dynamic json = await _api.post('$_base/invite/revoke', body: <String, dynamic>{}, projectToken: project.token);
    return InviteInfo.fromJson((json as Map)['invite']);
  }

  Future<InviteInfo> resetInvite() async {
    final dynamic json = await _api.post('$_base/invite/reset', body: <String, dynamic>{}, projectToken: project.token);
    return InviteInfo.fromJson((json as Map)['invite']);
  }

  Future<List<MemberInfo>> members() async {
    final dynamic json = await _api.get('$_base/members', projectToken: project.token);
    final List<dynamic> items = (json as Map)['items'] as List<dynamic>? ?? <dynamic>[];
    return items.map(MemberInfo.fromJson).toList(growable: false);
  }

  Future<void> removeMember(String deviceId) async {
    await _api.delete('$_base/members/$deviceId', projectToken: project.token);
  }

  Future<Map<String, dynamic>> nameAvailable(String name) async {
    final dynamic json = await _api.get(
      '/api/projects/name-available',
      query: <String, String>{'name': name},
      withDeviceSecret: true,
    );
    return Map<String, dynamic>.from(json as Map);
  }

  String exportUrl({String? type}) {
    final Map<String, String> query = <String, String>{'project': project.id};
    if (type != null) query['type'] = type;
    return '${session.serverUrl}/api/projects/${project.id}/movements/export';
  }
}
