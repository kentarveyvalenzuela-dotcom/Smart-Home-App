// filepath: c:\Users\Ivy\OneDrive\Desktop\New folder\brix\as_flutter_project\lib\services\energy_monitor_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Energy reading from sensors
class EnergyReading {
  final double voltage;       // Volts (from ZMPT101B)
  final double current;       // Amps (from SCT-013 sensors)
  final double power;         // Watts (calculated: V × I)
  final double energy;        // kWh (accumulated)
  final DateTime timestamp;
  final Map<String, double> currentPerChannel;  // Individual SCT readings

  EnergyReading({
    required this.voltage,
    required this.current,
    required this.power,
    required this.energy,
    required this.timestamp,
    this.currentPerChannel = const {},
  });

  factory EnergyReading.fromJson(Map<String, dynamic> json) {
    // Handle timestamp - can be String (ISO format) or int (milliseconds)
    DateTime parseTimestamp(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is String) {
        try {
          return DateTime.parse(value);
        } catch (e) {
          return DateTime.now();
        }
      }
      if (value is int) {
        // If it's a small number, treat as uptime milliseconds from ESP32
        // If it's a large number (Unix timestamp), convert accordingly
        if (value > 1000000000000) {
          // Unix timestamp in milliseconds
          return DateTime.fromMillisecondsSinceEpoch(value);
        } else if (value > 1000000000) {
          // Unix timestamp in seconds
          return DateTime.fromMillisecondsSinceEpoch(value * 1000);
        } else {
          // ESP32 uptime in milliseconds - just use current time
          return DateTime.now();
        }
      }
      return DateTime.now();
    }

    return EnergyReading(
      voltage: (json['voltage'] ?? 0).toDouble(),
      current: (json['current'] ?? 0).toDouble(),
      power: (json['power'] ?? 0).toDouble(),
      energy: (json['energy'] ?? 0).toDouble(),
      timestamp: parseTimestamp(json['timestamp']),
      currentPerChannel: json['channels'] != null
          ? Map<String, double>.from(
              (json['channels'] as Map).map((k, v) => MapEntry(k.toString(), (v as num).toDouble())))
          : {},
    );
  }

  Map<String, dynamic> toJson() => {
    'voltage': voltage,
    'current': current,
    'power': power,
    'energy': energy,
    'timestamp': timestamp.toIso8601String(),
    'channels': currentPerChannel,
  };
}

/// Billing calculation
class EnergyBill {
  final double totalKwh;
  final double ratePerKwh;
  final double totalCost;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int daysInPeriod;
  final double averageDailyKwh;
  final double projectedMonthlyKwh;
  final double projectedMonthlyCost;

  EnergyBill({
    required this.totalKwh,
    required this.ratePerKwh,
    required this.totalCost,
    required this.periodStart,
    required this.periodEnd,
    required this.daysInPeriod,
    required this.averageDailyKwh,
    required this.projectedMonthlyKwh,
    required this.projectedMonthlyCost,
  });
}

/// Energy Monitor Service - Handles voltage & current sensors
class EnergyMonitorService {
  static final EnergyMonitorService _instance = EnergyMonitorService._internal();
  factory EnergyMonitorService() => _instance;
  EnergyMonitorService._internal();

  // Stream controllers
  final _readingStreamController = StreamController<EnergyReading>.broadcast();
  final _billStreamController = StreamController<EnergyBill>.broadcast();

  Stream<EnergyReading> get readingStream => _readingStreamController.stream;
  Stream<EnergyBill> get billStream => _billStreamController.stream;

  // State
  EnergyReading? _latestReading;
  EnergyBill? _currentBill;
  double _totalEnergyKwh = 0.0;
  DateTime? _periodStart;

  StreamSubscription<DatabaseEvent>? _sensorSubscription;
  Timer? _billCalculationTimer;

  // Configuration - Philippine electricity rates (Meralco approximation)
  double _ratePerKwh = 11.85; // PHP per kWh (adjust as needed)

  // Getters
  EnergyReading? get latestReading => _latestReading;
  EnergyBill? get currentBill => _currentBill;
  double get ratePerKwh => _ratePerKwh;

  /// Initialize the service
  Future<void> initialize() async {
    debugPrint('⚡ Initializing Energy Monitor Service...');

    _periodStart = DateTime.now().subtract(const Duration(days: 30));

    // Listen to sensor data from Firebase
    _listenToSensorData();

    // Start periodic bill calculation
    _startBillCalculation();

    // Load historical data
    await _loadHistoricalData();

    debugPrint('✅ Energy Monitor Service initialized');
  }

  /// Listen to real-time sensor data from Firebase
  void _listenToSensorData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseDatabase.instance
        .ref()
        .child('users')
        .child(user.uid)
        .child('sensors')
        .child('energy');

