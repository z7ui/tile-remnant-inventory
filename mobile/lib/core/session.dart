import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'config.dart';
import 'invite.dart';
import 'models.dart';

/// Hardware backed storage for the device secret and project tokens.
class SecureStore {
  SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  Future<String?> read(String key) => _storage.read(key: key);
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  Future<void> delete(String key) => _storage.delete(key: key);
  Future<void> clear() => _storage.deleteAll();
}

/// Small, non sensitive preferences (last unit / location / cut option).
class UserPrefs {
  UserPrefs(this._prefs);

  final SharedPreferences _prefs;

  String unitFor(String projectId, String fallback) => _prefs.getString('unit_$projectId') ?? fallback;

  Future<void> setUnit(String projectId, String unit) => _prefs.setString('unit_$projectId', unit);

  String? lastLocation(String projectId) => _prefs.getString('location_$projectId');

  Future<void> setLastLocation(String projectId, String location) =>
      _prefs.setString('location_$projectId', location);

  String cutOptionFor(String projectId) => _prefs.getString('cut_$projectId') ?? 'long_side_cut';

  Future<void> setCutOption(String projectId, String option) => _prefs.setString('cut_$projectId', option);

  String remnantActionFor(String projectId) => _prefs.getString('remnant_$projectId') ?? 'store';

  Future<void> setRemnantAction(String projectId, String action) => _prefs.setString('remnant_$projectId', action);
}

class Session extends ChangeNotifier {
  Session({required SecureStore store, required UserPrefs prefs})
      : _store = store,
        prefs = prefs,
        api = ApiClient(baseUrl: AppConfig.defaultBaseUrl);

  static const String _kServer = 'server_url';
  static const String _kDeviceId = 'device_id';
  static const String _kDeviceSecret = 'device_secret';
  static const String _kProjects = 'joined_projects';

  final SecureStore _store;
  final UserPrefs prefs;
  ApiClient api;

  String serverUrl = AppConfig.defaultBaseUrl;
  String? deviceId;
  String? deviceSecret;
  List<JoinedProject> projects = <JoinedProject>[];
  JoinedProject? current;
  bool loading = true;
  bool offline = false;
  String? error;

  /// Persists the server address before a session exists (first run / wrong host).
  static Future<void> persistServerUrl(String url) async {
    final SecureStore store = SecureStore();
    await store.write(_kServer, url.trim().replaceAll(RegExp(r'/+$'), ''));
  }

