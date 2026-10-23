import 'dart:async';

import 'package:flutter/material.dart';

import '../services/energy_monitor_service.dart';
import '../services/auth_service.dart';

class MonitorPage extends StatefulWidget {
  final bool showAppBar;

  const MonitorPage({super.key, this.showAppBar = true});

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage>
    with AutomaticKeepAliveClientMixin {
  final EnergyMonitorService _energyService = EnergyMonitorService();
  StreamSubscription<EnergyReading>? _readingSubscription;
  EnergyReading? _reading;
  List<EnergyReading> _history = const [];
  List<Map<String, dynamic>> _sensorHistory = const [];
  String? _registeredDeviceId;
  bool _loadingHistory = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reading = _energyService.latestReading;
    _readingSubscription = _energyService.readingStream.listen((reading) {
      if (mounted) setState(() => _reading = reading);
    });
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await _energyService.getEnergyHistory(limit: 20);
    final registration = await AuthService().ensureEnergyDeviceRegistered();
    final sensors = await AuthService().getLatestSensorReadings();
    if (!mounted) return;
    setState(() {
      _history = history;
      _registeredDeviceId = registration?['device_id']?.toString() ??
          registration?['device']?['id']?.toString();
      _sensorHistory = sensors;
      _loadingHistory = false;
    });
  }

  @override
  void dispose() {
    _readingSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final reading = _reading;
    final cards = <({String label, String value, IconData icon})>[
      (
        label: 'Voltage',
        value: '${(reading?.voltage ?? 0).toStringAsFixed(1)} V',
        icon: Icons.bolt
      ),
      (
        label: 'Current',
        value: '${(reading?.current ?? 0).toStringAsFixed(2)} A',
        icon: Icons.electric_meter
      ),
      (
        label: 'Power',
        value: '${(reading?.power ?? 0).toStringAsFixed(1)} W',
        icon: Icons.power
      ),
      (
        label: 'Energy',
        value: '${(reading?.energy ?? 0).toStringAsFixed(3)} kWh',
        icon: Icons.energy_savings_leaf
      ),
    ];

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Energy Monitor'),
              actions: [
                IconButton(
                  tooltip: 'Refresh history',
                  onPressed: () {
                    setState(() => _loadingHistory = true);
                    _loadHistory();
                  },
                  icon: const Icon(Icons.refresh),
                ),
              ],
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Current readings', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cards.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.65,
              ),
              itemBuilder: (context, index) {
                final item = cards[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(item.icon, color: theme.colorScheme.primary),
                        Text(item.value,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        Text(item.label, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (reading != null) ...[
              const SizedBox(height: 8),
              Text('Updated ${reading.timestamp.toLocal()}',
                  style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 24),
            Text('Recent readings', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_loadingHistory)
              const Center(
                  child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ))
            else if (_history.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No energy readings are available yet.'),
                ),
              )
            else
              ..._history.map((entry) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.show_chart),
                      title: Text(
                          '${entry.power.toStringAsFixed(1)} W  ·  ${entry.energy.toStringAsFixed(3)} kWh'),
                      subtitle: Text(
                          '${entry.voltage.toStringAsFixed(1)} V  ·  ${entry.current.toStringAsFixed(2)} A'),
                      trailing: Text(
                        TimeOfDay.fromDateTime(entry.timestamp.toLocal())
                            .format(context),
                      ),
                    ),
                  )),
            const SizedBox(height: 24),
            Text('Sensor history', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_registeredDeviceId != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.memory),
                  title: Text('Firmware device ID: $_registeredDeviceId'),
                  subtitle: const Text(
                    'Set ENERGY_DEVICE_ID to this value in scripts/secrets.h, then flash the ESP32.',
                  ),
                ),
              ),
            if (_loadingHistory)
              const Center(child: CircularProgressIndicator())
            else if (_sensorHistory.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No sensor readings are available yet.'),
                ),
              )
            else
              ..._sensorHistory.map((entry) {
                final timestamp = DateTime.tryParse(
                    '${entry['timestamp'] ?? entry['recorded_at'] ?? ''}');
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.sensors),
                    title: Text(
                      '${entry['sensor_type'] ?? 'Sensor'}: ${entry['value'] ?? ''} ${entry['unit'] ?? ''}',
                    ),
                    subtitle: Text(
                      timestamp == null
                          ? 'Device ${entry['device_id'] ?? ''}'
                          : '${timestamp.toLocal()} · Device ${entry['device_id'] ?? ''}',
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
