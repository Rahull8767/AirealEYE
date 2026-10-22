import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/providers/settings_provider.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/providers/auth_provider.dart';
import 'package:aerial_eye/screens/mavlink_connection_screen.dart';
import 'package:aerial_eye/screens/camera_connection_screen.dart';
import 'package:aerial_eye/providers/pi_camera_provider.dart';
import 'package:aerial_eye/models/camera_connection_config.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';
import 'package:aerial_eye/widgets/animated_button.dart';
import 'package:aerial_eye/widgets/pi_shutdown_card.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final cameraService = ref.watch(piCameraServiceProvider);
    final cameraState =
        ref.watch(piCameraStateProvider).value ?? cameraService.currentState;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Console Settings'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section 1: Appearance
          _buildSectionHeader('Appearance settings'),
          GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                SwitchListTile(
                  value: settings.isDarkMode,
                  title: const Text('Dark professional layout'),
                  subtitle: const Text(
                    'Vibrant dark scheme to prevent screen reflection outside',
                  ),
                  activeColor: AppTheme.secondary,
                  onChanged: (val) => notifier.updateDarkMode(val),
                ),
                ListTile(
                  title: const Text('Theme HUD Color Accent'),
                  trailing: DropdownButton<String>(
                    value: settings.themeColorName,
                    dropdownColor: AppTheme.card,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(
                        value: 'Blue',
                        child: Text('Blue Accent'),
                      ),
                      DropdownMenuItem(value: 'Cyan', child: Text('Cyan Sky')),
                      DropdownMenuItem(
                        value: 'Green',
                        child: Text('Emerald Green'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) notifier.updateThemeColor(val);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section 2: Maps configs
          _buildSectionHeader('Offline & Tile Maps'),
          GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                ListTile(
                  title: const Text('Active tile layer'),
                  trailing: DropdownButton<String>(
                    value: settings.mapType,
                    dropdownColor: AppTheme.card,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(
                        value: 'Hybrid',
                        child: Text('Dark Hybrid (CARTO)'),
                      ),
                      DropdownMenuItem(
                        value: 'Standard',
                        child: Text('Standard Light'),
                      ),
                      DropdownMenuItem(
                        value: 'Terrain',
                        child: Text('Topography Terrain'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) notifier.updateMapType(val);
                    },
                  ),
                ),
                SwitchListTile(
                  value: settings.offlineMapsEnabled,
                  title: const Text('Offline map buffering'),
                  subtitle: const Text(
                    'Enable SQLite local cache files for remote areas',
                  ),
                  activeColor: AppTheme.secondary,
                  onChanged: (val) => notifier.toggleOfflineMaps(val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section 3: MAVLink Diagnostics
          _buildSectionHeader('Pixhawk MAVLink Interface'),
          GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'MAVLink Network Settings',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Configure UDP listener/direct, ports, IDs, and timeouts',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  trailing: const Icon(
                    LucideIcons.chevronRight,
                    color: AppTheme.secondary,
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MavlinkConnectionScreen(),
                      ),
                    );
                  },
                ),
                const Divider(color: AppTheme.border, height: 16),
                _buildEditableField(
                  context,
                  'Default Bind IP',
                  settings.droneIp,
                  (val) {
                    notifier.updateDroneConnection(val, settings.pixhawkPort);
                    final svc = ref.read(droneServiceProvider);
                    svc.updateConfig(svc.config.copyWith(bindAddress: val));
                  },
                ),
                const Divider(color: AppTheme.border, height: 16),
                _buildEditableField(
                  context,
                  'MAVLink UDP Port',
                  '${settings.pixhawkPort}',
                  (val) {
                    final p = int.tryParse(val) ?? 14550;
                    notifier.updateDroneConnection(settings.droneIp, p);
                    final svc = ref.read(droneServiceProvider);
                    svc.updateConfig(svc.config.copyWith(localPort: p));
                  },
                ),
                const Divider(color: AppTheme.border, height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Telemetry Rates'),
                  trailing: DropdownButton<String>(
                    value: settings.telemetryFreq,
                    dropdownColor: AppTheme.card,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: '5 Hz', child: Text('5 Hz')),
                      DropdownMenuItem(value: '10 Hz', child: Text('10 Hz')),
                      DropdownMenuItem(value: '20 Hz', child: Text('20 Hz')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        notifier.updateTelemetryFrequency(val);
                        final hz =
                            int.tryParse(
                              val.replaceAll(RegExp(r'[^0-9]'), ''),
                            ) ??
                            10;
                        final svc = ref.read(droneServiceProvider);
                        svc.updateConfig(
                          svc.config.copyWith(telemetryRateHz: hz),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section 4: Raspberry Pi Camera Link
          _buildSectionHeader('Raspberry Pi Live Camera Feed'),
          GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          (cameraState.isConnected
                                  ? AppTheme.success
                                  : AppTheme.secondary)
                              .withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      LucideIcons.camera,
                      color: cameraState.isConnected
                          ? AppTheme.success
                          : AppTheme.secondary,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Camera Network Settings',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Status: ${cameraState.statusDisplay} (${cameraService.config.baseUrl})',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  trailing: const Icon(
                    LucideIcons.chevronRight,
                    color: AppTheme.secondary,
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CameraConnectionScreen(),
                      ),
                    );
                  },
                ),
                const Divider(color: AppTheme.border, height: 16),
                _buildEditableField(
                  context,
                  'Camera URL',
                  cameraService.config.baseUrl,
                  (val) {
                    final validation = CameraConnectionConfig.validateUrl(val);
                    if (validation.isValid) {
                      cameraService.updateConfig(
                        cameraService.config.copyWith(
                          baseUrl: validation.normalizedUrl!,
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            validation.errorMessage ?? 'Invalid URL format.',
                          ),
                          backgroundColor: AppTheme.danger,
                        ),
                      );
                    }
                  },
                ),
                const Divider(color: AppTheme.border, height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const CameraConnectionScreen(),
                          ),
                        );
                      },
                      icon: const Icon(LucideIcons.stethoscope, size: 14),
                      label: const Text('Test Connection'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.secondary,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        if (cameraState.isConnected) {
                          cameraService.disconnect();
                        } else {
                          cameraService.connect();
                        }
                      },
                      icon: Icon(
                        cameraState.isConnected
                            ? LucideIcons.power
                            : LucideIcons.play,
                        size: 14,
                      ),
                      label: Text(
                        cameraState.isConnected ? 'Disconnect' : 'Connect',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cameraState.isConnected
                            ? AppTheme.danger
                            : AppTheme.secondary,
                        foregroundColor: cameraState.isConnected
                            ? Colors.white
                            : Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section 5: Companion Computer Power
          _buildSectionHeader('Raspberry Pi Companion Power'),
          const PiShutdownCard(),
          const SizedBox(height: 20),

          // Section 6: AI Model specs
          _buildSectionHeader('AI Detection Model Config'),
          GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Confidence Threshold',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      '${(settings.aiConfidenceThreshold * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.secondary,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: settings.aiConfidenceThreshold,
                  min: 0.50,
                  max: 0.95,
                  activeColor: AppTheme.secondary,
                  onChanged: (val) => notifier.updateAiConfidence(val),
                ),
                const SizedBox(height: 8),
                const Text(
                  'ENABLED DETECTOR CLASSES',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children:
                      [
                        'Pothole',
                        'Road Crack',
                        'Garbage',
                        'Water Logging',
                        'Animal',
                        'Obstacle',
                        'Broken Road Sign',
                      ].map((cls) {
                        final active = settings.enabledAiClasses.contains(cls);
                        return InkWell(
                          onTap: () => notifier.toggleAiClass(cls),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppTheme.secondary.withOpacity(0.15)
                                  : AppTheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: active
                                    ? AppTheme.secondary.withOpacity(0.3)
                                    : AppTheme.border,
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              cls,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: active
                                    ? AppTheme.secondary
                                    : AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section 5: Sync
          _buildSectionHeader('Cloud syncing sync'),
          GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                SwitchListTile(
                  value: settings.firebaseSyncEnabled,
                  title: const Text('Real-time database sync'),
                  subtitle: const Text(
                    'Upload anomaly frames directly to city cloud database',
                  ),
                  activeColor: AppTheme.secondary,
                  onChanged: (val) => notifier.toggleFirebaseSync(val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Logout Button
          AnimatedButton(
            color: AppTheme.danger,
            onTap: () {
              ref.read(authProvider.notifier).logout();
              Navigator.pop(context);
            },
            child: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(LucideIcons.logOut, size: 18),
              label: const Text('Logout Console Session'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: AppTheme.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildEditableField(
    BuildContext context,
    String label,
    String value,
    Function(String) onSubmit,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        InkWell(
          onTap: () {
            final controller = TextEditingController(text: value);
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('Edit $label'),
                content: TextField(
                  controller: controller,
                  decoration: const InputDecoration(filled: true),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {
                      onSubmit(controller.text);
                      Navigator.pop(context);
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            );
          },
          child: Row(
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: AppTheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                LucideIcons.edit2,
                size: 12,
                color: AppTheme.secondary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