  static Future<Session> create() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Session session = Session(store: SecureStore(), prefs: UserPrefs(prefs));
    await session.bootstrap();
    return session;
  }

  Future<void> bootstrap() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      serverUrl = await _store.read(_kServer) ?? AppConfig.defaultBaseUrl;
      api = ApiClient(baseUrl: serverUrl)..deviceId = null..deviceSecret = null;
      deviceId = await _store.read(_kDeviceId);
      deviceSecret = await _store.read(_kDeviceSecret);

      if (deviceId == null || deviceSecret == null) {
        await _registerDevice();
      } else {
        api.deviceId = deviceId;
        api.deviceSecret = deviceSecret;
      }

      final String? raw = await _store.read(_kProjects);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
        projects = decoded.map(JoinedProject.fromStorage).where((JoinedProject p) => p.token.isNotEmpty).toList();
      }

      try {
        await refreshProjects();
        offline = false;
      } on ApiException catch (e) {
        offline = e.isNetwork;
        if (projects.isEmpty) error = e.message;
      }
    } on ApiException catch (e) {
      error = e.message;
      offline = e.isNetwork;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _registerDevice() async {
    final dynamic response = await api.post(
      '/api/devices/register',
      body: <String, dynamic>{
        'name': '工地手机',
        'platform': defaultTargetPlatform == TargetPlatform.android ? 'android' : 'other',
        'app_version': AppConfig.appVersion,
      },
      withDeviceId: false,
    );
    final Map<String, dynamic> map = Map<String, dynamic>.from(response as Map);
    deviceId = map['device_id'] as String;
    deviceSecret = map['device_secret'] as String;
    api.deviceId = deviceId;
    api.deviceSecret = deviceSecret;
    await _store.write(_kDeviceId, deviceId!);
    await _store.write(_kDeviceSecret, deviceSecret!);
  }

  Future<void> refreshProjects() async {
    final dynamic response = await api.get('/api/projects', withDeviceSecret: true);
    final List<dynamic> items = (response as Map)['items'] as List<dynamic>? ?? <dynamic>[];
    final Map<String, JoinedProject> byId = <String, JoinedProject>{
      for (final JoinedProject project in projects) project.id: project,
    };
    final List<JoinedProject> merged = <JoinedProject>[];
    for (final dynamic item in items) {
      final Map<String, dynamic> map = Map<String, dynamic>.from(item as Map);
      final String id = '${map['id']}';
      final JoinedProject? local = byId[id];
      if (local == null) continue; // no token -> cannot access, needs a new invite
      merged.add(JoinedProject.fromApi(map, local.token));
    }
    projects = merged;
    current = _findCurrent();
    await _persistProjects();
    notifyListeners();
  }

  JoinedProject? _findCurrent() {
    if (current == null) return projects.isEmpty ? null : projects.first;
    for (final JoinedProject project in projects) {
      if (project.id == current!.id) return project;
    }
    return projects.isEmpty ? null : projects.first;
  }

  Future<void> _persistProjects() async {
    final String raw = jsonEncode(projects.map((JoinedProject p) => p.toStorage()).toList());
    await _store.write(_kProjects, raw);
  }

  Future<void> setServer(String url) async {
    final String normalised = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (normalised == serverUrl) return;
    await _store.write(_kServer, normalised);
    serverUrl = normalised;
    api.baseUrl = normalised;
    // device identity is issued per server: start clean
    await _store.delete(_kDeviceId);
    await _store.delete(_kDeviceSecret);
    await _store.delete(_kProjects);
    deviceId = null;
    deviceSecret = null;
    projects = <JoinedProject>[];
    current = null;
    await bootstrap();
  }

  Future<JoinedProject> createProject(String name, String unit, int minUsableMm) async {
    final dynamic response = await api.post(
      '/api/projects',
      body: <String, dynamic>{
        'name': name,
        'default_unit': unit,
        'min_usable_mm': minUsableMm,
      },
      withDeviceSecret: true,
    );
    final Map<String, dynamic> map = Map<String, dynamic>.from(response as Map);
    final String token = map['project_token'] as String;
    final JoinedProject project = JoinedProject.fromApi(map['project'], token);
    projects = <JoinedProject>[project, ...projects];
    current = project;
    await _persistProjects();
    offline = false;
    notifyListeners();
    return project;
  }

  Future<JoinedProject> joinProject(String code, {String? server}) async {
    final String cleaned = code.trim().replaceAll(' ', '').toUpperCase();
    if (server != null && server.trim().isNotEmpty) {
      final String normalised = server.trim().replaceAll(RegExp(r'/+$'), '');
      if (normalised != serverUrl) {
        await setServer(normalised);
      }
    }
    final dynamic response = await api.post(
      '/api/projects/join',
      body: <String, dynamic>{'invite_code': cleaned},
      withDeviceSecret: true,
    );
    final Map<String, dynamic> map = Map<String, dynamic>.from(response as Map);
    final JoinedProject project = JoinedProject.fromApi(map['project'], map['project_token'] as String);
    projects = <JoinedProject>[project, ...projects.where((JoinedProject p) => p.id != project.id)];
    current = project;
    await _persistProjects();
    offline = false;
    notifyListeners();
    return project;
  }

  Future<JoinedProject> joinProjectFromPayload(String payload) async {
    final InvitePayload? invite = parseInvitePayload(payload);
    if (invite == null || !invite.isComplete) {
      throw ApiException(0, 'invalid_qr', '二维码内容不是有效的项目邀请，请让工头重新生成。');
    }
    return joinProject(invite.code, server: invite.server);
  }

  Future<void> leaveProject(JoinedProject project) async {
    await api.delete('/api/projects/${project.id}/membership', projectToken: project.token);
    projects = projects.where((JoinedProject p) => p.id != project.id).toList();
    if (current?.id == project.id) current = projects.isEmpty ? null : projects.first;
    await _persistProjects();
    notifyListeners();
  }

  Future<void> deleteProject(JoinedProject project) async {
    await api.delete('/api/projects/${project.id}', projectToken: project.token);
    projects = projects.where((JoinedProject p) => p.id != project.id).toList();
    if (current?.id == project.id) current = projects.isEmpty ? null : projects.first;
    await _persistProjects();
    notifyListeners();
  }

  Future<void> forgetLocally(JoinedProject project) async {
    projects = projects.where((JoinedProject p) => p.id != project.id).toList();
    if (current?.id == project.id) current = projects.isEmpty ? null : projects.first;
    await _persistProjects();
    notifyListeners();
  }

  void select(JoinedProject project) {
    current = project;
    notifyListeners();
  }

  void updateStats(String projectId, ProjectStats stats) {
    projects = projects
        .map((JoinedProject p) => p.id == projectId ? p.copyWith(stats: stats) : p)
        .toList();
    if (current?.id == projectId) {
      current = projects.firstWhere((JoinedProject p) => p.id == projectId);
    }
    notifyListeners();
  }
}
