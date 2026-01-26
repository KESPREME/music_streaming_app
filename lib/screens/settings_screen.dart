import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/music_provider.dart';
import '../services/auth_service.dart';
import '../models/music_source.dart';
import '../screens/login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicProvider = Provider.of<MusicProvider>(context);
    final authService = Provider.of<AuthService>(context, listen: false);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark 
              ? [const Color(0xFF121212), const Color(0xFF1E1E1E), const Color(0xFF000000)]
              : [const Color(0xFFF7F7F7), const Color(0xFFFFFFFF)],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                surfaceTintColor: Colors.transparent,
                backgroundColor: Colors.transparent,
                floating: true,
                pinned: true,
                elevation: 0,
                expandedHeight: 100,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  color: isDark ? Colors.white : Colors.black,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                flexibleSpace: ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      color: Colors.black.withOpacity(0.5),
                      child: FlexibleSpaceBar(
                        titlePadding: const EdgeInsets.only(left: 50, bottom: 16),
                        title: Text(
                          'Settings',
                          style: GoogleFonts.splineSans(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 20,
                          ),
                        ),
                        background: Container(color: Colors.transparent),
                      ),
                    ),
                  ),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildSectionTitle('Music Source', isDark),
                    const SizedBox(height: 12),
                    _buildMusicSourceCard(context, musicProvider, isDark),
                    
                    const SizedBox(height: 32),
                    _buildSectionTitle('Playback Quality', isDark),
                    const SizedBox(height: 12),
                    _buildGlassCard(
                      isDark,
                      children: [
                        _buildSettingTile(
                          icon: Icons.wifi_rounded, 
                          title: 'Wi-Fi Quality', 
                          subtitle: '${musicProvider.wifiBitrate} kbps',
                          isDark: isDark,
                          onTap: () => _showBitrateDialog(context, musicProvider, true, isDark),
                        ),
                        _buildDivider(isDark),
                        _buildSettingTile(
                          icon: Icons.signal_cellular_alt_rounded, 
                          title: 'Cellular Quality', 
                          subtitle: '${musicProvider.cellularBitrate} kbps',
                          isDark: isDark,
                          onTap: () => _showBitrateDialog(context, musicProvider, false, isDark),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),
                    _buildSectionTitle('Data & Storage', isDark),
                    const SizedBox(height: 12),
                    _buildGlassCard(
                      isDark,
                      children: [
                        _buildSwitchTile(
                          icon: Icons.data_saver_on_rounded,
                          title: 'Low Data Mode',
                          subtitle: 'Reduces quality to save data',
                          value: musicProvider.isLowDataMode,
                          isDark: isDark,
                          onChanged: (val) => musicProvider.toggleLowDataMode(),
                        ),
                        _buildDivider(isDark),
                        _buildSwitchTile(
                          icon: Icons.offline_bolt_rounded,
                          title: 'Offline Mode',
                          subtitle: 'Play only downloaded songs',
                          value: musicProvider.isOfflineMode,
                          isDark: isDark,
                          onChanged: (val) => musicProvider.toggleOfflineMode(),
                        ),
                        _buildDivider(isDark),
                        _buildSettingTile(
                          icon: Icons.cleaning_services_rounded,
                          title: 'Clear Cache',
                          subtitle: 'Free up storage space',
                          isDark: isDark,
                          onTap: () async {
                            await musicProvider.clearAllCaches();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                 SnackBar(
                                   content: Text('Cache cleared', style: GoogleFonts.splineSans(color: Colors.white)),
                                   backgroundColor: Colors.grey[900],
                                 ),
                              );
                            }
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),
                    _buildSectionTitle('Account', isDark),
                    const SizedBox(height: 12),
                    _buildAccountCard(context, authService, isDark),

                    const SizedBox(height: 32),
                     _buildSectionTitle('About', isDark),
                    const SizedBox(height: 12),
                    _buildGlassCard(
                      isDark,
                      children: [
                        _buildSettingTile(
                          icon: Icons.info_outline_rounded,
                          title: 'Version',
                          subtitle: '1.0.1 (Mine Music)',
                          isDark: isDark,
                        ),
                        _buildDivider(isDark),
                        _buildSettingTile(
                          icon: Icons.code_rounded,
                          title: 'Source',
                          subtitle: 'Powered by InnerTube',
                          isDark: isDark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    _buildMadeByFooter(isDark),
                    const SizedBox(height: 50),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMadeByFooter(bool isDark) {
    return Column(
      children: [
        Image.asset(
          'assets/images/app_logo.png',
          height: 60, 
          width: 60,
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: () async {
            final uri = Uri.parse('https://github.com/KESPREME');
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: GoogleFonts.splineSans(
                  color: isDark ? Colors.white54 : Colors.black54,
                  fontSize: 14,
                ),
                children: [
                  const TextSpan(text: 'Made with ❤️ using Flutter by '),
                  TextSpan(
                    text: 'KESPREME',
                    style: GoogleFonts.splineSans(
                      color: const Color(0xFFEA80FC), // Purple accent
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.splineSans(
          color: isDark ? Colors.white54 : Colors.black54,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildGlassCard(bool isDark, {required List<Widget> children}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
         child: Container(
           decoration: BoxDecoration(
             color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
             borderRadius: BorderRadius.circular(24),
             border: Border.all(
               color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
             ),
           ),
           child: Column(
             children: children,
           ),
         ),
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 1, 
      thickness: 1, 
      color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
      indent: 56, // Align with text start
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    required bool isDark,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: isDark ? Colors.white : Colors.black, size: 20),
      ),
      title: Text(
        title, 
        style: GoogleFonts.splineSans(
          color: isDark ? Colors.white : Colors.black,
          fontWeight: FontWeight.w600,
          fontSize: 16
        )
      ),
      subtitle: subtitle != null ? Text(
        subtitle, 
        style: GoogleFonts.splineSans(
          color: isDark ? Colors.white54 : Colors.black54,
          fontSize: 13
        )
      ) : null,
      trailing: Icon(Icons.chevron_right_rounded, color: isDark ? Colors.white30 : Colors.black.withOpacity(0.3)),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    required bool isDark,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: isDark ? Colors.white : Colors.black, size: 20),
      ),
      title: Text(
        title, 
        style: GoogleFonts.splineSans(
          color: isDark ? Colors.white : Colors.black,
          fontWeight: FontWeight.w600,
          fontSize: 16
        )
      ),
      subtitle: Text(
        subtitle, 
        style: GoogleFonts.splineSans(
          color: isDark ? Colors.white54 : Colors.black54,
          fontSize: 13
        )
      ),
      activeColor: const Color(0xFFEA80FC), // Purple accent
      activeTrackColor: const Color(0xFFEA80FC).withOpacity(0.3),
      inactiveThumbColor: isDark ? Colors.grey : Colors.white,
      inactiveTrackColor: isDark ? Colors.grey[800] : Colors.grey[300],
    );
  }

  Widget _buildMusicSourceCard(BuildContext context, MusicProvider musicProvider, bool isDark) {
    final currentSource = musicProvider.currentMusicSource;
    final accentColor = const Color(0xFF00E5FF); // Cyan
    
    return _buildGlassContainer(
      isDark,
      child: Column(
        children: [
          Row(
            children: [
               Container(
                 padding: const EdgeInsets.all(12),
                 decoration: BoxDecoration(
                   color: accentColor.withOpacity(0.1),
                   borderRadius: BorderRadius.circular(16),
                 ),
                 child: Icon(
                   currentSource == MusicSource.youtube ? Icons.cloud_queue_rounded : Icons.folder_open_rounded,
                   color: accentColor,
                   size: 28,
                 ),
               ),
               const SizedBox(width: 16),
               Expanded(
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     Text(
                       currentSource.displayName,
                       style: GoogleFonts.splineSans(
                         color: isDark ? Colors.white : Colors.black,
                         fontWeight: FontWeight.bold,
                         fontSize: 16
                       ),
                     ),
                     const SizedBox(height: 2),
                     Text(
                       currentSource.description,
                       style: GoogleFonts.splineSans(
                         color: isDark ? Colors.white54 : Colors.black54,
                         fontSize: 12
                       ),
                     ),
                   ],
                 ),
               ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: MusicSource.values.map((source) {
              final isSelected = source == currentSource;
              return Expanded(
                child: GestureDetector(
                  onTap: () => musicProvider.setMusicSource(source),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: EdgeInsets.only(right: source != MusicSource.values.last ? 12 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? accentColor.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? accentColor : (isDark ? Colors.white12 : Colors.black12),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        source == MusicSource.youtube ? 'Stream' : 'Local',
                         style: GoogleFonts.splineSans(
                           color: isSelected ? accentColor : (isDark ? Colors.white : Colors.black),
                           fontWeight: FontWeight.bold,
                         ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(BuildContext context, AuthService authService, bool isDark) {
    bool isLoggedIn = authService.isLoggedIn;
    
    return _buildGlassContainer(
      isDark,
      child: InkWell(
        onTap: isLoggedIn ? null : () async {
           Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
        },
        borderRadius: BorderRadius.circular(20),
        child: Row(
          children: [
             CircleAvatar(
               radius: 24,
               backgroundColor: isLoggedIn ? Colors.redAccent.withOpacity(0.2) : (isDark ? Colors.white10 : Colors.black12),
               child: Icon(
                 isLoggedIn ? Icons.g_mobiledata_rounded : Icons.person_outline_rounded,
                 color: isLoggedIn ? Colors.redAccent : (isDark ? Colors.white : Colors.black),
                 size: 28,
               ),
             ),
             const SizedBox(width: 16),
             Expanded(
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Text(
                     isLoggedIn ? 'YouTube Account' : 'Log In to YouTube',
                     style: GoogleFonts.splineSans(
                       color: isDark ? Colors.white : Colors.black,
                       fontWeight: FontWeight.bold,
                       fontSize: 16
                     ),
                   ),
                   const SizedBox(height: 2),
                   Text(
                     isLoggedIn ? 'Connected' : 'Sync your personalized mix',
                     style: GoogleFonts.splineSans(
                       color: isDark ? Colors.white54 : Colors.black54,
                       fontSize: 12
                     ),
                   ),
                 ],
               ),
             ),
             if (isLoggedIn)
               IconButton(
                 icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                 onPressed: () async {
                    // Show confirmation
                    // For now simple logout
                    await authService.logout();
                 },
               )
             else 
               Icon(Icons.arrow_forward_ios_rounded, color: isDark ? Colors.white30 : Colors.black.withOpacity(0.3), size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassContainer(bool isDark, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
        ),
      ),
      child: child,
    );
  }

  void _showBitrateDialog(BuildContext context, MusicProvider musicProvider, bool isWifi, bool isDark) {
    final theme = Theme.of(context);
    final currentBitrate = isWifi ? musicProvider.wifiBitrate : musicProvider.cellularBitrate;
    final List<int> options = isWifi ? [64, 128, 256, 320] : [32, 64, 128];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E), // Fixed dark bg for consistency for now
        title: Text('${isWifi ? "Wi-Fi" : "Cellular"} Quality', style: GoogleFonts.splineSans(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((bitrate) {
            final isSelected = bitrate == currentBitrate;
            return ListTile(
              title: Text('$bitrate kbps', style: GoogleFonts.splineSans(color: Colors.white)),
              leading: Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: isSelected ? const Color(0xFFEA80FC) : Colors.white54,
              ),
              onTap: () {
                if (isWifi) {
                  musicProvider.setWifiBitrate(bitrate);
                } else {
                  musicProvider.setCellularBitrate(bitrate);
                }
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}
