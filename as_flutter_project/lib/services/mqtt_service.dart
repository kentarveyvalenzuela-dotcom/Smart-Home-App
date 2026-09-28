import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global singleton MQTT service that maintains persistent connection
/// throughout app lifecycle, independent of UI pages.
class MqttService {
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;
  MqttService._internal();

  MqttClient? _client;
  MqttConnectionState _connectionState = MqttConnectionState.disconnected;
  String? _errorMessage;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Completer<void>? _connectionCompleter;

  // Broadcast streams for UI listeners
  final _connectionStateController = StreamController<MqttConnectionState>.broadcast();
  final _errorController = StreamController<String?>.broadcast();
  final _messageController = StreamController<ServiceMessage>.broadcast();

  Stream<MqttConnectionState> get connectionState => _connectionStateController.stream;
  Stream<String?> get errors => _errorController.stream;
  Stream<ServiceMessage> get messages => _messageController.stream;

  MqttConnectionState get currentConnectionState => _connectionState;
  String? get currentError => _errorMessage;

  int _selectedBrokerIndex = 0; // Default to localhost

  final List<Map<String, dynamic>> _brokerOptions = [
    {
      'label': 'HiveMQ Cloud Production ⭐',
      'host': 'de9d5f2926cf45349f923cadced1aece.s1.eu.hivemq.cloud',
      'port': 8883,
      'isWebSocket': false,
      'username': 'as_flutter_user',
      'password': 'SmartHome@2025',
      'useTLS': true,
    },
    {
      'label': 'localhost (TCP 1883)',
      'host': 'localhost',
      'port': 1883,
      'isWebSocket': false,
    },
    {
      'label': 'broker.emqx.io (WebSocket 8083)',
      'host': 'broker.emqx.io',
      'wsUrl': 'ws://broker.emqx.io:8083/mqtt',
      'port': 8083,
      'isWebSocket': true,
    },
    {
      'label': 'broker.emqx.io (Secure WebSocket 8084)',
      'host': 'broker.emqx.io',
      'wsUrl': 'wss://broker.emqx.io:8084/mqtt',
      'port': 8084,
      'isWebSocket': true,
    },
    {
      'label': 'test.mosquitto.org (WebSocket 8080)',
      'host': 'test.mosquitto.org',
      'wsUrl': 'ws://test.mosquitto.org:8080/mqtt',
      'port': 8080,
      'isWebSocket': true,
    },
    {
      'label': 'test.mosquitto.org (TCP 1883)',
      'host': 'test.mosquitto.org',
      'port': 1883,
      'isWebSocket': false,
    },
  ];

  List<Map<String, dynamic>> get brokerOptions => _brokerOptions;
  int get selectedBrokerIndex => _selectedBrokerIndex;

  /// Initialize service and attempt connection
  Future<void> initialize() async {
    debugPrint('🚀 MqttService initializing...');
    await _loadBrokerPreference();
    await connect();
  }