    _sensorSubscription?.cancel();
    _sensorSubscription = ref.onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        try {
          final data = Map<String, dynamic>.from(event.snapshot.value as Map);
          final reading = EnergyReading.fromJson(data);

          _latestReading = reading;
          _readingStreamController.add(reading);

          // Accumulate energy
          _accumulateEnergy(reading);

          debugPrint('⚡ Energy reading: ${reading.voltage}V, ${reading.current}A, ${reading.power}W');
        } catch (e) {
          debugPrint('❌ Error parsing energy data: $e');
        }
      }
    }, onError: (error) {
      debugPrint('❌ Firebase energy listener error: $error');
    });
  }

  /// Accumulate energy consumption
  void _accumulateEnergy(EnergyReading reading) {
    // Simple accumulation - in reality, you'd integrate power over time
    // power (W) × time (hours) = energy (Wh)
    // For real-time updates every second: power × (1/3600) = Wh per reading
    _totalEnergyKwh += reading.power / 3600000; // Convert Wh to kWh
  }

  /// Start periodic bill calculation
  void _startBillCalculation() {
    _billCalculationTimer?.cancel();
    _billCalculationTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _calculateBill();
    });

    // Calculate immediately
    _calculateBill();
  }

  /// Calculate current bill
  void _calculateBill() {
    if (_periodStart == null) return;

    final now = DateTime.now();
    final daysInPeriod = now.difference(_periodStart!).inDays.clamp(1, 365);

    final totalCost = _totalEnergyKwh * _ratePerKwh;
    final avgDaily = _totalEnergyKwh / daysInPeriod;
    final projectedMonthly = avgDaily * 30;
    final projectedCost = projectedMonthly * _ratePerKwh;

    _currentBill = EnergyBill(
      totalKwh: _totalEnergyKwh,
      ratePerKwh: _ratePerKwh,
      totalCost: totalCost,
      periodStart: _periodStart!,
      periodEnd: now,
      daysInPeriod: daysInPeriod,
      averageDailyKwh: avgDaily,
      projectedMonthlyKwh: projectedMonthly,
      projectedMonthlyCost: projectedCost,
    );

    _billStreamController.add(_currentBill!);
  }

  /// Load historical energy data
  Future<void> _loadHistoricalData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(user.uid)
          .child('energy_history')
          .child('total_kwh')
          .get();

      if (snapshot.exists && snapshot.value != null) {
        _totalEnergyKwh = (snapshot.value as num).toDouble();
        debugPrint('📊 Loaded historical energy: $_totalEnergyKwh kWh');
      }
    } catch (e) {
      debugPrint('❌ Error loading historical data: $e');
    }
  }

  /// Save energy data to Firebase
  Future<void> saveEnergyReading(EnergyReading reading) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Save current reading
      await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(user.uid)
          .child('sensors')
          .child('energy')
          .set(reading.toJson());

      // Save to history
      final historyRef = FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(user.uid)
          .child('energy_history')
          .child('readings')
          .push();

      await historyRef.set(reading.toJson());

      // Update total
      await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(user.uid)
          .child('energy_history')
          .child('total_kwh')
          .set(_totalEnergyKwh);

    } catch (e) {
      debugPrint('❌ Error saving energy reading: $e');
    }
  }

  /// Get energy history for a date range
  Future<List<EnergyReading>> getEnergyHistory({
    DateTime? startDate,
    DateTime? endDate,
    int limit = 100,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return [];

      final snapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(user.uid)
          .child('energy_history')
          .child('readings')
          .orderByChild('timestamp')
          .limitToLast(limit)
          .get();

      if (!snapshot.exists || snapshot.value == null) return [];

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final readings = <EnergyReading>[];

      data.forEach((key, value) {
        try {
          readings.add(EnergyReading.fromJson(Map<String, dynamic>.from(value)));
        } catch (e) {
          debugPrint('⚠️ Error parsing reading: $e');
        }
      });

      // Sort by timestamp
      readings.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      return readings;
    } catch (e) {
      debugPrint('❌ Error getting energy history: $e');
      return [];
    }
  }

  /// Set electricity rate
  void setRate(double ratePerKwh) {
    _ratePerKwh = ratePerKwh;
    _calculateBill();
  }

  /// Reset billing period
  void resetBillingPeriod() {
    _periodStart = DateTime.now();
    _totalEnergyKwh = 0.0;
    _calculateBill();
  }

  /// Dispose resources
  void dispose() {
    _sensorSubscription?.cancel();
    _billCalculationTimer?.cancel();
    _readingStreamController.close();
    _billStreamController.close();
  }
}

