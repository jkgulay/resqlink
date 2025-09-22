import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/messaging/message_debug_service.dart';
import '../../services/p2p/p2p_main_service.dart';

/// Debug panel widget for testing message flow and connectivity
class MessageDebugPanel extends StatefulWidget {
  final P2PMainService p2pService;

  const MessageDebugPanel({
    super.key,
    required this.p2pService,
  });

  @override
  State<MessageDebugPanel> createState() => _MessageDebugPanelState();
}

class _MessageDebugPanelState extends State<MessageDebugPanel> {
  final MessageDebugService _debugService = MessageDebugService();
  final TextEditingController _testMessageController = TextEditingController();
  
  bool _debugEnabled = false;
  TestResult? _lastTestResult;
  String _debugReport = '';
  Map<String, dynamic> _messageStats = {};

  @override
  void initState() {
    super.initState();
    _debugEnabled = _debugService.isDebugModeEnabled;
    _updateDebugInfo();
  }

  @override
  void dispose() {
    _testMessageController.dispose();
    super.dispose();
  }

  void _updateDebugInfo() {
    setState(() {
      _debugReport = _debugService.getDebugReport();
      _messageStats = _debugService.getMessageStats();
    });
  }

  void _toggleDebugMode() {
    setState(() {
      _debugEnabled = !_debugEnabled;
      if (_debugEnabled) {
        _debugService.enableDebugMode();
      } else {
        _debugService.disableDebugMode();
      }
    });
    _updateDebugInfo();
  }

  Future<void> _runMessageTest() async {
    final testMessage = _testMessageController.text.trim();
    if (testMessage.isEmpty) {
      _testMessageController.text = _debugService.generateTestMessage();
    }

    final result = await _debugService.testMessageSending(
      widget.p2pService,
      _testMessageController.text,
    );

    setState(() {
      _lastTestResult = result;
    });

    _updateDebugInfo();

    // Show result in snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? '✅ Message test passed (${result.duration.inMilliseconds}ms)'
                : '❌ Message test failed: ${result.error}',
          ),
          backgroundColor: result.success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _runConnectionTest() async {
    final result = await _debugService.testConnectionEstablishment(
      widget.p2pService,
    );

    setState(() {
      _lastTestResult = result;
    });

    _updateDebugInfo();

    // Show result in dialog
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(result.success ? '✅ Connection Test' : '❌ Connection Test'),
          content: SingleChildScrollView(
            child: Text(result.toString()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _clearDebugData() {
    _debugService.clearTraces();
    setState(() {
      _lastTestResult = null;
    });
    _updateDebugInfo();
  }

  void _copyDebugReport() {
    Clipboard.setData(ClipboardData(text: _debugReport));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Debug report copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Message Debug Panel'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_debugEnabled ? Icons.bug_report : Icons.bug_report_outlined),
            onPressed: _toggleDebugMode,
            tooltip: 'Toggle Debug Mode',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _updateDebugInfo,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusCard(),
            const SizedBox(height: 16),
            _buildTestSection(),
            const SizedBox(height: 16),
            _buildStatsSection(),
            const SizedBox(height: 16),
            _buildDebugReportSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _debugEnabled ? Icons.bug_report : Icons.bug_report_outlined,
                  color: _debugEnabled ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'Debug Mode: ${_debugEnabled ? 'ON' : 'OFF'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildServiceStatus(),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceStatus() {
    return Column(
      children: [
        _buildStatusRow('P2P Service', widget.p2pService.isConnected ? 'Connected' : 'Disconnected'),
        _buildStatusRow('Device ID', widget.p2pService.deviceId ?? 'Unknown'),
        _buildStatusRow('User Name', widget.p2pService.userName ?? 'Unknown'),
        _buildStatusRow('Current Role', widget.p2pService.currentRole.name),
        _buildStatusRow('Emergency Mode', widget.p2pService.emergencyMode ? 'ON' : 'OFF'),
        _buildStatusRow('Connected Devices', '${widget.p2pService.connectedDevices.length}'),
      ],
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(
            flex: 3,
            child: Text(value, style: const TextStyle(fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  Widget _buildTestSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Testing Tools',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            
            // Message test
            TextField(
              controller: _testMessageController,
              decoration: const InputDecoration(
                labelText: 'Test Message',
                hintText: 'Enter test message or leave empty for auto-generated',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.send),
                    label: const Text('Test Message'),
                    onPressed: _runMessageTest,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.wifi),
                    label: const Text('Test Connection'),
                    onPressed: _runConnectionTest,
                  ),
                ),
              ],
            ),
            
            if (_lastTestResult != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _lastTestResult!.success
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  border: Border.all(
                    color: _lastTestResult!.success ? Colors.green : Colors.red,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _lastTestResult!.success ? Icons.check_circle : Icons.error,
                          color: _lastTestResult!.success ? Colors.green : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Last Test: ${_lastTestResult!.success ? 'PASSED' : 'FAILED'}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Duration: ${_lastTestResult!.duration.inMilliseconds}ms'),
                    if (_lastTestResult!.error != null)
                      Text('Error: ${_lastTestResult!.error}'),
                    if (_lastTestResult!.details != null)
                      Text('Details: ${_lastTestResult!.details}'),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Message Statistics',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear'),
                  onPressed: _clearDebugData,
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            if (_messageStats.isNotEmpty) ...[
              _buildStatsRow('Total Traces', '${_messageStats['total_traces'] ?? 0}'),
              _buildStatsRow('Sent Messages', '${_messageStats['sent_messages'] ?? 0}'),
              _buildStatsRow('Received Messages', '${_messageStats['received_messages'] ?? 0}'),
              _buildStatsRow('Failed Messages', '${_messageStats['failed_messages'] ?? 0}'),
              _buildStatsRow(
                'Success Rate',
                '${((_messageStats['success_rate'] ?? 0.0) * 100).toStringAsFixed(1)}%',
              ),
            ] else ...[
              const Text('No message statistics available. Enable debug mode and send some messages.'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugReportSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Debug Report',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
                  onPressed: _copyDebugReport,
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            Container(
              width: double.infinity,
              height: 300,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _debugReport,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}