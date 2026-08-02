import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/core/constants/app_constants.dart';
import 'package:aerial_eye/core/config/app_config.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';
import 'package:aerial_eye/widgets/animated_button.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  bool _isScanning = false;
  bool _isConnecting = false;

  void _scanForPixhawk() async {
    setState(() => _isScanning = true);
    await Future.delayed(const Duration(seconds: 2));
    setState(() => _isScanning = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pixhawk MAVLink device discovered over USB/IP: 192.168.1.100'),
        backgroundColor: AppTheme.success,
      ),
    );
  }

  void _connectDrone() async {
    setState(() => _isConnecting = true);
    await Future.delayed(const Duration(seconds: 1500 ~/ 1000));
    ref.read(droneServiceProvider).connect();
    setState(() => _isConnecting = false);
  }

  void _disconnectDrone() {
    ref.read(droneServiceProvider).disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final telemetryAsync = ref.watch(droneTelemetryProvider);
    final telemetry = telemetryAsync.value ?? DroneTelemetry.initial();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Console'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.paddingMedium),
        child: Column(
          children: [
            // 1. Connection Animation / status indicator
            _buildPulseRing(telemetry.isConnected),
            const SizedBox(height: 24),

            // 2. Drone Connection Card
            GlassPanel(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Pixhawk MAVLink Link',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: telemetry.isConnected
                              ? AppTheme.success.withOpacity(0.15)
                              : AppTheme.danger.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: telemetry.isConnected ? AppTheme.success : AppTheme.danger,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              telemetry.isConnected ? 'LINK ACTIVE' : 'NO HEARTBEAT',
                              style: TextStyle(
                                color: telemetry.isConnected ? AppTheme.success : AppTheme.danger,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'MAVLink communication protocol v2.0 endpoint configured to listen for UDP heartbeats.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const Divider(color: AppTheme.border, height: 24),
                  
                  // IP settings layout
                  _buildSettingRow('Host IP Address', AppConfig.droneHostIp),
                  _buildSettingRow('MAVLink port', '${AppConfig.pixhawkPort} (UDP)'),
                  _buildSettingRow('Baudrate', '115200 (Serial bypass)'),
                  _buildSettingRow('Telemetry rate', AppConfig.telemetryFrequencyHz),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 3. Telemetry parameters
            if (telemetry.isConnected) ...[
              GlassPanel(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Link Diagnostics',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _buildDiagTile('Battery Pack', '${telemetry.batteryVoltage} V', LucideIcons.battery)),
                        Expanded(child: _buildDiagTile('Flight Mode', telemetry.flightMode, LucideIcons.plane)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _buildDiagTile('GPS satellites', '${telemetry.satellites} Sats', LucideIcons.satellite)),
                        Expanded(child: _buildDiagTile('Telemetry RSSI', '${telemetry.rssi.toStringAsFixed(0)} %', LucideIcons.wifi)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _buildDiagTile('Altitude AGL', '${telemetry.altitude.toStringAsFixed(1)} m', LucideIcons.arrowUpRight)),
                        Expanded(child: _buildDiagTile('Heading Comp.', '${telemetry.heading.toStringAsFixed(0)}°', LucideIcons.compass)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // 4. Control buttons
            Column(
              children: [
                if (_isConnecting)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(AppTheme.secondary)),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: AnimatedButton(
                        onTap: telemetry.isConnected ? null : _scanForPixhawk,
                        child: OutlinedButton(
                          onPressed: telemetry.isConnected ? null : _scanForPixhawk,
                          child: _isScanning
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                                )
                              : const Text('Scan Port'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AnimatedButton(
                        onTap: _isConnecting
                            ? null
                            : telemetry.isConnected
                                ? _disconnectDrone
                                : _connectDrone,
                        child: ElevatedButton(
                          onPressed: _isConnecting
                              ? null
                              : telemetry.isConnected
                                  ? _disconnectDrone
                                  : _connectDrone,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: telemetry.isConnected ? AppTheme.danger : AppTheme.primary,
                          ),
                          child: Text(telemetry.isConnected ? 'Disconnect' : 'Connect Link'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPulseRing(bool isConnected) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: isConnected ? AppTheme.success.withOpacity(0.08) : AppTheme.danger.withOpacity(0.08),
        shape: BoxShape.circle,
        border: Border.all(
          color: isConnected ? AppTheme.success.withOpacity(0.3) : AppTheme.danger.withOpacity(0.3),
          width: 2.0,
        ),
      ),
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 1.0, end: 1.2),
          duration: const Duration(seconds: 1),
          builder: (context, val, child) {
            return Transform.scale(
              scale: isConnected ? val : 1.0,
              child: Icon(
                isConnected ? LucideIcons.plane : LucideIcons.plane,
                size: 36,
                color: isConnected ? AppTheme.success : AppTheme.danger,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSettingRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDiagTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border, width: 0.8),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.secondary, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 9, color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                Text(value, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
