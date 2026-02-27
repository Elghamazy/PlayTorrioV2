import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/iptv_service.dart';
import 'iptv_home_screen.dart';

class IptvLoginScreen extends StatefulWidget {
  const IptvLoginScreen({super.key});

  @override
  State<IptvLoginScreen> createState() => _IptvLoginScreenState();
}

class _IptvLoginScreenState extends State<IptvLoginScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _m3uController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _checkingSession = true;
  String? _error;

  final _iptvService = IptvService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkExistingSession();
  }

  Future<void> _checkExistingSession() async {
    await _iptvService.loadSavedCredential();
    if (_iptvService.isLoggedIn && mounted) {
      _navigateToHome();
    } else if (mounted) {
      setState(() => _checkingSession = false);
    }
  }

  void _navigateToHome() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const IptvHomeScreen()),
    );
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_tabController.index == 0) {
        // Xtream
        final server = _serverController.text.trim();
        final username = _usernameController.text.trim();
        final password = _passwordController.text.trim();

        if (server.isEmpty || username.isEmpty || password.isEmpty) {
          throw Exception('Please fill in all fields');
        }

        await _iptvService.loginXtream(server, username, password);
      } else {
        // M3U
        final url = _m3uController.text.trim();
        if (url.isEmpty) throw Exception('Please enter a playlist URL');
        await _iptvService.loginM3u(url);
      }

      if (mounted) _navigateToHome();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _m3uController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.live_tv, size: 64, color: Color(0xFF00E5FF)),
              const SizedBox(height: 20),
              Text('IPTV', style: GoogleFonts.bebasNeue(fontSize: 32, color: Colors.white, letterSpacing: 4)),
              const SizedBox(height: 20),
              const CircularProgressIndicator(color: Color(0xFF00E5FF)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D1B2A), Color(0xFF0A0A0F)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo area
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1565C0), Color(0xFF00E5FF)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.live_tv, size: 48, color: Colors.white),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'IPTV',
                      style: GoogleFonts.bebasNeue(
                        fontSize: 40,
                        color: Colors.white,
                        letterSpacing: 6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Connect your IPTV service',
                      style: GoogleFonts.poppins(color: Colors.white54, fontSize: 14),
                    ),
                    const SizedBox(height: 32),

                    // Tab selector
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: const Color(0xFF1565C0),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white54,
                        labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
                        unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13),
                        tabs: const [
                          Tab(text: 'Xtream Codes'),
                          Tab(text: 'M3U Playlist'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Tab content
                    ListenableBuilder(
                      listenable: _tabController,
                      builder: (context, _) {
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _tabController.index == 0
                              ? _buildXtreamForm()
                              : _buildM3uForm(),
                        );
                      },
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Login button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF1565C0).withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _loading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                )
                              : Text(
                                  'LOGIN',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 2,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildXtreamForm() {
    return Column(
      key: const ValueKey('xtream'),
      children: [
        _buildTextField(
          controller: _serverController,
          label: 'Server URL',
          hint: 'http://example.com:8080',
          icon: Icons.dns_outlined,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 14),
        _buildTextField(
          controller: _usernameController,
          label: 'Username',
          hint: 'Enter username',
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 14),
        _buildTextField(
          controller: _passwordController,
          label: 'Password',
          hint: 'Enter password',
          icon: Icons.lock_outline,
          obscure: _obscurePassword,
          suffix: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_off : Icons.visibility,
              color: Colors.white38,
              size: 20,
            ),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
      ],
    );
  }

  Widget _buildM3uForm() {
    return Column(
      key: const ValueKey('m3u'),
      children: [
        _buildTextField(
          controller: _m3uController,
          label: 'Playlist URL',
          hint: 'https://example.com/playlist.m3u',
          icon: Icons.link,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.info_outline, size: 14, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Remote M3U URL or direct stream URL',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.poppins(color: Colors.white54, fontSize: 13),
        hintStyle: GoogleFonts.poppins(color: Colors.white24, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1565C0), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