  Future<void> _loadBrokerPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _selectedBrokerIndex = prefs.getInt('mqtt_broker_index') ?? 0; // Default to HiveMQ Cloud
    } catch (e) {
      debugPrint('Failed to load broker preference: $e');
    }
  }

  Future<void> _saveBrokerPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('mqtt_broker_index', _selectedBrokerIndex);
    } catch (e) {
      debugPrint('Failed to save broker preference: $e');
    }
  }

  /// Switch broker and reconnect
  Future<void> switchBroker(int index) async {
    if (index == _selectedBrokerIndex) return;
    _selectedBrokerIndex = index;
    await _saveBrokerPreference();
    _reconnectAttempts = 0;
    disconnect();
    await connect();
  }

  Future<void> connect() async {
    _reconnectTimer?.cancel();

    if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
      _connectionCompleter!.completeError('New connection attempt');
    }
    _connectionCompleter = Completer<void>();

    try {
      final brokerCfg = _brokerOptions[_selectedBrokerIndex];
      final bool isWebSocket = brokerCfg['isWebSocket'] as bool? ?? true;
      final String clientId = 'flutter_home_${DateTime.now().millisecondsSinceEpoch}';

      _updateConnectionState(MqttConnectionState.connecting);
      _updateError(null);

      debugPrint('🔌 MqttService connecting to: ${brokerCfg['label']}');

      // Web only supports WebSocket. If on web and selected broker is TLS-only, switch to WebSocket
      int brokerIdx = _selectedBrokerIndex;
      if (kIsWeb && !brokerCfg.containsKey('wsUrl')) {
        debugPrint('⚠️ Web does not support TLS/TCP. Switching to WebSocket broker (broker.emqx.io)...');
        brokerIdx = 2; // broker.emqx.io WebSocket
      }
      final actualBrokerCfg = _brokerOptions[brokerIdx];
      final actualIsWebSocket = actualBrokerCfg['isWebSocket'] as bool? ?? true;

      if ((kIsWeb || actualIsWebSocket) && actualBrokerCfg.containsKey('wsUrl')) {
        final wsUrl = actualBrokerCfg['wsUrl'] as String;
        final browser = MqttBrowserClient(wsUrl, clientId);
        browser.port = actualBrokerCfg['port'] as int;
        browser.websocketProtocols = ['mqtt'];
        browser.keepAlivePeriod = 60;
        browser.autoReconnect = false;
        browser.logging(on: false);

        browser.onConnected = _onConnected;
        browser.onDisconnected = _onDisconnected;

        final connMsg = MqttConnectMessage()
            .withClientIdentifier(clientId)
            .startClean()
            .withWillQos(MqttQos.atMostOnce)
            .keepAliveFor(60);
        browser.connectionMessage = connMsg;

        _client = browser;
        await browser.connect().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Connection timeout');
          },
        );
      } else {
        final host = actualBrokerCfg['host'] as String;
        final port = actualBrokerCfg['port'] as int;
        final useTLS = actualBrokerCfg['useTLS'] as bool? ?? false;
        final username = actualBrokerCfg['username'] as String?;
        final password = actualBrokerCfg['password'] as String?;
        
        final server = MqttServerClient(host, clientId);
        server.port = port;
        server.keepAlivePeriod = 60;
        server.autoReconnect = false;
        server.logging(on: false);
        server.secure = useTLS;

        server.onConnected = _onConnected;
        server.onDisconnected = _onDisconnected;

        final connMsg = MqttConnectMessage()
            .withClientIdentifier(clientId)
            .startClean()
            .withWillQos(MqttQos.atMostOnce)
            .keepAliveFor(60);
        
        // Add authentication if provided
        if (username != null && password != null) {
          connMsg.authenticateAs(username, password);
        }
        
        server.connectionMessage = connMsg;

        _client = server;
        await server.connect().timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException('Connection timeout');
          },
        );
      }

      // Set up message listener
      if (_client?.updates != null) {
        _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>> msgs) {
          debugPrint('📨 [MQTT] Received ${msgs.length} message(s)');
          for (final m in msgs) {
            try {
              final payload = m.payload as MqttPublishMessage;
              debugPrint('📥 [MESSAGE] Topic: ${m.topic} | Payload length: ${payload.payload.message.length}');
              _messageController.add(ServiceMessage(m.topic, payload));
            } catch (e) {
              debugPrint('❌ [MESSAGE_ERROR] Failed to process message: $e');
            }
          }
        });
        debugPrint('✅ Message listener registered');
      } else {
        debugPrint('⚠️ WARNING: updates stream is null - messages may not be received!');
      }

      if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
        _connectionCompleter!.complete();
      }
    } catch (e) {
      debugPrint('❌ MqttService connection failed: $e');
      debugPrint('💡 Don\'t worry - device control works via backend API (Heroku → HiveMQ)');

      _client?.disconnect();

      if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
        // Complete normally instead of error - app can work without direct MQTT
        _connectionCompleter!.complete();
      }

      _updateConnectionState(MqttConnectionState.disconnected);
      _updateError('MQTT offline - backend handles device control');

      _scheduleReconnect();
    }
  }

  void _onConnected() {
    debugPrint('✅ MqttService Connected!');
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _updateConnectionState(MqttConnectionState.connected);
    _updateError(null);
  }

  void _onDisconnected() {
    debugPrint('❌ MqttService Disconnected');
    _updateConnectionState(MqttConnectionState.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    // Limit reconnect attempts - app works without MQTT (backend handles MQTT)
    if (_reconnectAttempts >= 3) {
      debugPrint('⚠️ MQTT: Max reconnect attempts reached. App will work via backend API.');
      debugPrint('💡 Device control still works - backend publishes to MQTT on your behalf.');
      _updateError('MQTT offline - using backend API for device control');
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    _reconnectAttempts++;
    final delay = Duration(seconds: 5 * _reconnectAttempts);
    debugPrint('🔄 MqttService scheduling reconnect attempt $_reconnectAttempts in ${delay.inSeconds}s');

    _reconnectTimer = Timer(delay, () {
      if (_connectionState != MqttConnectionState.connected) {
        connect();
      }
    });
  }

  void _updateConnectionState(MqttConnectionState state) {
    _connectionState = state;
    _connectionStateController.add(state);
  }

  void _updateError(String? error) {
    _errorMessage = error;
    _errorController.add(error);
  }

  /// Subscribe to a topic
  void subscribe(String topic, {MqttQos qos = MqttQos.atLeastOnce}) {
    if (_client == null || _connectionState != MqttConnectionState.connected) {
      debugPrint('⚠️ Cannot subscribe to $topic - not connected');
      return;
    }
    try {
      _client!.subscribe(topic, qos);
      debugPrint('📥 Subscribed to $topic');
    } catch (e) {
      debugPrint('❌ Subscribe failed for $topic: $e');
    }
  }

  /// Publish a message
  Future<void> publish(String topic, String message, {bool retain = true}) async {
    if (_client == null || _connectionState != MqttConnectionState.connected) {
      debugPrint('⚠️ Cannot publish to $topic - not connected');

      if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
        try {
          await _connectionCompleter!.future.timeout(const Duration(seconds: 10));
        } catch (e) {
          debugPrint('❌ Failed to wait for connection: $e');
          throw Exception('Not connected to MQTT broker');
        }
      }

      if (_client == null || _connectionState != MqttConnectionState.connected) {
        throw Exception('Not connected to MQTT broker');
      }
    }

    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(message);
      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!, retain: retain);
      debugPrint('📤 Published: $message to $topic');
    } catch (e) {
      debugPrint('❌ Publish failed: $e');
      throw Exception('Publish failed: $e');
    }
  }

  /// Disconnect and cleanup
  void disconnect() {
    _reconnectTimer?.cancel();
    _client?.disconnect();
    _updateConnectionState(MqttConnectionState.disconnected);
  }

  /// Force reconnect (reset retry count)
  Future<void> reconnect() async {
    _reconnectAttempts = 0;
    disconnect();
    await connect();
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _client?.disconnect();
    _connectionStateController.close();
    _errorController.close();
    _messageController.close();
  }
}

/// Message wrapper for broadcast
class ServiceMessage {
  final String topic;
  final MqttPublishMessage payload;

  ServiceMessage(this.topic, this.payload);
}
