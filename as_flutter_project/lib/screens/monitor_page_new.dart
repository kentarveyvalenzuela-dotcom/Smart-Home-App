import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/config_service.dart';

class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  List<Map<String, dynamic>> _recordings = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  Future<void> _loadRecordings() async {
    final base = ConfigService().backendUrl;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final jsonResp = await http.get(Uri.parse('$base/camera/images/json'));
      if (!mounted) return;

      if (jsonResp.statusCode == 200) {
        final List<dynamic> arr = json.decode(jsonResp.body);
        final items = arr.map<Map<String, dynamic>>((e) {
          return {
            'url': e['url'] as String? ?? '',
            'date': e['date'] as String? ?? '',
            'device_id': e['device_id'] as String? ?? '',
            'filename': e['filename'] as String? ?? '',
          };
        }).toList();
        setState(() {
          _recordings = items;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loaded ${items.length} recording(s).')),
        );
      } else {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load recordings (${jsonResp.statusCode}).';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Cannot reach backend. Check network and URL.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera Monitor'),
        backgroundColor: Colors.deepPurple,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                )
              : _recordings.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.videocam_off,
                              size: 48, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text('No recordings found',
                              style: TextStyle(fontSize: 16)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _recordings.length,
                      itemBuilder: (context, index) {
                        final rec = _recordings[index];
                        return Card(
                          margin: const EdgeInsets.all(8),
                          child: ListTile(
                            leading:
                                const Icon(Icons.image, color: Colors.blue),
                            title: Text(rec['filename'] ?? 'Image'),
                            subtitle: Text(rec['date'] ?? 'Unknown date'),
                            trailing: const Icon(Icons.download),
                            onTap: () {
                              // Open image viewer
                              showDialog(
                                context: context,
                                builder: (context) => Dialog(
                                  child: Image.network(
                                    rec['url'] ?? '',
                                    errorBuilder: (_, __, ___) =>
                                        const Center(
                                          child: Text('Image failed to load'),
                                        ),
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadRecordings,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
