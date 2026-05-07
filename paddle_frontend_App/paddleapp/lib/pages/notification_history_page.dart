import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppNotification {
  final String title;
  final String body;
  final DateTime timestamp;

  AppNotification({required this.title, required this.body, required this.timestamp});

  Map<String, dynamic> toJson() => {
        'title': title,
        'body': body,
        'ts': timestamp.millisecondsSinceEpoch,
      };

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        title: j['title'] as String,
        body: j['body'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(j['ts'] as int),
      );
}

/// Persistent notification store backed by SharedPreferences.
/// Keeps the last 50 notifications across app restarts.
class NotificationStore {
  NotificationStore._();
  static final NotificationStore instance = NotificationStore._();

  static const _key = 'notif_history';
  static const _maxItems = 50;

  final List<AppNotification> _items = [];
  bool _loaded = false;
  final List<VoidCallback> _listeners = [];

  List<AppNotification> get all => List.unmodifiable(_items.reversed.toList());
  int get unreadCount => _items.length;

  void addListener(VoidCallback l) => _listeners.add(l);
  void removeListener(VoidCallback l) => _listeners.remove(l);
  void _notify() { for (final l in List.of(_listeners)) l(); }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final list = (jsonDecode(raw) as List<dynamic>)
            .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
            .toList();
        _items.addAll(list);
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(_items.map((n) => n.toJson()).toList());
      await prefs.setString(_key, data);
    } catch (_) {}
  }

  Future<void> add(String title, String body) async {
    await _ensureLoaded();
    _items.add(AppNotification(title: title, body: body, timestamp: DateTime.now()));
    if (_items.length > _maxItems) _items.removeAt(0);
    _notify();
    await _persist();
  }

  Future<void> clear() async {
    _items.clear();
    _notify();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Call once at app startup so the first render has data already.
  Future<void> preload() => _ensureLoaded();
}

class NotificationHistoryPage extends StatefulWidget {
  const NotificationHistoryPage({super.key});

  @override
  State<NotificationHistoryPage> createState() => _NotificationHistoryPageState();
}

class _NotificationHistoryPageState extends State<NotificationHistoryPage> {
  final _store = NotificationStore.instance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _store.addListener(_rebuild);
    _store._ensureLoaded().then((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _store.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF76ACC6))),
      );
    }

    final items = _store.all;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () => _store.clear(),
              child: const Text('Clear all', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: items.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('No notifications yet', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final n = items[i];
                final diff = DateTime.now().difference(n.timestamp);
                final timeLabel = diff.inMinutes < 1
                    ? 'Just now'
                    : diff.inHours < 1
                        ? '${diff.inMinutes}m ago'
                        : diff.inDays < 1
                            ? '${diff.inHours}h ago'
                            : '${diff.inDays}d ago';
                return ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF76ACC6),
                    child: Icon(Icons.notifications, color: Colors.white, size: 18),
                  ),
                  title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(n.body),
                  trailing: Text(timeLabel,
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                );
              },
            ),
    );
  }
}
