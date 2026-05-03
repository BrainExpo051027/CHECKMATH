import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../widgets/profile_modal.dart';
import 'achievements_screen.dart';
import 'game_screen.dart';
import 'leaderboard_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _nameCtrl = TextEditingController();
  final _oppNameCtrl = TextEditingController();
  final _roomCodeCtrl = TextEditingController();
  bool _vsPlayer = false;
  bool _onlineMode = false;
  String _difficulty = 'medium';
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  String _usernameDisplay = 'Player';
  int? _userId;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadPrefs();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _oppNameCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      final username = p.getString('checkmath_username') ?? '';
      final profileName = p.getString('checkmath_profile_name') ?? username;
      _nameCtrl.text = username;
      _usernameDisplay = profileName.isNotEmpty ? profileName : 'Player';
      _userId = p.getInt('checkmath_user_id');
    });
  }

  Future<void> _saveName() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('checkmath_username', _nameCtrl.text.trim());
  }

  Future<int?> _tryGetUserId() async {
    final p = await SharedPreferences.getInstance();
    final cached = p.getInt('checkmath_user_id');
    if (cached != null) return cached;
    try {
      final name = _usernameDisplay.trim().isEmpty ? 'Player' : _usernameDisplay.trim();
      final data = await resolveUser(name);
      final id = (data['user_id'] as num).toInt();
      await p.setInt('checkmath_user_id', id);
      return id;
    } catch (_) {
      return p.getInt('checkmath_user_id');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF302E2B),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 700;
            if (isWide) return _buildWideLayout();
            return _buildNarrowLayout();
          },
        ),
      ),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      children: [
        // Left brand panel
        Expanded(
          flex: 2,
          child: Container(
            color: const Color(0xFF262421),
            child: _buildBrandPanel(),
          ),
        ),
        // Right form panel
        Expanded(
          flex: 3,
          child: _buildFormPanel(),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHeader(),
          _buildFormPanel(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 32),
      color: const Color(0xFF262421),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.settings, color: Color(0xFF888888)),
                tooltip: 'Server Settings',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
            ],
          ),
          _buildLogo(size: 64),
          const SizedBox(height: 12),
          const Text(
            'CheckMath',
            style: TextStyle(
              color: Color(0xFFD4D4D4),
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Checkers meets Mathematics',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandPanel() {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildLogo(size: 96),
          const SizedBox(height: 24),
          const Text(
            'CheckMath',
            style: TextStyle(
              color: Color(0xFFD4D4D4),
              fontSize: 36,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Checkers meets Mathematics',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          _buildFeatureItem(Icons.calculate, 'Land on operators to score'),
          const SizedBox(height: 16),
          _buildFeatureItem(Icons.smart_toy, 'Challenge the AI bot'),
          const SizedBox(height: 16),
          _buildFeatureItem(Icons.emoji_events, 'Earn achievements'),
          const SizedBox(height: 16),
          _buildFeatureItem(Icons.leaderboard, 'Climb the leaderboard'),
        ],
      ),
    );
  }

  Widget _buildLogo({double size = 72}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF739552),
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF739552).withValues(alpha: 0.4),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Text(
          '✦',
          style: TextStyle(
            fontSize: size * 0.5,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF739552), size: 20),
        const SizedBox(width: 12),
        Text(
          text,
          style: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildFormPanel() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Profile banner
          _buildProfileBanner(),
          const SizedBox(height: 24),

          // Game Mode
          const Text(
            'GAME MODE',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _modeChip('vs_ai', '🤖  Vs Bot'),
              const SizedBox(width: 8),
              _modeChip('local_pvp', '👥  Local PvP'),
              if (_userId != null) ...[
                const SizedBox(width: 8),
                _modeChip('online_pvp', '🌐  Online'),
              ],
            ],
          ),
          const SizedBox(height: 24),

          if (_onlineMode) ...[
            _buildOnlinePanel(),
            const SizedBox(height: 28),
          ] else if (_vsPlayer) ...[
            const Text(
              'PLAYER 2 NAME',
              style: TextStyle(
                color: Color(0xFF888888),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _oppNameCtrl,
              style: const TextStyle(color: Color(0xFFD4D4D4)),
              decoration: InputDecoration(
                hintText: 'Enter player 2 name…',
                hintStyle: const TextStyle(color: Color(0xFF555555)),
                filled: true,
                fillColor: const Color(0xFF262421),
                prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF888888), size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF3E3B37)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF3E3B37)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF739552), width: 2),
                ),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 28),
          ] else ...[
            // Difficulty
            const Text(
              'DIFFICULTY',
              style: TextStyle(
                color: Color(0xFF888888),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _difficultyChip('easy', '🟢  Easy', 'Random moves'),
                const SizedBox(width: 8),
                _difficultyChip('medium', '🟡  Medium', 'Greedy AI'),
                const SizedBox(width: 8),
                _difficultyChip('hard', '🔴  Hard', 'Minimax AI'),
              ],
            ),
            const SizedBox(height: 36),
          ],

          // Play button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF739552),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 4,
              shadowColor: const Color(0xFF739552).withValues(alpha: 0.5),
            ),
            onPressed: () async {
              final nav = Navigator.of(context);
              await _saveName();
              if (!mounted) return;
              if (_onlineMode) {
                _showOnlineDialog();
                return;
              }
              nav.push(
                MaterialPageRoute<void>(
                  builder: (ctx) => GameScreen(
                    difficulty: _difficulty,
                    username: _usernameDisplay.trim().isEmpty
                        ? 'Player 1'
                        : _usernameDisplay.trim(),
                    gameMode: _vsPlayer ? 'local_pvp' : 'vs_ai',
                    opponentName: _vsPlayer
                        ? (_oppNameCtrl.text.trim().isEmpty
                            ? 'Player 2'
                            : _oppNameCtrl.text.trim())
                        : null,
                  ),
                ),
              );
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_arrow_rounded, size: 24),
                SizedBox(width: 8),
                Text(
                  'Play Now',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Secondary buttons
          Row(
            children: [
              Expanded(
                child: _secondaryButton(
                  icon: Icons.leaderboard,
                  label: 'Leaderboard',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (ctx) => const LeaderboardScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _secondaryButton(
                  icon: Icons.emoji_events,
                  label: 'Achievements',
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    await _saveName();
                    final uid = await _tryGetUserId();
                    if (!mounted) return;
                    nav.push(
                      MaterialPageRoute<void>(
                        builder: (ctx) => AchievementsScreen(
                          username: _nameCtrl.text.trim().isEmpty ? 'Player 1' : _nameCtrl.text.trim(),
                          userId: uid,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // API Settings subtle link
          Center(
            child: TextButton.icon(
              onPressed: _apiSettings,
              icon: const Icon(Icons.settings_ethernet,
                  size: 14, color: Color(0xFF555555)),
              label: const Text(
                'API Settings',
                style: TextStyle(color: Color(0xFF555555), fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeChip(String mode, String label) {
    bool selected;
    if (mode == 'vs_ai') {
      selected = !_vsPlayer && !_onlineMode;
    } else if (mode == 'local_pvp') {
      selected = _vsPlayer;
    } else {
      selected = _onlineMode;
    }
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _vsPlayer = mode == 'local_pvp';
          _onlineMode = mode == 'online_pvp';
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF739552) : const Color(0xFF262421),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? const Color(0xFF739552)
                  : const Color(0xFF3E3B37),
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF888888),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildProfileBanner() {
    return GestureDetector(
      onTap: () async {
        await showProfileModal(context);
        if (mounted) await _loadPrefs();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF262421),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF3E3B37)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF739552),
              child: Text(
                _usernameDisplay.isNotEmpty ? _usernameDisplay[0].toUpperCase() : 'P',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _usernameDisplay.isEmpty ? 'Player' : _usernameDisplay,
                    style: const TextStyle(
                      color: Color(0xFFD4D4D4),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    _userId != null ? 'Signed In' : 'Guest',
                    style: TextStyle(
                      color: _userId != null ? const Color(0xFF739552) : const Color(0xFF888888),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.person_outline, color: Color(0xFF888888), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildOnlinePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'ONLINE MULTIPLAYER',
          style: TextStyle(
            color: Color(0xFF888888),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF739552),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _showCreateRoomDialog,
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Create Room'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFBBBBBB),
                  side: const BorderSide(color: Color(0xFF3E3B37)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _showJoinRoomDialog,
                icon: const Icon(Icons.login, size: 18),
                label: const Text('Join Room'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _roomCodeCtrl,
          style: const TextStyle(color: Color(0xFFD4D4D4)),
          decoration: InputDecoration(
            hintText: 'Enter 4-digit room code…',
            hintStyle: const TextStyle(color: Color(0xFF555555)),
            filled: true,
            fillColor: const Color(0xFF262421),
            prefixIcon: const Icon(Icons.meeting_room, color: Color(0xFF888888), size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF3E3B37)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF3E3B37)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF739552), width: 2),
            ),
          ),
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  void _showCreateRoomDialog() {
    final code = List.generate(4, (_) => (Random().nextInt(10))).join();
    _roomCodeCtrl.text = code;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF262421),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Create Online Room', style: TextStyle(color: Color(0xFFD4D4D4))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Share this room code with a friend on the same WiFi network.',
              style: TextStyle(color: Color(0xFFBBBBBB)),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1C1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF739552)),
              ),
              child: Text(
                code,
                style: const TextStyle(
                  color: Color(0xFF739552),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF888888))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF739552),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _enterOnlineGame(isHost: true, roomCode: code);
            },
            child: const Text('Start Room'),
          ),
        ],
      ),
    );
  }

  void _showJoinRoomDialog() {
    final code = _roomCodeCtrl.text.trim();
    if (code.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid 4-digit room code'),
          backgroundColor: Color(0xFF8B3A3A),
        ),
      );
      return;
    }
    _enterOnlineGame(isHost: false, roomCode: code);
  }

  void _showOnlineDialog() {
    final code = _roomCodeCtrl.text.trim();
    if (code.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid 4-digit room code'),
          backgroundColor: Color(0xFF8B3A3A),
        ),
      );
      return;
    }
    _enterOnlineGame(isHost: false, roomCode: code);
  }

  void _enterOnlineGame({required bool isHost, String? roomCode}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => GameScreen(
          difficulty: 'medium',
          username: _usernameDisplay.trim().isEmpty ? 'Player 1' : _usernameDisplay.trim(),
          gameMode: 'online_pvp',
          opponentName: isHost ? 'Guest' : 'Host',
          roomCode: roomCode,
          isOnlineHost: isHost,
        ),
      ),
    );
  }

  Widget _difficultyChip(String value, String label, String subLabel) {
    final selected = _difficulty == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _difficulty = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF739552) : const Color(0xFF262421),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? const Color(0xFF739552)
                  : const Color(0xFF3E3B37),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  color:
                      selected ? Colors.white : const Color(0xFF888888),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                subLabel,
                style: TextStyle(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.75)
                      : const Color(0xFF555555),
                  fontSize: 10,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _secondaryButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFBBBBBB),
        side: const BorderSide(color: Color(0xFF3E3B37)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }

  Future<void> _apiSettings() async {
    final current = await resolveBaseUrl();
    final ctrl = TextEditingController(text: current);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF262421),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'API Base URL',
          style: TextStyle(color: Color(0xFFD4D4D4)),
        ),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Color(0xFFD4D4D4)),
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: 'http://127.0.0.1:8765',
            hintStyle: const TextStyle(color: Color(0xFF555555)),
            filled: true,
            fillColor: const Color(0xFF302E2B),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF3E3B37)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF888888))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF739552),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await setApiBaseUrl(ctrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('API URL saved'),
            backgroundColor: Color(0xFF739552),
          ),
        );
      }
    }
  }
}
