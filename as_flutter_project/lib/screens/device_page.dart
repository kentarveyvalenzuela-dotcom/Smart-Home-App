import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart' hide MqttMessage;
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sync_service.dart';
import '../services/mqtt_service.dart';
import '../services/config_service.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../utils/smooth_ui.dart';
import '../main.dart';

class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // Keep this page alive when switching tabs

  final _mqtt = MqttService();
  List<Map<String, dynamic>> appliances = [];
  MqttConnectionState _connectionState = MqttConnectionState.disconnected;
  String? _errorMessage;
  late final SyncService _sync;
  StreamSubscription<MqttConnectionState>? _connectionSub;
  StreamSubscription<String?>? _errorSub;
  StreamSubscription<ServiceMessage>? _messageSub;
  bool _isLoadingDevices = false;
  String? _backendStatus;

  // Track last response time for each device
  final Map<String, DateTime> _lastResponseTime = {};

  // Track deleted device IDs to prevent them from coming back on refresh
  final Set<String> _deletedDeviceIds = {};

  // GPIO Pin to ESP32 device name mapping
  // IMPORTANT: These must match the registerDevice() calls in esp32_smart_home.ino
  final List<Map<String, dynamic>> pinSlots = [
    {'pin': 23, 'label': 'Sala (Living Room)', 'type': 'light', 'mqtt_id': 'sala'},
    {'pin': 22, 'label': 'Kwarto (Bedroom)', 'type': 'light', 'mqtt_id': 'kwarto'},
    {'pin': 21, 'label': 'Kusina (Kitchen)', 'type': 'appliance', 'mqtt_id': 'kusina'},
    {'pin': 19, 'label': 'Banyo (Bathroom)', 'type': 'light', 'mqtt_id': 'banyo'},
    {'pin': 18, 'label': 'Garahe (Garage)', 'type': 'appliance', 'mqtt_id': 'garahe'},
    {'pin': 17, 'label': 'Labas (Outside)', 'type': 'light', 'mqtt_id': 'labas'},
  ];

  @override
  void initState() {
    super.initState();
    _sync = SyncService(baseUrl: ConfigService().backendUrl);
    _connectionState = _mqtt.currentConnectionState;
    _errorMessage = _mqtt.currentError;
    
    _connectionSub = _mqtt.connectionState.listen((state) {
      if (mounted) {
        setState(() {
          _connectionState = state;
          if (state == MqttConnectionState.connected) {
            _resubscribeAppliances();
          }
        });
      }
    });
    
    _errorSub = _mqtt.errors.listen((error) {
      if (mounted) {
        setState(() {
          _errorMessage = error;
        });
      }
    });
    
    _messageSub = _mqtt.messages.listen(_handleIncomingMessage);
    
    // Initialize app on startup
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    debugPrint('[INIT] Initializing Device Page...');

    // Load deleted device IDs first
    await _loadDeletedDeviceIds();

    // STEP 1: Load from cache FIRST (instant display)
    await _loadAppliancesFromCache();
    debugPrint('[INIT] Loaded ${appliances.length} devices from cache');

    // Show cached devices immediately
    if (mounted && appliances.isNotEmpty) {
      setState(() {
        _backendStatus = 'Loaded ${appliances.length} cached devices, syncing...';
      });
      _resubscribeAppliances();
    }

    // STEP 2: Sync with backend in background (update if different)
    await _syncWithBackend();

    // STEP 3: Resubscribe to MQTT topics
    if (_connectionState == MqttConnectionState.connected) {
      _resubscribeAppliances();
    }

    debugPrint('[INIT] Device Page initialization complete');
  }

  Future<void> _syncWithBackend() async {
    if (!mounted) return;
    
    setState(() {
      _isLoadingDevices = true;
    });

    try {
      final authService = AuthService();
      final token = await authService.getAccessToken();

      if (token == null) {
        debugPrint('[SYNC] No auth token - using cached devices only');
        setState(() {
          _backendStatus = appliances.isEmpty
              ? 'Please login to load devices'
              : 'Using ${appliances.length} cached devices';
          _isLoadingDevices = false;
        });
        return;
      }

      debugPrint('[SYNC] Fetching devices from backend...');
      final devices = await _sync.pullDevices(authToken: token);

      if (devices != null && devices.isNotEmpty) {
        debugPrint('[SYNC] Got ${devices.length} devices from backend');
        debugPrint('[SYNC] Deleted device IDs count: ${_deletedDeviceIds.length}');

        // Filter out deleted devices
        final filteredDevices = devices.where((d) {
          final deviceId = d['device_id'] as String? ?? d['mqtt_client_id'] as String? ?? '';
          final backendId = d['backend_device_id'] as String? ?? '';
          final isDeleted = _deletedDeviceIds.contains(deviceId) || _deletedDeviceIds.contains(backendId);
          return !isDeleted;
        }).toList();

        debugPrint('[SYNC] ${filteredDevices.length} devices after filtering deleted');

        if (mounted) {
          setState(() {
            // Always update from backend if we got results (filtered or not)
            appliances = filteredDevices;
            _backendStatus = filteredDevices.isEmpty
                ? 'No devices - tap + to add'
                : '${filteredDevices.length} devices synced';
            _isLoadingDevices = false;
          });

          // Save updated list to cache
          await _saveAppliancesToCache();

          // Resubscribe with new devices
          if (filteredDevices.isNotEmpty) {
            _resubscribeAppliances();
          }
        }
      } else {
        debugPrint('[SYNC] Backend returned empty, keeping cached devices');
        if (mounted) {
          setState(() {
            _backendStatus = appliances.isEmpty
                ? 'No devices - tap + to add'
                : '${appliances.length} devices (cached)';
            _isLoadingDevices = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[SYNC] Backend error: $e');
      if (mounted) {
        setState(() {
          _backendStatus = appliances.isEmpty
              ? 'Offline - no cached devices'
              : '${appliances.length} devices (offline)';
          _isLoadingDevices = false;
        });
      }
    }
  }

  Future<void> _clearOldCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? raw = prefs.getStringList('appliances');

      if (raw != null && raw.isNotEmpty) {
        // Check if any appliances have device_id (new format)
        bool hasNewFormat = raw.any((s) => s.contains('device_id='));

        if (!hasNewFormat) {
          // Old format cache - clear it
          debugPrint('[CACHE] Clearing old cache format');
          await prefs.remove('appliances');
        }
      }
    } catch (e) {
      debugPrint('[CACHE] Error clearing cache: $e');
    }
  }

  Future<void> _loadDevicesFromBackend() async {
    await _syncWithBackend();
  }

  Future<void> _loadAppliancesFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = await _getCurrentUserId();
      final key = uid != null ? 'appliances_$uid' : 'appliances';
      final List<String>? raw = prefs.getStringList(key);

      debugPrint('[CACHE] Loading cache for user: $uid, key: $key');
      debugPrint('[CACHE] Raw cache entries: ${raw?.length ?? 0}');

      if (raw != null && raw.isNotEmpty) {
        final List<Map<String, dynamic>> decoded = [];

        for (final s in raw) {
          try {
            final app = _decodeAppliance(s);
            if (app.isNotEmpty) {
              decoded.add(app);
            }
          } catch (e) {
            debugPrint('[CACHE] Error decoding: $e');
          }
        }

        debugPrint('[CACHE] Decoded ${decoded.length} appliances');

        // Filter out invalid entries AND deleted devices
        final validAppliances = decoded.where((a) {
          final deviceId = a['device_id'] as String? ?? '';
          final name = a['name'] as String? ?? '';
          final topic = a['topic'] as String? ?? '';

          final isValid = deviceId.isNotEmpty && name.isNotEmpty && topic.isNotEmpty;
          final isNotDeleted = !_deletedDeviceIds.contains(deviceId);

          if (!isValid) {
            debugPrint('[CACHE] Invalid appliance: $a');
          }
          if (!isNotDeleted) {
            debugPrint('[CACHE] Deleted appliance skipped: $deviceId');
          }

          return isValid && isNotDeleted;
        }).map((a) {
          // MIGRATE: Fix old topic format to new format
          final topic = a['topic'] as String? ?? '';
          final deviceId = a['device_id'] as String? ?? '';
          final mqttId = a['mqtt_client_id'] as String? ?? deviceId;

          if (topic.startsWith('device/') && !topic.startsWith('home/device/')) {
            a['topic'] = 'home/device/$mqttId';
            a['device_id'] = mqttId;
            debugPrint('[CACHE] Migrated topic: $topic -> ${a['topic']}');
          }
          return a;
        }).toList();

        debugPrint('[CACHE] Valid appliances: ${validAppliances.length}');

        if (mounted && validAppliances.isNotEmpty) {
          setState(() {
            appliances = validAppliances;
          });
        }
      } else {
        debugPrint('[CACHE] No cached appliances found');
      }
    } catch (e) {
      debugPrint('[CACHE] Error loading: $e');
      if (mounted) {
        appliances = [];
      }
    }
  }

  Future<void> _saveAppliancesToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = await _getCurrentUserId();
      final key = uid != null ? 'appliances_$uid' : 'appliances';
      final encoded = appliances.map((ap) => _encodeAppliance(ap)).toList();
      await prefs.setStringList(key, encoded);
      debugPrint('✅ Saved ${appliances.length} appliances to cache (key: $key)');
    } catch (e) {
      debugPrint('❌ Error saving cache: $e');
    }
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _errorSub?.cancel();
    _messageSub?.cancel();
    super.dispose();
  }

  void _handleIncomingMessage(ServiceMessage mqttMsg) {
    try {
      final topic = mqttMsg.topic;
      final payload = MqttPublishPayload.bytesToStringAsString(mqttMsg.payload.payload.message);
      
      debugPrint('📨 [MQTT] Topic: $topic | Payload: "$payload"');

      final normalizedPayload = payload.trim().toUpperCase();
      final isOn = ['ON', '1', 'TRUE', 'HIGH', '100', 'ACTIVE'].contains(normalizedPayload);

      for (int i = 0; i < appliances.length; i++) {
        final deviceTopic = appliances[i]['topic'] as String;
        
        if (topic == '$deviceTopic/state' || topic == '$deviceTopic/status' || topic == deviceTopic) {
          _lastResponseTime[deviceTopic] = DateTime.now();
          
          if (mounted && appliances[i]['isOn'] != isOn) {
            setState(() {
              appliances[i]['isOn'] = isOn;
            });
            _saveAppliancesToCache();
          }
          break;
        }
      }
    } catch (e) {
      debugPrint('❌ Error handling MQTT message: $e');
    }
  }

  Future<bool> _sendDeviceControl(String deviceTopic, String action) async {
    debugPrint('========== DEVICE CONTROL DEBUG ==========');
    debugPrint('[DEBUG] deviceTopic param: $deviceTopic');
    debugPrint('[DEBUG] action param: $action');
    debugPrint('[DEBUG] Total appliances: ${appliances.length}');

    // Print all appliances for debugging
    for (int i = 0; i < appliances.length; i++) {
      final ap = appliances[i];
      debugPrint('[DEBUG] Appliance[$i]: topic="${ap['topic']}", device_id="${ap['device_id']}", name="${ap['name']}"');
    }

    try {
      final appliance = appliances.firstWhere(
        (a) => a['topic'] == deviceTopic,
        orElse: () => {},
      );

      if (appliance.isEmpty) {
        debugPrint('[ERROR] Device not found! Looking for topic: $deviceTopic');
        debugPrint('[ERROR] Available topics: ${appliances.map((a) => a['topic']).toList()}');
        return false;
      }

      final mqttDeviceId = appliance['device_id'] as String? ?? '';
      final pin = (appliance['pin'] as int?) ?? 23;

      debugPrint('[DEBUG] Found appliance: $appliance');
      debugPrint('[DEBUG] mqttDeviceId: $mqttDeviceId');
      debugPrint('[DEBUG] pin: $pin');

      if (mqttDeviceId.isEmpty) {
        debugPrint('[ERROR] Device missing device_id');
        return false;
      }

      debugPrint('[CMD] Sending: $action to $mqttDeviceId pin $pin');

      // ===== METHOD 1: DIRECT MQTT (FAST!) =====
      final mqttService = MqttService();
      debugPrint('[DEBUG] MQTT connection state: ${mqttService.currentConnectionState}');

      if (mqttService.currentConnectionState == MqttConnectionState.connected) {
        try {
          // Publish to home/device/{id}/set topic with ON/OFF payload
          final topic = 'home/device/$mqttDeviceId/set';
          debugPrint('[MQTT] Publishing to: $topic with payload: ${action.toUpperCase()}');
          await mqttService.publish(topic, action.toUpperCase(), retain: false);
          debugPrint('[MQTT] Published successfully!');

          // Clear last response and wait for new one
          _lastResponseTime.remove(deviceTopic);

          // Wait for MQTT response (max 2 seconds)
          final startTime = DateTime.now();
          while (DateTime.now().difference(startTime).inSeconds < 2) {
            if (_lastResponseTime.containsKey(deviceTopic)) {
              debugPrint('[OK] Got response from hardware');
              return true;
            }
            await Future.delayed(const Duration(milliseconds: 100));
          }

          // Command sent via MQTT even if no response
          debugPrint('[OK] MQTT command sent (no response yet)');
          return true;
        } catch (e) {
          debugPrint('[MQTT ERROR] Direct publish failed: $e');
          // Fall through to backend API
        }
      } else {
        debugPrint('[MQTT] Not connected, using backend API...');
      }

      // ===== METHOD 2: BACKEND API (FALLBACK) =====
      final backendDeviceId = appliance['backend_device_id'] as String? ?? mqttDeviceId;

      debugPrint('[API] Sending via backend: $backendDeviceId pin $pin');

      final authService = AuthService();
      final result = await authService.sendDeviceControl(
        device_id: backendDeviceId,
        pin_number: pin,
        action: action.toUpperCase(),
      );

      if (result?['success'] == true) {
        debugPrint('[OK] Command sent via backend');
        return true;
      } else {
        debugPrint('[API ERROR] ${result?['error'] ?? 'Unknown error'}');
        return false;
      }
    } catch (e) {
      debugPrint('[ERROR] Control failed: $e');
      return false;
    }
  }

  void _addAppliance() {
    final nameController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final availableSlots = pinSlots
            .where((s) => !appliances.any((ap) => ap['pin'] == s['pin']))
            .toList();
        
        int? selectedPin = availableSlots.isNotEmpty 
            ? (availableSlots.first['pin'] as int) 
            : null;

        // Get the mqtt_id for the selected pin
        String getMqttId(int? pin) {
          if (pin == null) return '';
          final slot = pinSlots.firstWhere(
            (s) => s['pin'] == pin,
            orElse: () => {'mqtt_id': 'relay${pin}'},
          );
          return slot['mqtt_id'] as String? ?? 'relay$pin';
        }

        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            final currentMqttId = getMqttId(selectedPin);

            return AlertDialog(
              title: const Text('Add New Device'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Device Name',
                        border: OutlineInputBorder(),
                        hintText: 'e.g. Ilaw sa Sala',
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (availableSlots.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber, color: Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Max 6 devices. Delete one to add another.',
                                style: TextStyle(color: Colors.orange.shade700),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      DropdownButtonFormField<int>(
                        value: selectedPin,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Select Room/Location',
                          border: OutlineInputBorder(),
                        ),
                        items: availableSlots
                            .map((s) => DropdownMenuItem<int>(
                              value: s['pin'] as int,
                              child: Text(
                                '${s['label']} (GPIO ${s['pin']})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                            .toList(),
                        onChanged: (v) => setStateDialog(() => selectedPin = v),
                      ),
                    const SizedBox(height: 12),
                    // Show the MQTT ID that will be used
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.wifi, color: Colors.green.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'MQTT Device ID',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                                Text(
                                  currentMqttId,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.check_circle, color: Colors.green.shade400, size: 18),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  onPressed: availableSlots.isEmpty ? null : () async {
                    final name = nameController.text.trim();
                    final mqttId = getMqttId(selectedPin);

                    if (name.isEmpty || selectedPin == null) {
                      return;
                    }

                    // Show loading indicator
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Registering device...')),
                    );

                    // Try to register device with backend
                    final authService = AuthService();
                    final registerResult = await authService.registerDevice(
                      deviceName: name,
                      mqttClientId: mqttId,  // Use the correct MQTT ID
                      location: '',
                    );

                    String? backendDeviceId;
                    if (registerResult?['success'] == true) {
                      backendDeviceId = registerResult?['device_id'] as String?;
                      debugPrint('[OK] Device registered with backend: $backendDeviceId');
                    } else {
                      debugPrint('[WARN] Backend registration failed: ${registerResult?['error']}');
                      // Continue anyway with local device
                    }

                    final newDevice = {
                      'device_id': mqttId,  // Use the correct MQTT ID (sala, kwarto, etc.)
                      'backend_device_id': backendDeviceId ?? mqttId,
                      'name': name,
                      'isOn': false,
                      'topic': 'home/device/$mqttId',  // Correct topic
                      'pin': selectedPin!,
                      'mqtt_client_id': mqttId,
                      'location': '',
                      'is_online': false,
                    };

                    setState(() {
                      appliances.add(newDevice);
                    });

                    await _saveAppliancesToCache();
                    _resubscribeAppliances();

                    // Add notification for device add
                    NotificationService().addDeviceAddNotification(name);

                    if (mounted) {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(registerResult?['success'] == true
                            ? 'Device "$name" registered!'
                            : 'Device "$name" added locally'),
                          backgroundColor: registerResult?['success'] == true ? Colors.green : Colors.orange,
                        ),
                      );
                    }

                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildApplianceCard(Map<String, dynamic> appliance, int index) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      child: ListTile(
        leading: GestureDetector(
          onTap: () async {
            final isTurningOn = !appliances[index]['isOn'];
            final action = isTurningOn ? 'ON' : 'OFF';
            final topic = appliances[index]['topic'] as String;
            final deviceName = appliances[index]['name'] as String? ?? 'Unknown Device';
            final location = appliances[index]['location'] as String?;

            setState(() {
              appliances[index]['isOn'] = isTurningOn;
            });

            final success = await _sendDeviceControl(topic, action);

            if (success) {
              // Add notification for successful device toggle
              NotificationService().addDeviceToggleNotification(
                deviceName: deviceName,
                action: action,
                location: location,
              );
            }

            if (!success && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('⚠️ Failed to control ${appliance['name']}'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 3),
                ),
              );
              
              setState(() {
                appliances[index]['isOn'] = !isTurningOn;
              });
            }
          },
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: appliances[index]['isOn'] ? Colors.green : Colors.red,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(77),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                )
              ],
            ),
            child: const Icon(Icons.power_settings_new, color: Colors.white, size: 30),
          ),
        ),
        title: Text(
          appliance['name'] as String? ?? 'Unknown',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          appliance['topic'] as String? ?? 'No topic',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              appliances[index]['isOn'] ? Icons.check_circle : Icons.highlight_off,
              color: appliances[index]['isOn'] ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'Device actions',
              icon: const Icon(Icons.more_vert),
              onSelected: (action) async {
                if (action == 'edit') {
                  await _editAppliance(index);
                } else if (action == 'delete') {
                  await _deleteAppliance(index);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(value: 'edit', child: Text('Edit name')),
                const PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editAppliance(int index) async {
    final controller = TextEditingController(text: appliances[index]['name'] as String? ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Device Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        appliances[index]['name'] = result;
      });
      await _saveAppliancesToCache();
    }
  }

  Future<void> _deleteAppliance(int index) async {
    final deviceId = appliances[index]['device_id'] as String? ?? '';
    final backendDeviceId = appliances[index]['backend_device_id'] as String? ?? deviceId;
    final deviceName = appliances[index]['name'] as String? ?? 'Device';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Device'),
        content: Text('Remove "$deviceName" from your devices?\n\nThis will permanently delete it from your account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deleting device...'), duration: Duration(seconds: 1)),
        );
      }

      // 1. Delete from backend FIRST
      final authService = AuthService();
      final deleteResult = await authService.deleteDevice(deviceId: backendDeviceId);

      debugPrint('[DELETE] Backend result: $deleteResult');

      if (deleteResult['success'] == true) {
        // 2. Remove from local list
        setState(() {
          appliances.removeAt(index);
        });

        // 3. Save updated cache
        await _saveAppliancesToCache();

        // 4. Add notification for device delete
        NotificationService().addDeviceDeleteNotification(deviceName);

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ "$deviceName" deleted permanently'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // Backend delete failed
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Failed to delete: ${deleteResult['error'] ?? 'Unknown error'}'),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () => _deleteAppliance(index),
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _saveDeletedDeviceIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = await _getCurrentUserId();
      final key = uid != null ? 'deleted_device_ids_$uid' : 'deleted_device_ids';
      await prefs.setStringList(key, _deletedDeviceIds.toList());
    } catch (e) {
      debugPrint('❌ Error saving deleted device IDs: $e');
    }
  }

  Future<void> _loadDeletedDeviceIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = await _getCurrentUserId();
      final key = uid != null ? 'deleted_device_ids_$uid' : 'deleted_device_ids';
      final ids = prefs.getStringList(key) ?? [];
      _deletedDeviceIds.clear(); // Clear first to avoid duplicates
      _deletedDeviceIds.addAll(ids);
      debugPrint('[CACHE] Loaded ${_deletedDeviceIds.length} deleted device IDs for user $uid');
    } catch (e) {
      debugPrint('❌ Error loading deleted device IDs: $e');
    }
  }

  Future<String?> _getCurrentUserId() async {
    try {
      final authService = AuthService();
      final token = await authService.getAccessToken();
      if (token != null) {
        // Try to get UID from Firebase Auth
        final firebaseUser = await authService.getCurrentFirebaseUser();
        return firebaseUser?['uid'] as String?;
      }
    } catch (e) {
      debugPrint('Error getting user ID: $e');
    }
    return null;
  }

  Future<void> _clearDeletedDeviceIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = await _getCurrentUserId();
      final key = uid != null ? 'deleted_device_ids_$uid' : 'deleted_device_ids';
      await prefs.remove(key);
      _deletedDeviceIds.clear();
      debugPrint('✅ Cleared deleted device IDs - all devices will show again');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Deleted devices restored'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error clearing deleted device IDs: $e');
    }
  }

  Future<void> _clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = await _getCurrentUserId();
      final appliancesKey = uid != null ? 'appliances_$uid' : 'appliances';
      final deletedKey = uid != null ? 'deleted_device_ids_$uid' : 'deleted_device_ids';

      await prefs.remove(appliancesKey);
      await prefs.remove(deletedKey);
      _deletedDeviceIds.clear();
      setState(() {
        appliances.clear();
      });
      debugPrint('✅ Cleared all device cache for user $uid');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Cache cleared - refreshing...'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      // Reload from backend
      await _syncWithBackend();
    } catch (e) {
      debugPrint('❌ Error clearing cache: $e');
    }
  }

  void _resubscribeAppliances() {
    if (_connectionState != MqttConnectionState.connected) {
      debugPrint('⚠️ Cannot subscribe - MQTT not connected');
      return;
    }

    debugPrint('📡 Subscribing to ${appliances.length} devices');
    for (final ap in appliances) {
      final topic = ap['topic'] as String;
      _mqtt.subscribe('$topic/state');
      _mqtt.subscribe('$topic/status');
      _mqtt.subscribe(topic);
    }
  }

  Map<String, dynamic> _decodeAppliance(String s) {
    final Map<String, dynamic> m = {};
    
    for (final part in s.split(';')) {
      final idx = part.indexOf('=');
      if (idx <= 0) continue;
      
      final k = part.substring(0, idx);
      final v = part.substring(idx + 1);
      
      switch (k) {
        case 'name':
          m['name'] = v;
        case 'isOn':
          m['isOn'] = v == 'true';
        case 'topic':
          m['topic'] = v;
        case 'pin':
          m['pin'] = int.tryParse(v) ?? 23;
        case 'device_id':
          m['device_id'] = v;
        case 'backend_device_id':
          m['backend_device_id'] = v;
        case 'mqtt_client_id':
          m['mqtt_client_id'] = v;
        case 'location':
          m['location'] = v;
        case 'is_online':
          m['is_online'] = v == 'true';
      }
    }

    // Set defaults for missing fields
    m['name'] ??= 'Unknown Device';
    m['isOn'] ??= false;
    m['topic'] ??= '';
    m['pin'] ??= 23;
    m['device_id'] ??= '';
    m['backend_device_id'] ??= m['device_id'] ?? '';
    m['mqtt_client_id'] ??= m['device_id'] ?? '';
    m['location'] ??= '';
    m['is_online'] ??= false;

    return m;
  }

  String _encodeAppliance(Map<String, dynamic> ap) {
    return [
      'name=${ap['name'] ?? ''}',
      'isOn=${(ap['isOn'] ?? false) ? 'true' : 'false'}',
      'topic=${ap['topic'] ?? ''}',
      'pin=${ap['pin'] ?? 23}',
      'device_id=${ap['device_id'] ?? ''}',
      'backend_device_id=${ap['backend_device_id'] ?? ap['device_id'] ?? ''}',
      'mqtt_client_id=${ap['mqtt_client_id'] ?? ap['device_id'] ?? ''}',
      'location=${ap['location'] ?? ''}',
      'is_online=${(ap['is_online'] ?? false) ? 'true' : 'false'}',
    ].join(';');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // Main content
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                ? [AppColors.darkBg, AppColors.darkBgSecondary]
                : [AppColors.lightBg, Colors.white],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Status bar
                _buildConnectionStatusCard(isDark),

                // Error message
                if (_errorMessage != null)
                  _buildErrorCard(isDark),

                // Devices list
                Expanded(
                  child: appliances.isEmpty
                      ? _buildEmptyState(isDark)
                      : RefreshIndicator(
                          onRefresh: _loadDevicesFromBackend,
                          color: AppColors.primaryBlue,
                          child: ListView.builder(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 100),
                            itemCount: appliances.length,
                            itemBuilder: (context, index) =>
                                _buildModernApplianceCard(appliances[index], index, isDark),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        // Animated FAB - only show when there are devices (moves from center to corner)
        if (appliances.isNotEmpty)
          Positioned(
            bottom: 100,
            right: 16,
            child: FloatingActionButton(
              heroTag: 'addDeviceFab',
              onPressed: _addAppliance,
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              elevation: 6,
              child: const Icon(Icons.add_rounded, size: 28),
            ),
          ),
      ],
    );
  }

  Widget _buildConnectionStatusCard(bool isDark) {
    final isConnected = _connectionState == MqttConnectionState.connected;
    final deviceCount = appliances.length;
    final onlineCount = appliances.where((a) => a['isOn'] == true).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBgCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected
            ? AppColors.electricGreen.withOpacity(0.3)
            : Colors.orange.withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: (isConnected ? AppColors.electricGreen : Colors.orange).withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Main status row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isConnected
                    ? AppColors.electricGreen.withOpacity(0.15)
                    : Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isConnected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                  color: isConnected ? AppColors.electricGreen : Colors.orange,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isConnected ? 'Connected to HiveMQ' : 'Using Backend API',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark ? Colors.white : AppColors.darkBg,
                      ),
                    ),
                    Text(
                      isConnected
                        ? 'Real-time device updates active'
                        : 'Device control works via Heroku',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              if (_isLoadingDevices)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryBlue),
                )
              else
                PopupMenuButton<String>(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.more_vert_rounded, color: AppColors.primaryBlue, size: 20),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (action) async {
                    if (action == 'refresh') {
                      await _loadDevicesFromBackend();
                    } else if (action == 'clear_deleted') {
                      await _clearDeletedDeviceIds();
                      await _loadDevicesFromBackend();
                    } else if (action == 'clear_cache') {
                      await _clearAllCache();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'refresh',
                      child: Row(
                        children: [
                          Icon(Icons.refresh_rounded, size: 20),
                          SizedBox(width: 12),
                          Text('Refresh Devices'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'clear_deleted',
                      child: Row(
                        children: [
                          const Icon(Icons.restore_rounded, size: 20),
                          const SizedBox(width: 12),
                          Text('Restore Deleted (${_deletedDeviceIds.length})'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'clear_cache',
                      child: Row(
                        children: [
                          Icon(Icons.delete_sweep_rounded, size: 20, color: Colors.orange),
                          SizedBox(width: 12),
                          Text('Clear Cache', style: TextStyle(color: Colors.orange)),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // Device stats row (only show if there are devices)
          if (deviceCount > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // Total devices
                  _buildStatItem(
                    icon: Icons.devices_rounded,
                    label: 'Devices',
                    value: '$deviceCount',
                    color: AppColors.primaryBlue,
                    isDark: isDark,
                  ),
                  // Divider
                  Container(
                    width: 1,
                    height: 30,
                    color: Colors.grey.withOpacity(0.3),
                  ),
                  // Active devices
                  _buildStatItem(
                    icon: Icons.power_rounded,
                    label: 'Active',
                    value: '$onlineCount',
                    color: AppColors.electricGreen,
                    isDark: isDark,
                  ),
                  // Divider
                  Container(
                    width: 1,
                    height: 30,
                    color: Colors.grey.withOpacity(0.3),
                  ),
                  // Inactive devices
                  _buildStatItem(
                    icon: Icons.power_off_rounded,
                    label: 'Inactive',
                    value: '${deviceCount - onlineCount}',
                    color: Colors.grey,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade500,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_rounded, color: AppColors.error, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.error, size: 20),
            onPressed: () => setState(() => _errorMessage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBgCard : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.devices_rounded,
              size: 50,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No devices yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : AppColors.darkBg,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your smart devices to control them',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _addAppliance,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Device'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernApplianceCard(Map<String, dynamic> appliance, int index, bool isDark) {
    final isOn = appliances[index]['isOn'] ?? false;
    final deviceName = appliance['name'] as String? ?? 'Unknown';
    final deviceTopic = appliance['topic'] as String? ?? 'No topic';
    final pin = appliance['pin'] ?? 23;

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 300 + (index * 50)),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBgCard : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isOn
              ? AppColors.electricGreen.withOpacity(0.3)
              : Colors.grey.withOpacity(0.2),
            width: isOn ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isOn
                ? AppColors.electricGreen.withOpacity(0.15)
                : Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _toggleDevice(index),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Power Button
                  GestureDetector(
                    onTap: () => _toggleDevice(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isOn
                            ? [AppColors.electricGreen, AppColors.electricGreen.withOpacity(0.7)]
                            : [Colors.grey.shade400, Colors.grey.shade500],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isOn
                              ? AppColors.electricGreen.withOpacity(0.4)
                              : Colors.black.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.power_settings_new_rounded, color: Colors.white, size: 28),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Device Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          deviceName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : AppColors.darkBg,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.memory_rounded, size: 14, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text(
                              'GPIO $pin',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isOn
                                  ? AppColors.electricGreen.withOpacity(0.15)
                                  : Colors.grey.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                isOn ? 'ON' : 'OFF',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isOn ? AppColors.electricGreen : Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Actions
                  PopupMenuButton<String>(
                    tooltip: 'Device actions',
                    icon: Icon(Icons.more_vert_rounded, color: Colors.grey.shade500),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (action) async {
                      if (action == 'edit') {
                        await _editAppliance(index);
                      } else if (action == 'delete') {
                        await _deleteAppliance(index);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem<String>(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_rounded, size: 20),
                            SizedBox(width: 12),
                            Text('Edit name'),
                          ],
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_rounded, size: 20, color: AppColors.error),
                            SizedBox(width: 12),
                            Text('Delete', style: TextStyle(color: AppColors.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleDevice(int index) async {
    final isTurningOn = !appliances[index]['isOn'];
    final action = isTurningOn ? 'ON' : 'OFF';
    final topic = appliances[index]['topic'] as String;
    final name = appliances[index]['name'] as String? ?? 'Device';

    setState(() {
      appliances[index]['isOn'] = isTurningOn;
    });

    final success = await _sendDeviceControl(topic, action);

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to control $name'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

      setState(() {
        appliances[index]['isOn'] = !isTurningOn;
      });
    }
  }
}
