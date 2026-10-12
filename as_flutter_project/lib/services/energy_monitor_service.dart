import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'config_service.dart';

class EnergyReading {
  final double voltage;
  final double current;
  final double power;
  final double energy;
  final DateTime timestamp;
  final Map<String, double> currentPerChannel;

  EnergyReading({required this.voltage, required this.current, required this.power, required this.energy, required this.timestamp, this.currentPerChannel = const {}});

  factory EnergyReading.fromJson(Map<String, dynamic> json) => EnergyReading(
        voltage: (json['voltage'] as num?)?.toDouble() ?? 0,
        current: (json['current'] as num?)?.toDouble() ?? 0,
        power: (json['power'] as num?)?.toDouble() ?? 0,
        energy: (json['energy'] as num?)?.toDouble() ?? 0,
        timestamp: DateTime.tryParse('${json['timestamp'] ?? ''}') ?? DateTime.now(),
        currentPerChannel: json['channels'] is Map
            ? Map<String, double>.from((json['channels'] as Map).map((k, v) => MapEntry(k.toString(), (v as num).toDouble())))
            : const {},
      );

  Map<String, dynamic> toJson() => {'voltage': voltage, 'current': current, 'power': power, 'energy': energy, 'timestamp': timestamp.toIso8601String(), 'channels': currentPerChannel};
}

class EnergyBill {
  final double totalKwh, ratePerKwh, totalCost, averageDailyKwh, projectedMonthlyKwh, projectedMonthlyCost;
  final DateTime periodStart, periodEnd;
  final int daysInPeriod;
  EnergyBill({required this.totalKwh, required this.ratePerKwh, required this.totalCost, required this.periodStart, required this.periodEnd, required this.daysInPeriod, required this.averageDailyKwh, required this.projectedMonthlyKwh, required this.projectedMonthlyCost});
}

/// Energy monitoring backed by PostgreSQL via the authenticated app API.
class EnergyMonitorService {
  static final EnergyMonitorService _instance = EnergyMonitorService._internal();
  factory EnergyMonitorService() => _instance;
  EnergyMonitorService._internal();

  final _readingStreamController = StreamController<EnergyReading>.broadcast();
  final _billStreamController = StreamController<EnergyBill>.broadcast();
  Stream<EnergyReading> get readingStream => _readingStreamController.stream;
  Stream<EnergyBill> get billStream => _billStreamController.stream;

  EnergyReading? _latestReading;
  EnergyBill? _currentBill;
  double _totalEnergyKwh = 0;
  DateTime? _periodStart;
  Timer? _sensorPollTimer;
  Timer? _billCalculationTimer;
  double _ratePerKwh = 11.85;
  DateTime? get _lastReadingTimestamp => _latestReading?.timestamp;
  EnergyReading? get latestReading => _latestReading;
  EnergyBill? get currentBill => _currentBill;
  double get ratePerKwh => _ratePerKwh;

  Future<void> initialize() async {
    _periodStart ??= DateTime.now().subtract(const Duration(days: 30));
    await _loadHistoricalData();
    _startBillCalculation();
    _sensorPollTimer?.cancel();
    _sensorPollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollLatestReading());
    await _pollLatestReading();
  }

  Future<Map<String, String>?> _authHeaders() async {
    final headers = await AuthService().getAuthHeaders();
    if (!headers.containsKey('Authorization')) return null;
    headers['Content-Type'] = 'application/json';
    return headers;
  }

  Future<void> _pollLatestReading() async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return;
      final response = await http.get(Uri.parse('${ConfigService().backendUrl}/energy/current'), headers: headers).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || response.body.trim().isEmpty || response.body.trim() == '{}') return;
      final reading = EnergyReading.fromJson(Map<String, dynamic>.from(jsonDecode(response.body)));
      if (_lastReadingTimestamp == reading.timestamp) return;
      _latestReading = reading;
      _totalEnergyKwh = reading.energy;
      _readingStreamController.add(reading);
      _calculateBill();
    } catch (e) { debugPrint('Energy API polling failed: $e'); }
  }

  void _startBillCalculation() {
    _billCalculationTimer?.cancel();
    _billCalculationTimer = Timer.periodic(const Duration(minutes: 1), (_) => _calculateBill());
    _calculateBill();
  }

  void _calculateBill() {
    if (_periodStart == null) return;
    final now = DateTime.now();
    final days = now.difference(_periodStart!).inDays.clamp(1, 365);
    final cost = _totalEnergyKwh * _ratePerKwh;
    final daily = _totalEnergyKwh / days;
    _currentBill = EnergyBill(totalKwh: _totalEnergyKwh, ratePerKwh: _ratePerKwh, totalCost: cost, periodStart: _periodStart!, periodEnd: now, daysInPeriod: days, averageDailyKwh: daily, projectedMonthlyKwh: daily * 30, projectedMonthlyCost: daily * 30 * _ratePerKwh);
    _billStreamController.add(_currentBill!);
  }

  Future<void> _loadHistoricalData() async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return;
      final response = await http.get(Uri.parse('${ConfigService().backendUrl}/energy/history?limit=1'), headers: headers).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;
      final rows = jsonDecode(response.body) as List;
      if (rows.isEmpty) return;
      _latestReading = EnergyReading.fromJson(Map<String, dynamic>.from(rows.first as Map));
      _totalEnergyKwh = _latestReading!.energy;
      _readingStreamController.add(_latestReading!);
    } catch (e) { debugPrint('Energy history load failed: $e'); }
  }

  Future<void> saveEnergyReading(EnergyReading reading) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return;
      final response = await http.post(Uri.parse('${ConfigService().backendUrl}/energy/readings'), headers: headers, body: jsonEncode(reading.toJson())).timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      _latestReading = reading;
      _totalEnergyKwh = reading.energy;
      _readingStreamController.add(reading);
      _calculateBill();
    } catch (e) { debugPrint('Energy save failed: $e'); }
  }

  Future<List<EnergyReading>> getEnergyHistory({DateTime? startDate, DateTime? endDate, int limit = 100}) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return [];
      final query = <String, String>{'limit': '$limit'};
      if (startDate != null) query['start_time'] = startDate.toIso8601String();
      if (endDate != null) query['end_time'] = endDate.toIso8601String();
      final uri = Uri.parse('${ConfigService().backendUrl}/energy/history').replace(queryParameters: query);
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];
      return (jsonDecode(response.body) as List).map((r) => EnergyReading.fromJson(Map<String, dynamic>.from(r as Map))).toList();
    } catch (e) { debugPrint('Energy history query failed: $e'); return []; }
  }

  void setRate(double ratePerKwh) { _ratePerKwh = ratePerKwh; _calculateBill(); }
  void resetBillingPeriod() { _periodStart = DateTime.now(); _totalEnergyKwh = 0; _calculateBill(); }
  void dispose() { _sensorPollTimer?.cancel(); _billCalculationTimer?.cancel(); _readingStreamController.close(); _billStreamController.close(); }
}
