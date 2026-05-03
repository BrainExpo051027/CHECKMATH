import 'package:flutter/material.dart';

import '../services/api_service.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // Local tab state
  bool _localLoading = true;
  List<Map<String, dynamic>> _localRows = [];

  // Global tab state
  bool _globalLoading = false;
  String? _globalError;
  List<dynamic> _globalRows = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        if (_tabCtrl.index == 1 && _globalRows.isEmpty && !_globalLoading) {
          _loadGlobal();
        }
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
    setState(() => _localLoading = true);
    try {
      final rows = await getLocalLeaderboard();
      setState(() {
        _localRows = rows;
        _localLoading = false;
      });
    } catch (_) {
      setState(() => _localLoading = false);
    }
  }

  Future<void> _loadGlobal() async {
    setState(() {
      _globalLoading = true;
      _globalError = null;
    });
    try {
      final data = await getLeaderboard();
      setState(() {
        _globalRows = data['leaderboard'] as List<dynamic>? ?? [];
        _globalLoading = false;
      });
    } catch (e) {
      setState(() {
        _globalError = e.toString();
        _globalLoading = false;
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
          'Leaderboard',
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
                _loadGlobal();
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
            Tab(icon: Icon(Icons.public, size: 16), text: 'Global'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildLocalTab(),
          _buildGlobalTab(),
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
    if (_localRows.isEmpty) {
      return _buildEmpty(
        icon: Icons.smartphone,
        message: 'No local scores yet.\nPlay a game to get started!',
      );
    }
    return RefreshIndicator(
      color: const Color(0xFF739552),
      backgroundColor: const Color(0xFF262421),
      onRefresh: _loadLocal,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('📱  Device Leaderboard'),
          const SizedBox(height: 12),
          _buildTableHeader(showExtra: true),
          const Divider(color: Color(0xFF3E3B37)),
          for (int i = 0; i < _localRows.length; i++)
            _buildLocalRow(i, _localRows[i]),
        ],
      ),
    );
  }

  Widget _buildLocalRow(int index, Map<String, dynamic> r) {
    final isTop3 = index < 3;
    final medals = ['🥇', '🥈', '🥉'];
    final rankColor = isTop3
        ? [
            const Color(0xFFD4AF37),
            const Color(0xFFBBBBBB),
            const Color(0xFFCD7F32),
          ][index]
        : const Color(0xFF888888);

    final wins = (r['wins'] as int?) ?? 0;
    final losses = (r['losses'] as int?) ?? 0;
    final draws = (r['draws'] as int?) ?? 0;
    final totalScore = (r['total_score'] as num).toDouble();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: isTop3 ? const Color(0xFF262421) : const Color(0xFF2A2825),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isTop3
              ? rankColor.withValues(alpha: 0.3)
              : const Color(0xFF3E3B37),
          width: isTop3 ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Rank
            SizedBox(
              width: 32,
              child: isTop3
                  ? Text(medals[index],
                      style: const TextStyle(fontSize: 20))
                  : Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Color(0xFF3E3B37),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                              color: Color(0xFF888888),
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            // Name
            Expanded(
              child: Text(
                '${r['username']}',
                style: TextStyle(
                  color: isTop3
                      ? const Color(0xFFD4D4D4)
                      : const Color(0xFFAAAAAA),
                  fontWeight:
                      isTop3 ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ),
            // W/L/D
            Text(
              '${wins}W  ${losses}L  ${draws}D',
              style: const TextStyle(
                  color: Color(0xFF888888), fontSize: 11),
            ),
            const SizedBox(width: 10),
            // Score
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color:
                    const Color(0xFF739552).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${totalScore.toStringAsFixed(1)} pts',
                style: const TextStyle(
                    color: Color(0xFF9FCE6C),
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Global Tab
  // ---------------------------------------------------------------------------
  Widget _buildGlobalTab() {
    if (_globalLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF739552)),
      );
    }
    if (_globalError != null) {
      return _buildNetworkError(_globalError!, _loadGlobal);
    }
    if (_globalRows.isEmpty) {
      return _buildEmpty(
        icon: Icons.public,
        message: 'No global scores yet.',
        subtitle: 'Connect to the backend to see global rankings.',
      );
    }
    return RefreshIndicator(
      color: const Color(0xFF739552),
      backgroundColor: const Color(0xFF262421),
      onRefresh: _loadGlobal,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('🌐  Global Leaderboard'),
          const SizedBox(height: 12),
          _buildTableHeader(showExtra: false),
          const Divider(color: Color(0xFF3E3B37)),
          for (int i = 0; i < _globalRows.length; i++)
            _buildGlobalRow(i, _globalRows[i] as Map<String, dynamic>),
        ],
      ),
    );
  }

  Widget _buildGlobalRow(int index, Map<String, dynamic> r) {
    final isTop3 = index < 3;
    final medals = ['🥇', '🥈', '🥉'];
    final rankColor = isTop3
        ? [
            const Color(0xFFD4AF37),
            const Color(0xFFBBBBBB),
            const Color(0xFFCD7F32),
          ][index]
        : const Color(0xFF888888);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: isTop3 ? const Color(0xFF262421) : const Color(0xFF2A2825),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isTop3
              ? rankColor.withValues(alpha: 0.3)
              : const Color(0xFF3E3B37),
          width: isTop3 ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: isTop3
            ? Text(medals[index], style: const TextStyle(fontSize: 22))
            : Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFF3E3B37),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
        title: Text(
          '${r['username']}',
          style: TextStyle(
            color: isTop3
                ? const Color(0xFFD4D4D4)
                : const Color(0xFFAAAAAA),
            fontWeight:
                isTop3 ? FontWeight.bold : FontWeight.normal,
            fontSize: 15,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color:
                    const Color(0xFF739552).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${r['total_score']} pts',
                style: const TextStyle(
                    color: Color(0xFF9FCE6C),
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${r['wins']}W',
              style: const TextStyle(
                  color: Color(0xFF888888), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------
  Widget _buildSectionHeader(String text) {
    return Text(
      text,
      style: const TextStyle(
          color: Color(0xFFD4D4D4),
          fontSize: 15,
          fontWeight: FontWeight.bold),
    );
  }

  Widget _buildTableHeader({required bool showExtra}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const SizedBox(
              width: 42,
              child: Text('#',
                  style: TextStyle(color: Color(0xFF888888), fontSize: 11))),
          const Expanded(
            child: Text('PLAYER',
                style: TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 11,
                    letterSpacing: 1)),
          ),
          if (showExtra)
            const Text('W/L/D',
                style: TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 11,
                    letterSpacing: 1)),
          const SizedBox(width: 10),
          const Text('SCORE',
              style: TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 11,
                  letterSpacing: 1)),
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
              'Start the backend (run_backend.cmd) and connect to the same network.',
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
}
