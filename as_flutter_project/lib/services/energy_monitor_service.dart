import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

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

  final ApiService _apiService = ApiService();

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

  void stopPolling() {
    _sensorPollTimer?.cancel();
    _sensorPollTimer = null;
    _billCalculationTimer?.cancel();
    _billCalculationTimer = null;
  }

  Future<void> _pollLatestReading() async {
    try {
      if (!await _apiService.hasAccessToken()) return;
      final response = await _apiService.getRequest<Map<String, dynamic>>(
        '/energy/current',
        parser: (data) => data is Map
            ? Map<String, dynamic>.from(data)
            : <String, dynamic>{},
      );
      if (!response.success || response.data == null || response.data!.isEmpty) {
        return;
      }
      final reading = EnergyReading.fromJson(response.data!);
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
      if (!await _apiService.hasAccessToken()) return;
      final response = await _apiService.getRequest<List<dynamic>>(
        '/energy/history',
        queryParams: {'limit': '1'},
        parser: (data) => data is List ? data : <dynamic>[],
      );
      if (!response.success || response.data == null) return;
      final rows = response.data!;
      if (rows.isEmpty) return;
      _latestReading = EnergyReading.fromJson(Map<String, dynamic>.from(rows.first as Map));
      _totalEnergyKwh = _latestReading!.energy;
      _readingStreamController.add(_latestReading!);
    } catch (e) { debugPrint('Energy history load failed: $e'); }
  }

  Future<void> saveEnergyReading(EnergyReading reading) async {
    try {
      if (!await _apiService.hasAccessToken()) return;
      final response = await _apiService.postRequest<dynamic>(
        '/energy/readings',
        body: reading.toJson(),
        parser: (data) => data,
      );
      if (!response.success) return;
      _latestReading = reading;
      _totalEnergyKwh = reading.energy;
      _readingStreamController.add(reading);
      _calculateBill();
    } catch (e) { debugPrint('Energy save failed: $e'); }
  }

  Future<List<EnergyReading>> getEnergyHistory({DateTime? startDate, DateTime? endDate, int limit = 100}) async {
    try {
      if (!await _apiService.hasAccessToken()) return [];
      final query = <String, String>{'limit': '$limit'};
      if (startDate != null) query['start_time'] = startDate.toIso8601String();
      if (endDate != null) query['end_time'] = endDate.toIso8601String();
      final response = await _apiService.getRequest<List<dynamic>>(
        '/energy/history',
        queryParams: query,
        parser: (data) => data is List ? data : <dynamic>[],
      );
      if (!response.success || response.data == null) return [];
      return response.data!
          .map((r) => EnergyReading.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) { debugPrint('Energy history query failed: $e'); return []; }
  }

  void setRate(double ratePerKwh) { _ratePerKwh = ratePerKwh; _calculateBill(); }
  void resetBillingPeriod() { _periodStart = DateTime.now(); _totalEnergyKwh = 0; _calculateBill(); }
  void dispose() {
    stopPolling();
    _readingStreamController.close();
    _billStreamController.close();
  }
}
