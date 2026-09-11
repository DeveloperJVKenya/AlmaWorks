import 'dart:async';

import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/schedule/task_progress_monitor_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';

/// One notification merged from either UserNotificationQueue (targeted at
/// this uid) or AdminNotificationQueue (targeted at this role) — same
/// shape either way (see InventoryService._notifyUser/_notifyAdmins and
/// TaskProgressMonitorScreen._notifyUser/_notifyAdmins, which both write
/// to these two collections).
class _QueuedNotification {
  final String id;
  final String collection; // 'UserNotificationQueue' | 'AdminNotificationQueue'
  final String title;
  final String body;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final bool isRead;

  const _QueuedNotification({
    required this.id,
    required this.collection,
    required this.title,
    required this.body,
    required this.payload,
    required this.createdAt,
    required this.isRead,
  });

  factory _QueuedNotification.fromDoc(DocumentSnapshot doc, String collection) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return _QueuedNotification(
      id: doc.id,
      collection: collection,
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      payload: Map<String, dynamic>.from(data['payload'] as Map? ?? {}),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: data['isRead'] as bool? ?? false,
    );
  }
}

/// Real, Firestore-backed notification center — merges every notification
/// queued for the signed-in user (UserNotificationQueue, by uid) or their
/// role (AdminNotificationQueue, by targetRoles) into one chronological
/// list. Tapping one marks it read and, where the payload names a known
/// destination (currently: project date-extension requests/decisions),
/// navigates straight there — the same deep-link a tap on the OS tray
/// notification does (see main.dart's onActionReceivedMethod, which this
/// mirrors for in-app taps).
class NotificationsScreen extends StatefulWidget {
  final Logger? logger;

  const NotificationsScreen({super.key, this.logger});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final Logger _logger;
  String? _currentUid;
  String _currentRole = 'Client';

  List<_QueuedNotification> _userNotifications = [];
  List<_QueuedNotification> _adminNotifications = [];
  StreamSubscription<QuerySnapshot>? _userSub;
  StreamSubscription<QuerySnapshot>? _adminSub;
  bool _isLoading = true;

  List<_QueuedNotification> get _all {
    final combined = [..._userNotifications, ..._adminNotifications];
    combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return combined;
  }

  int get _unreadCount => _all.where((n) => !n.isRead).length;

  @override
  void initState() {
    super.initState();
    _logger = widget.logger ?? Logger();
    _logger.i('🔔 NotificationsScreen: Initialized');
    _init();
  }

  Future<void> _init() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    _currentUid = user.uid;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('Users')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        _currentRole = snap.docs.first.data()['role'] as String? ?? 'Client';
      }
    } catch (e) {
      _logger.e('❌ NotificationsScreen: failed to resolve role', error: e);
    }

    _userSub = FirebaseFirestore.instance
        .collection('UserNotificationQueue')
        .where('targetUid', isEqualTo: _currentUid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _userNotifications =
            snap.docs.map((d) => _QueuedNotification.fromDoc(d, 'UserNotificationQueue')).toList();
        _isLoading = false;
      });
    }, onError: (e) {
      _logger.e('❌ NotificationsScreen: user queue stream error', error: e);
      if (mounted) setState(() => _isLoading = false);
    });

    _adminSub = FirebaseFirestore.instance
        .collection('AdminNotificationQueue')
        .where('targetRoles', arrayContains: _currentRole)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _adminNotifications =
            snap.docs.map((d) => _QueuedNotification.fromDoc(d, 'AdminNotificationQueue')).toList();
        _isLoading = false;
      });
    }, onError: (e) {
      _logger.e('❌ NotificationsScreen: admin queue stream error', error: e);
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _adminSub?.cancel();
    _logger.i('🧹 NotificationsScreen: Disposing resources');
    super.dispose();
  }

  Future<void> _markRead(_QueuedNotification n) async {
    if (n.isRead) return;
    try {
      await FirebaseFirestore.instance.collection(n.collection).doc(n.id).update({'isRead': true});
    } catch (e) {
      _logger.e('❌ NotificationsScreen: failed to mark read', error: e);
    }
  }

  Future<void> _markAllAsRead() async {
    final unread = _all.where((n) => !n.isRead).toList();
    if (unread.isEmpty) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final n in unread) {
        batch.update(FirebaseFirestore.instance.collection(n.collection).doc(n.id), {'isRead': true});
      }
      await batch.commit();
      _logger.i('✅ NotificationsScreen: All notifications marked as read');
    } catch (e) {
      _logger.e('❌ NotificationsScreen: failed to mark all read', error: e);
    }
  }

  /// Mirrors main.dart's onActionReceivedMethod dispatch for the OS-tray
  /// tap — same payload `type`/`projectId` fields, so a notification opens
  /// the same place whether tapped here or from the system tray.
  Future<void> _handleTap(_QueuedNotification n) async {
    await _markRead(n);
    final type = n.payload['type'] as String?;
    final projectId = n.payload['projectId'] as String?;
    if (type == null || projectId == null) return;

    if (type.startsWith('project_date_extension') || type.startsWith('task_date_extension')) {
      await _openProject(projectId);
    }
  }

  Future<void> _openProject(String projectId) async {
    if (!mounted) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('Projects').doc(projectId).get();
      if (!doc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('That project no longer exists.', style: GoogleFonts.poppins()),
          ));
        }
        return;
      }
      final project = ProjectModel.fromFirestore(doc);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TaskProgressMonitorScreen(project: project, logger: _logger)),
      );
    } catch (e) {
      _logger.e('❌ NotificationsScreen: failed to open project', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Notifications', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color(0xFF0A2E5A),
        foregroundColor: Colors.white,
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: Text('Mark All Read', style: GoogleFonts.poppins(color: Colors.white)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _all.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_none_rounded, size: 56, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text('No notifications yet', style: GoogleFonts.poppins(color: Colors.grey[500])),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _all.length,
                  itemBuilder: (context, index) => _buildNotificationItem(_all[index]),
                ),
    );
  }

  Widget _buildNotificationItem(_QueuedNotification n) {
    final icon = _iconFor(n.payload['type'] as String?);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: n.isRead ? Colors.white : const Color(0xFF0A2E5A).withValues(alpha: 0.05),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: icon.$2.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon.$1, color: icon.$2, size: 20),
        ),
        title: Text(n.title,
            style: GoogleFonts.poppins(fontWeight: n.isRead ? FontWeight.normal : FontWeight.w700, fontSize: 13.5)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(n.body, style: GoogleFonts.poppins(fontSize: 12.5)),
            const SizedBox(height: 4),
            Text(_formatTimestamp(n.createdAt), style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 11)),
          ],
        ),
        trailing: n.isRead
            ? null
            : Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(color: Color(0xFF0A2E5A), shape: BoxShape.circle),
              ),
        onTap: () => _handleTap(n),
      ),
    );
  }

  (IconData, Color) _iconFor(String? type) {
    if (type == null) return (Icons.info_outline, Colors.grey);
    if (type.startsWith('project_date_extension_requested')) return (Icons.hourglass_top_rounded, Colors.orange);
    if (type.startsWith('project_date_extension_approved')) return (Icons.check_circle_outline, Colors.green);
    if (type.startsWith('project_date_extension_rejected')) return (Icons.cancel_outlined, Colors.red);
    if (type.startsWith('inventory')) return (Icons.inventory_2_outlined, Colors.brown);
    if (type.startsWith('communication')) return (Icons.mail_outline, Colors.blueAccent);
    return (Icons.info_outline, Colors.grey);
  }

  String _formatTimestamp(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}
