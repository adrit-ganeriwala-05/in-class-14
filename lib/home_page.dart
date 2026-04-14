// =============================================================================
// home_page.dart — Phase 5: Connect payload data to the UI
//
// Payload keys this page responds to:
//   message.data['asset']   → switches displayed image/animation
//   message.data['action']  → drives an animation or UI action
//   message.data['screen']  → optional deep-link hint (logged)
//
// State machine:
//   'waiting'   → default grey card, "Waiting for a cloud message"
//   'received'  → green card, shows notification title + data
//   'promo'     → teal card with promo asset
//   'alert'     → amber card with alert asset
// =============================================================================

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fcm_service.dart';

// Simple enum to drive UI state
enum MessageState { waiting, received, promo, alert }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  // ── FCM ──────────────────────────────────────────────────────────────────
  final FCMService _fcmService = FCMService();
  String? _fcmToken;

  // ── Message state ─────────────────────────────────────────────────────────
  MessageState _msgState = MessageState.waiting;
  String _statusText = 'Waiting for a cloud message…';
  String _imagePath = 'assets/images/default.png';
  String? _lastTitle;
  String? _lastBody;
  Map<String, dynamic> _lastData = {};
  String _handlerUsed = '—';
  int _messageCount = 0;

  // ── Animation ─────────────────────────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // ── History log ───────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _messageHistory = [];

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    // Pulse animation for when a message arrives
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Initialize FCM — this wires all three handlers
    _fcmService.initialize(onData: _handleIncomingMessage);

    // Retrieve and display the token
    _fcmService.getToken().then((token) {
      setState(() => _fcmToken = token);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Core payload handler — called by all three FCM paths
  // ─────────────────────────────────────────────────────────────────────────
  void _handleIncomingMessage(RemoteMessage message) {
    // Determine which handler fired (best-effort detection)
    final String handler = _detectHandler(message);

    // Parse payload keys (case-sensitive — must match Firebase Console exactly)
    final String? asset = message.data['asset'] as String?;
    final String? action = message.data['action'] as String?;
    final String? screen = message.data['screen'] as String?;

    // Determine new UI state
    MessageState newState = MessageState.received;
    String newImagePath = 'assets/images/default.png';

    if (asset == 'promo' || action == 'show_animation') {
      newState = MessageState.promo;
      newImagePath = 'assets/images/promo.png';
    } else if (asset == 'alert') {
      newState = MessageState.alert;
      newImagePath = 'assets/images/alert.png';
    }

    if (screen != null) {
      debugPrint('🗺️  Deep-link hint received: screen=$screen');
    }

    // Add to history
    _messageHistory.insert(0, {
      'id': message.messageId ?? 'unknown',
      'handler': handler,
      'title': message.notification?.title ?? '(no title)',
      'body': message.notification?.body ?? '(no body)',
      'data': Map<String, dynamic>.from(message.data),
      'time': DateTime.now(),
    });

    setState(() {
      _msgState = newState;
      _statusText = message.notification?.title ?? 'Payload received';
      _imagePath = newImagePath;
      _lastTitle = message.notification?.title;
      _lastBody = message.notification?.body;
      _lastData = Map<String, dynamic>.from(message.data);
      _handlerUsed = handler;
      _messageCount++;
    });

    // Trigger pulse animation
    _pulseController.forward(from: 0).then((_) => _pulseController.reverse());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Heuristic: detect which handler delivered the message (for evidence log)
  // ─────────────────────────────────────────────────────────────────────────
  String _detectHandler(RemoteMessage message) {
    // getInitialMessage fires synchronously inside initialize() before any
    // listener is registered. By the time onMessage or onMessageOpenedApp
    // would fire the app is already running, so we use count as a proxy.
    if (_messageCount == 0 && _msgState == MessageState.waiting) {
      return 'getInitialMessage() — terminated state';
    }
    // Cannot distinguish onMessage vs onMessageOpenedApp here reliably,
    // but we log both. The debug console shows exact handler.
    return 'onMessage / onMessageOpenedApp — see debug log';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FCM Activity 14'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Message History',
            onPressed: _showHistorySheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset UI',
            onPressed: _resetState,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusCard(),
            const SizedBox(height: 16),
            _buildTokenCard(),
            const SizedBox(height: 16),
            _buildPayloadCard(),
            const SizedBox(height: 16),
            _buildHandlerGuideCard(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Status card — changes color & content based on message state
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildStatusCard() {
    final Color cardColor;
    final IconData icon;

    switch (_msgState) {
      case MessageState.waiting:
        cardColor = Colors.grey.shade200;
        icon = Icons.cloud_outlined;
      case MessageState.received:
        cardColor = Colors.green.shade100;
        icon = Icons.cloud_done;
      case MessageState.promo:
        cardColor = const Color(0xFFE0F5F2);
        icon = Icons.local_offer;
      case MessageState.alert:
        cardColor = Colors.amber.shade100;
        icon = Icons.warning_amber;
    }

    return ScaleTransition(
      scale: _pulseAnimation,
      child: Card(
        color: cardColor,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(icon, size: 32, color: const Color(0xFF007B6E)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _statusText,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  if (_messageCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF007B6E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_messageCount',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
              if (_lastBody != null) ...[
                const SizedBox(height: 8),
                Text(
                  _lastBody!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              // Image display — shows asset based on payload
              const SizedBox(height: 12),
              _buildAssetDisplay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssetDisplay() {
    // We use a placeholder container since we can't ship real PNG assets
    // In a real project, swap this for Image.asset(_imagePath)
    final Color boxColor;
    final String label;

    switch (_msgState) {
      case MessageState.waiting:
        boxColor = Colors.grey.shade300;
        label = 'No message yet\nassets/images/default.png';
      case MessageState.received:
        boxColor = Colors.green.shade200;
        label = 'Message received!\n$_imagePath';
      case MessageState.promo:
        boxColor = const Color(0xFF007B6E).withOpacity(0.3);
        label = '🎉 Promo asset triggered!\n$_imagePath';
      case MessageState.alert:
        boxColor = Colors.amber.shade200;
        label = '⚠️ Alert asset triggered!\n$_imagePath';
    }

    return Container(
      width: double.infinity,
      height: 100,
      decoration: BoxDecoration(
        color: boxColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Colors.black87),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Token card
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildTokenCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.key, color: Color(0xFF007B6E)),
                const SizedBox(width: 8),
                Text('FCM Device Token',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        )),
              ],
            ),
            const SizedBox(height: 8),
            if (_fcmToken == null)
              const Text('Fetching token…',
                  style: TextStyle(fontStyle: FontStyle.italic))
            else ...[
              SelectableText(
                _fcmToken!,
                style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _fcmToken!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Token copied! Paste into Firebase Console.'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy Token for Firebase Console'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007B6E),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Copy this token → Firebase Console → Cloud Messaging → Send test message → paste as registration token',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Payload detail card
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildPayloadCard() {
    if (_messageCount == 0) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.data_object, color: Color(0xFF007B6E)),
                  const SizedBox(width: 8),
                  Text('Last Payload',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          )),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'No message received yet.\n\nSend a test message from Firebase Console using the token above.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 12),
              const Text(
                'Recommended test payload:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const SelectableText(
                  '{\n'
                  '  "notification": {\n'
                  '    "title": "Activity 14 Test",\n'
                  '    "body": "Show the promo asset now"\n'
                  '  },\n'
                  '  "data": {\n'
                  '    "asset": "promo",\n'
                  '    "action": "show_animation",\n'
                  '    "screen": "home"\n'
                  '  }\n'
                  '}',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.data_object, color: Color(0xFF007B6E)),
                const SizedBox(width: 8),
                Text('Last Payload',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        )),
              ],
            ),
            const Divider(),
            _payloadRow('Title', _lastTitle ?? '—'),
            _payloadRow('Body', _lastBody ?? '—'),
            _payloadRow('Handler', _handlerUsed),
            const SizedBox(height: 4),
            const Text('data {}',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 12)),
            ..._lastData.entries.map(
              (e) => _payloadRow('  ${e.key}', e.value.toString()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _payloadRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(key,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Handler guide card
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHandlerGuideCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.map_outlined, color: Color(0xFF007B6E)),
                const SizedBox(width: 8),
                Text('Handler Map',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        )),
              ],
            ),
            const Divider(),
            _handlerRow(
              'onMessage',
              'App FOREGROUND',
              'App is open & visible',
              Colors.green,
            ),
            _handlerRow(
              'onMessageOpenedApp',
              'App BACKGROUND',
              'User tapped notification',
              Colors.blue,
            ),
            _handlerRow(
              'getInitialMessage()',
              'App TERMINATED',
              'Cold start from notification',
              Colors.purple,
            ),
          ],
        ),
      ),
    );
  }

  Widget _handlerRow(
      String handler, String when, String useFor, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 4, right: 8),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(handler,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: 12)),
                Text('When: $when',
                    style: const TextStyle(fontSize: 11)),
                Text('Use for: $useFor',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // History bottom sheet
  // ─────────────────────────────────────────────────────────────────────────
  void _showHistorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Message History (${_messageHistory.length})',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const Divider(),
            if (_messageHistory.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('No messages received yet.',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              Expanded(
                child: ListView.separated(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _messageHistory.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (_, i) {
                    final m = _messageHistory[i];
                    final time = m['time'] as DateTime;
                    return ListTile(
                      dense: true,
                      title: Text(m['title'] as String),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m['body'] as String),
                          Text(
                            'Handler: ${m['handler']}',
                            style: const TextStyle(
                                fontSize: 10,
                                fontStyle: FontStyle.italic),
                          ),
                          Text(
                            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Reset state
  // ─────────────────────────────────────────────────────────────────────────
  void _resetState() {
    setState(() {
      _msgState = MessageState.waiting;
      _statusText = 'Waiting for a cloud message…';
      _imagePath = 'assets/images/default.png';
      _lastTitle = null;
      _lastBody = null;
      _lastData = {};
      _handlerUsed = '—';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('UI reset — ready for next test')),
    );
  }
}