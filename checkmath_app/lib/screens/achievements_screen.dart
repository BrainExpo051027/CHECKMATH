import 'package:flutter/material.dart';

import '../services/api_service.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({
    super.key,
    required this.username,
    this.userId,
  });

  final String username;
  final int? userId; // optional — only needed for Online tab

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // Local tab
  bool _localLoading = true;
  List<Map<String, dynamic>> _localList = [];

  // Online tab
  bool _onlineLoading = false;
  String? _onlineError;
  List<dynamic> _onlineList = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging && _tabCtrl.index == 1) {
        if (_onlineList.isEmpty && !_onlineLoading) _loadOnline();
      }
    });
    _loadLocal();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data loaders
  // ---------------------------------------------------------------------------
  Future<void> _loadLocal() async {
    if (widget.username.isEmpty) {
      setState(() {
        _localLoading = false;
        _localList = [];
      });
      return;
    }
    setState(() => _localLoading = true);
    try {
      final list = await getLocalAchievements(widget.username);
      setState(() {
        _localList = list;
        _localLoading = false;
      });
    } catch (_) {
      setState(() => _localLoading = false);
    }
  }

  Future<void> _loadOnline() async {
    if (widget.userId == null) {
      setState(() {
        _onlineError = 'No account found. Play a game while connected to the backend to create one.';
        _onlineLoading = false;
      });
      return;
    }
    setState(() {
      _onlineLoading = true;
      _onlineError = null;
    });
    try {
      final data = await getAchievements(widget.userId!);
      setState(() {
        _onlineList = data['achievements'] as List<dynamic>? ?? [];
        _onlineLoading = false;
      });
    } catch (e) {
      setState(() {
        _onlineError = e.toString();
        _onlineLoading = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF302E2B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF262421),
        foregroundColor: const Color(0xFFD4D4D4),
        elevation: 0,
        title: const Text(
          'Achievements',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              if (_tabCtrl.index == 0) {
                _loadLocal();
              } else {
                _loadOnline();
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFF739552),
          labelColor: const Color(0xFF9FCE6C),
          unselectedLabelColor: const Color(0xFF888888),
          tabs: const [
            Tab(icon: Icon(Icons.smartphone, size: 16), text: 'Local'),
            Tab(icon: Icon(Icons.cloud, size: 16), text: 'Online'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildLocalTab(),
          _buildOnlineTab(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Local Tab
  // ---------------------------------------------------------------------------
  Widget _buildLocalTab() {
    if (_localLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF739552)),
      );
    }

    final unlocked = _localList.where((a) => a['unlocked'] == true).length;
    final total = _localList.length;

    return RefreshIndicator(
      color: const Color(0xFF739552),
      backgroundColor: const Color(0xFF262421),
      onRefresh: _loadLocal,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Progress card
          _buildProgressCard(
            unlocked: unlocked,
            total: total,
            subtitle: '📱 Device achievements for ${widget.username}',
          ),
          const SizedBox(height: 16),

          // Achievement tiles
          for (final a in _localList) _buildLocalTile(a),
        ],
      ),
    );
  }

  Widget _buildLocalTile(Map<String, dynamic> a) {
    final unlocked = a['unlocked'] == true;
    final title = '${a['title']}';
    final desc = '${a['desc']}';
    final iconName = '${a['icon']}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF262421),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: unlocked
              ? const Color(0xFF739552).withValues(alpha: 0.5)
              : const Color(0xFF3E3B37),
          width: unlocked ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: unlocked
                ? const Color(0xFF739552).withValues(alpha: 0.15)
                : const Color(0xFF3A3835),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            unlocked ? _iconFromName(iconName) : Icons.lock_outline,
            color: unlocked
                ? const Color(0xFF9FCE6C)
                : const Color(0xFF555555),
            size: 24,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: unlocked
                ? const Color(0xFFD4D4D4)
                : const Color(0xFF666666),
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        subtitle: Text(
          unlocked ? desc : 'Locked — keep playing!',
          style: TextStyle(
            color: unlocked
                ? const Color(0xFF888888)
                : const Color(0xFF555555),
            fontSize: 12,
          ),
        ),
        trailing: unlocked
            ? Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      const Color(0xFF739552).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '✓ Earned',
                  style: TextStyle(
                      color: Color(0xFF9FCE6C),
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              )
            : null,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Online Tab
  // ---------------------------------------------------------------------------
  Widget _buildOnlineTab() {
    if (_onlineLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF739552)),
      );
    }
    if (_onlineError != null) {
      return _buildNetworkError(_onlineError!, _loadOnline);
    }
    if (_onlineList.isEmpty) {
      return _buildEmpty(
        icon: Icons.cloud_off,
        message: 'No online achievements yet.',
        subtitle: 'Connect to the backend to sync your progress.',
      );
    }

    final unlocked =
        _onlineList.where((a) => a['unlocked'] == true || a['unlocked'] == 1).length;
    final total = _onlineList.length;

    return RefreshIndicator(
      color: const Color(0xFF739552),
      backgroundColor: const Color(0xFF262421),
      onRefresh: _loadOnline,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildProgressCard(
            unlocked: unlocked,
            total: total,
            subtitle: '🌐 Online achievements (backend)',
          ),
          const SizedBox(height: 16),
          for (final raw in _onlineList)
            _buildOnlineTile(raw as Map<String, dynamic>),
        ],
      ),
    );
  }

  Widget _buildOnlineTile(Map<String, dynamic> a) {
    final unlocked = a['unlocked'] == true || a['unlocked'] == 1;
    final title = '${a['title']}';
    final meta = _onlineAchievementMeta(title);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF262421),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: unlocked
              ? const Color(0xFF739552).withValues(alpha: 0.5)
              : const Color(0xFF3E3B37),
          width: unlocked ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: unlocked
                ? const Color(0xFF739552).withValues(alpha: 0.15)
                : const Color(0xFF3A3835),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            unlocked ? meta.icon : Icons.lock_outline,
            color: unlocked
                ? const Color(0xFF9FCE6C)
                : const Color(0xFF555555),
            size: 24,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: unlocked
                ? const Color(0xFFD4D4D4)
                : const Color(0xFF666666),
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        subtitle: Text(
          unlocked ? meta.desc : 'Locked — keep playing!',
          style: TextStyle(
            color: unlocked
                ? const Color(0xFF888888)
                : const Color(0xFF555555),
            fontSize: 12,
          ),
        ),
        trailing: unlocked
            ? Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      const Color(0xFF739552).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '✓ Earned',
                  style: TextStyle(
                      color: Color(0xFF9FCE6C),
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              )
            : null,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------
  Widget _buildProgressCard(
      {required int unlocked, required int total, required String subtitle}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF262421),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3E3B37)),
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(
                  value: total > 0 ? unlocked / total : 0,
                  strokeWidth: 5,
                  backgroundColor: const Color(0xFF3E3B37),
                  color: const Color(0xFF739552),
                ),
              ),
              Text(
                '$unlocked/$total',
                style: const TextStyle(
                    color: Color(0xFFD4D4D4),
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your Progress',
                style: TextStyle(
                    color: Color(0xFFD4D4D4),
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                unlocked == total && total > 0
                    ? '🏆 All achievements unlocked!'
                    : '$unlocked of $total achievements earned',
                style: const TextStyle(
                    color: Color(0xFF888888), fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                    color: Color(0xFF555555), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(
      {required IconData icon, required String message, String? subtitle}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: const Color(0xFF555555)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: Color(0xFF888888), fontSize: 14),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: Color(0xFF555555), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNetworkError(String error, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 56, color: Color(0xFF888888)),
            const SizedBox(height: 16),
            const Text(
              'Backend offline',
              style: TextStyle(
                  color: Color(0xFFD4D4D4),
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Start the backend and connect to the same network.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Color(0xFF888888), fontSize: 12),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF739552),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.refresh),
              onPressed: onRetry,
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFromName(String name) {
    switch (name) {
      case 'military_tech':
        return Icons.military_tech;
      case 'local_fire_department':
        return Icons.local_fire_department;
      case 'calculate':
        return Icons.calculate;
      case 'emoji_events':
        return Icons.emoji_events;
      case 'smart_toy':
        return Icons.smart_toy;
      default:
        return Icons.emoji_events;
    }
  }

  _OnlineMeta _onlineAchievementMeta(String title) {
    switch (title) {
      case 'First Win':
        return const _OnlineMeta(
            icon: Icons.military_tech, desc: 'Win your first game');
      case 'Win Streak':
        return const _OnlineMeta(
            icon: Icons.local_fire_department,
            desc: 'Win 3 or more games');
      case 'Math Master':
        return const _OnlineMeta(
            icon: Icons.calculate, desc: 'Reach 100 total score');
      default:
        return const _OnlineMeta(
            icon: Icons.emoji_events, desc: 'Special achievement');
    }
  }
}

class _OnlineMeta {
  const _OnlineMeta({required this.icon, required this.desc});
  final IconData icon;
  final String desc;
}
