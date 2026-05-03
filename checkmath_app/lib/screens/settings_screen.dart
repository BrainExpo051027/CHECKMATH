import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/audio_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _urlCtrl = TextEditingController();
  bool _loading = false;
  bool _bgmMuted = false;
  bool _sfxMuted = false;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadCurrentUrl();
    _loadSoundPrefs();
  }

  Future<void> _loadSoundPrefs() async {
    await AudioService().init();
    if (!mounted) return;
    setState(() {
      _bgmMuted = AudioService().isBgmMuted;
      _sfxMuted = AudioService().isSfxMuted;
    });
  }

  Future<void> _toggleBgmMuted(bool value) async {
    setState(() => _bgmMuted = value);
    AudioService().isBgmMuted = value;
  }

  Future<void> _toggleSfxMuted(bool value) async {
    setState(() => _sfxMuted = value);
    AudioService().isSfxMuted = value;
  }

  Future<void> _loadCurrentUrl() async {
    final url = await resolveBaseUrl();
    setState(() {
      _urlCtrl.text = url;
    });
  }

  Future<void> _saveUrl() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid URL'),
          backgroundColor: Color(0xFF8B3A3A),
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await setApiBaseUrl(url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Server URL saved successfully'),
            backgroundColor: Color(0xFF739552),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save URL: $e'),
            backgroundColor: Color(0xFF8B3A3A),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetToDefault() async {
    setState(() => _loading = true);
    try {
      await setApiBaseUrl('');
      await _loadCurrentUrl();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reset to default URL'),
            backgroundColor: Color(0xFF739552),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reset: $e'),
            backgroundColor: Color(0xFF8B3A3A),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF302E2B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF262421),
        foregroundColor: const Color(0xFFD4D4D4),
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFF739552),
          labelColor: const Color(0xFF9FCE6C),
          unselectedLabelColor: const Color(0xFF888888),
          tabs: const [
            Tab(icon: Icon(Icons.volume_up, size: 16), text: 'Sound'),
            Tab(icon: Icon(Icons.settings_ethernet, size: 16), text: 'Network Config'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildSoundTab(),
          _buildNetworkTab(),
        ],
      ),
    );
  }

  Widget _buildSoundTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'BACKGROUND MUSIC',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Control background music in menus and during gameplay.',
            style: TextStyle(
              color: Color(0xFFBBBBBB),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF262421),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF3E3B37)),
            ),
            child: SwitchListTile(
              value: _bgmMuted,
              onChanged: _toggleBgmMuted,
              title: const Text(
                'Mute BGM',
                style: TextStyle(color: Color(0xFFD4D4D4), fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _bgmMuted ? 'BGM Off' : 'BGM On',
                style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
              ),
              secondary: Icon(_bgmMuted ? Icons.music_off : Icons.music_note, color: const Color(0xFF888888)),
              activeColor: const Color(0xFF739552),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(color: Color(0xFF3E3B37), height: 32),
          const Text(
            'SOUND EFFECTS',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Control move and capture sounds during gameplay.',
            style: TextStyle(
              color: Color(0xFFBBBBBB),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF262421),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF3E3B37)),
            ),
            child: SwitchListTile(
              value: _sfxMuted,
              onChanged: _toggleSfxMuted,
              title: const Text(
                'Mute SFX',
                style: TextStyle(color: Color(0xFFD4D4D4), fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _sfxMuted ? 'SFX Off' : 'SFX On',
                style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
              ),
              secondary: Icon(_sfxMuted ? Icons.volume_off : Icons.volume_up, color: const Color(0xFF888888)),
              activeColor: const Color(0xFF739552),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'BACKEND SERVER',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter the IP address of the backend server for online multiplayer and account features.',
            style: TextStyle(
              color: Color(0xFFBBBBBB),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlCtrl,
            style: const TextStyle(color: Color(0xFFD4D4D4)),
            decoration: InputDecoration(
              hintText: 'http://192.168.1.x:8765',
              hintStyle: const TextStyle(color: Color(0xFF555555)),
              filled: true,
              fillColor: const Color(0xFF262421),
              prefixIcon: const Icon(Icons.dns, color: Color(0xFF888888), size: 20),
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
          ),
          const SizedBox(height: 8),
          Text(
            'Default: http://127.0.0.1:8765 (localhost)',
            style: TextStyle(
              color: const Color(0xFF666666),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 24),
          const Divider(color: Color(0xFF3E3B37), height: 32),
          const Text(
            'OFFLINE vs ONLINE',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E3A1E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF3A6A3A)),
            ),
            child: const Text(
              '✅ Works fully offline (no backend needed):\n'
              '   • VS AI  •  Local PvP  •  Achievements  •  Leaderboard\n\n'
              '🌐 Requires backend (same WiFi network):\n'
              '   • Online Multiplayer (WebSocket)\n'
              '   • Global leaderboard sync\n\n'
              '⚠️ The Python backend cannot be bundled into the APK — '
              'it must run on a PC. VS AI and Local PvP are fully self-contained in Dart.',
              style: TextStyle(
                color: Color(0xFFBBBBBB),
                fontSize: 11,
                height: 1.6,
              ),
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF888888),
                    side: const BorderSide(color: Color(0xFF3E3B37)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _loading ? null : _resetToDefault,
                  child: const Text('Reset to Default'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF739552),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _loading ? null : _saveUrl,
                  child: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
