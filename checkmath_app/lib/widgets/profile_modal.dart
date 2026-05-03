import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../screens/auth_screen.dart';

class ProfileModal extends StatefulWidget {
  const ProfileModal({super.key});

  @override
  State<ProfileModal> createState() => _ProfileModalState();
}

class _ProfileModalState extends State<ProfileModal> {
  bool _loading = true;
  Map<String, dynamic>? _stats;
  bool _googlePlay = false;
  String _displayName = 'Player';
  bool _editingName = false;
  int? _userId;
  final _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final p = await SharedPreferences.getInstance();
    final userId = p.getInt('checkmath_user_id');
    setState(() {
      _displayName = p.getString('checkmath_profile_name') ?? p.getString('checkmath_username') ?? 'Player';
      _googlePlay = p.getBool('checkmath_google_play') ?? false;
      _nameCtrl.text = _displayName;
      _userId = userId;
    });

    if (userId != null) {
      try {
        final data = await fetchProfile(userId);
        if (mounted) {
          setState(() {
            _stats = data;
            _loading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    } else {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveDisplayName() async {
    final newName = _nameCtrl.text.trim();
    if (newName.isEmpty || newName == _displayName) {
      if (mounted) setState(() => _editingName = false);
      return;
    }

    // Display name is purely cosmetic — it only updates checkmath_profile_name.
    // The login credential (checkmath_username) is never changed here.
    final p = await SharedPreferences.getInstance();
    await p.setString('checkmath_profile_name', newName);

    if (mounted) {
      setState(() {
        _displayName = newName;
        _editingName = false;
      });
    }
  }

  Future<void> _toggleGooglePlay(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('checkmath_google_play', v);
    setState(() => _googlePlay = v);
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF262421),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Log Out', style: TextStyle(color: Color(0xFFD4D4D4))),
        content: const Text(
          'Are you sure you want to log out?',
          style: TextStyle(color: Color(0xFF888888)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF888888))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4574B),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final p = await SharedPreferences.getInstance();
    await p.remove('checkmath_user_id');
    await p.remove('checkmath_profile_name');
    // Keep checkmath_username so the login field is pre-filled

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF262421),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Profile',
                  style: TextStyle(
                    color: Color(0xFFD4D4D4),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF888888)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            CircleAvatar(
              radius: 36,
              backgroundColor: const Color(0xFF739552),
              child: Text(
                _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'P',
                style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            if (_editingName) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      style: const TextStyle(color: Color(0xFFD4D4D4)),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF302E2B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.check, color: Color(0xFF739552)),
                    onPressed: _saveDisplayName,
                  ),
                ],
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _displayName,
                    style: const TextStyle(
                      color: Color(0xFFD4D4D4),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => setState(() => _editingName = true),
                    child: const Icon(Icons.edit, size: 16, color: Color(0xFF888888)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            if (_loading)
              const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF739552)),
              )
            else if (_stats != null) ...[
              _statRow('Total Games', '${_stats!['total_games'] ?? 0}'),
              _statRow('Wins', '${_stats!['wins'] ?? 0}'),
              _statRow('Win Rate', '${_stats!['win_rate'] ?? 0.0}%'),
            ] else ...[
              const Text(
                'Play games to see stats here',
                style: TextStyle(color: Color(0xFF888888), fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF302E2B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF3E3B37)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_sync, size: 18, color: Color(0xFF888888)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Save progress in Google Play account',
                      style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 12),
                    ),
                  ),
                  Switch(
                    value: _googlePlay,
                    onChanged: _toggleGooglePlay,
                    activeColor: const Color(0xFF739552),
                  ),
                ],
              ),
            ),
            if (_userId != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFD4574B),
                    side: const BorderSide(color: Color(0xFFD4574B)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.logout, size: 16),
                  label: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.w600)),
                  onPressed: _logout,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF888888), fontSize: 13)),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFD4D4D4),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showProfileModal(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (_) => const ProfileModal(),
  );
}
