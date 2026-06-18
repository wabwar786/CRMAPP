// lib/dashboard.dart
// [CHANGED] Full rewrite:
//   - Fully responsive for all Android screen sizes
//   - No overflow errors
//   - Web View button added to header
//   - All existing functionality preserved
//   - Modern, clean UI with LayoutBuilder / SafeArea / Wrap

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:line_icons/line_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartcrm_project/TaskScreen.dart';
import 'package:smartcrm_project/login.dart';
import 'package:smartcrm_project/webview_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http_parser/http_parser.dart';

class DashboardScreen extends StatefulWidget {
  final String userId;
  final String cCode;
  final String username;

  const DashboardScreen({
    super.key,
    required this.userId,
    required this.cCode,
    required this.username,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // ─── Debug ───────────────────────────────────────────────────────────────
  static const bool _debugMode = true;
  void _logDebug(String msg, {dynamic data}) {
    if (_debugMode) developer.log(msg, name: 'CRM_Dashboard', error: data);
  }

  // ─── Scaffold / UI state ─────────────────────────────────────────────────
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isLoading = false;
  final List<Map<String, dynamic>> _leads = [];
  List<Map<String, dynamic>> _filteredLeads = [];
  bool _permissionsGranted = false;
  bool _permissionsChecked = false;
  int? _expandedLeadIndex;

  List<Map<String, dynamic>> _sites = [];
  bool _isFetchingSites = false;
  String? _siteFetchError;
  String _currentFilter = 'All';
  String? _selectedSite;
  int _selectedNavIndex = 0;

  // ─── Call tracking ────────────────────────────────────────────────────────
  static const _callChannel = MethodChannel('com.your.app/call_tracker');
  static const _callStateChannel = MethodChannel('com.your.app/call_state');
  String? _currentCallLeadId;
  String? _currentCallPhoneNumber;
  Timer? _callCheckTimer;
  DateTime? _callStartTime;
  final Set<String> _loggedCallIds = {};
  String? _activeIncomingLeadId;
  String? _activeIncomingPhoneNumber;
  DateTime? _activeIncomingStartTime;
  final List<Map<String, dynamic>> _pendingRemarkCalls = [];

  // ─── Design tokens ────────────────────────────────────────────────────────
  final Color _primaryColor = const Color(0xFF049881);
  final Color _secondaryColor = const Color(0xFF8B0000);
  final Color _backgroundColor = const Color(0xFFF0F4F8);
  final Color _cardColor = Colors.white;
  final Color _textColor = const Color(0xFF1A2332);
  final Color _lightTextColor = const Color(0xFF6B7A8D);
  final List<Color> _headerGradient = [
    const Color(0xFF049881),
    const Color(0xFF026D5E),
    const Color(0xFF023D38),
  ];
  final Map<String, Color> _statusColors = {
    'New lead': const Color(0xFF2196F3),
    'Contacted': const Color(0xFFFF9800),
    'Qualified': const Color(0xFF4CAF50),
    'Closed': const Color(0xFFF44336),
    'Proposal Sent': const Color(0xFF9C27B0),
    'Follow up': const Color(0xFF673AB7),
    'Ready for sale': const Color(0xFF009688),
    'Meeting': const Color(0xFF795548),
    'Disqualified': const Color(0xFFFC0000),
    'Pending': const Color(0xFFFA9600),
  };

  // ─── API config ───────────────────────────────────────────────────────────
  static const String _baseUrl =
      'https://smartcrmbackend-production-56c0.up.railway.app';
  static const String _leadsEndpoint = '/api/leads';
  static const String _callLogEndpoint = '/api/call-log';
  static const String _followUpEndpoint = '/api/follow-up';
  static const String _readyForSaleEndpoint = '/api/ready-for-sale';
  static const String _meetingEndpoint = '/api/schedule-meeting';
  static const String _disqualifyEndpoint = '/api/disqualify';
  static const Duration _apiTimeout = Duration(seconds: 30);
  static const Duration _maxCallDuration = Duration(hours: 24);
  static const Duration _callCheckInterval = Duration(seconds: 5);
  static const int _maxCallCheckAttempts = 720;
  static const String _recordingChannel = 'com.your.app/call_recording';
  static const String _recordingUploadEndpoint = '/api/upload-recording';

  int _notificationCount = 0;
  Timer? _notificationTimer;

  // ─── Lifecycle ───────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _logDebug('Dashboard init: ${widget.userId}');
    _loadLoggedCallIds();
    _fetchNotificationCount();
    _startNotificationTimer();
    _setupCallStateListener();

    const MethodChannel(_recordingChannel).setMethodCallHandler((call) async {
      if (call.method == 'onCallRecording') {
        final number = call.arguments['number'] as String;
        final filePath = call.arguments['filePath'] as String;
        final lead = _leads.firstWhere(
          (l) => l['c_phone']?.toString() == number,
          orElse: () => {},
        );
        if (lead.isNotEmpty) {
          await _handleCallRecording(lead['leadid']?.toString() ?? '', filePath);
        }
      }
      return null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkAndRequestPermissions();
      await _fetchSites();
      await _fetchLeads();
      await _loadPendingRemarkCalls();
      _showTodayFollowupsPopup();
    });
  }

  @override
  void dispose() {
    _callCheckTimer?.cancel();
    _notificationTimer?.cancel();
    _callStateChannel.setMethodCallHandler(null);
    super.dispose();
  }

  // ─── Web View switch ──────────────────────────────────────────────────────
  // [CHANGED] Reads saved password and opens WebViewScreen
  Future<void> _switchToWebView() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final password = prefs.getString('password') ?? '';
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebViewScreen(
          userId: widget.userId,
          cCode: widget.cCode,
          username: widget.username,
          password: password,
        ),
      ),
    );
  }

  // ─── Notifications ────────────────────────────────────────────────────────
  Future<void> _fetchNotificationCount() async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/notification-count'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'userId': widget.userId}),
          )
          .timeout(_apiTimeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && mounted) {
          setState(() => _notificationCount = data['count'] ?? 0);
        }
      }
    } catch (e) {
      _logDebug('Notification count error', data: e);
    }
  }

  void _startNotificationTimer() {
    _notificationTimer?.cancel();
    _notificationTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _fetchNotificationCount(),
    );
  }

  void _navigateToTasks() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            TaskScreen(userId: widget.userId, username: widget.username),
      ),
    ).then((_) => _fetchNotificationCount());
  }

  // ─── Permissions ─────────────────────────────────────────────────────────
  Future<void> _checkAndRequestPermissions() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      var micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) micStatus = await Permission.microphone.request();

      var phoneStatus = await Permission.phone.status;
      if (!phoneStatus.isGranted) phoneStatus = await Permission.phone.request();

      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        if (info.version.sdkInt < 33) {
          var st = await Permission.storage.status;
          if (!st.isGranted) await Permission.storage.request();
        }
      }

      if (mounted) {
        setState(() {
          _permissionsGranted = micStatus.isGranted && phoneStatus.isGranted;
          _permissionsChecked = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _permissionsChecked = true; _isLoading = false; });
    }
  }

  // ─── Sites ────────────────────────────────────────────────────────────────
  Future<void> _fetchSites() async {
    if (!mounted) return;
    setState(() { _isFetchingSites = true; _siteFetchError = null; });
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/sites'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'cCode': widget.cCode}),
          )
          .timeout(_apiTimeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _sites = List<Map<String, dynamic>>.from(data['sites']);
            _isFetchingSites = false;
          });
          return;
        }
      }
      throw Exception('Failed');
    } catch (e) {
      if (mounted) setState(() { _siteFetchError = 'Failed to load sites'; _isFetchingSites = false; });
    }
  }

  // ─── Leads ────────────────────────────────────────────────────────────────

  Future<void> _cacheLeadsForNativeBackgroundLogger() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cache = _leads.map((lead) => {
            'leadid': lead['leadid']?.toString() ?? '',
            'c_name': lead['c_name']?.toString() ?? '',
            'c_phone': lead['c_phone']?.toString() ?? '',
            'status': lead['status']?.toString() ?? '',
          }).toList();
      await prefs.setString('crm_leads_cache', jsonEncode(cache));
    } catch (_) {}
  }

  Future<void> _fetchLeads() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl$_leadsEndpoint'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({'userId': widget.userId, 'cCode': widget.cCode}),
          )
          .timeout(_apiTimeout);

      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final data = jsonDecode(response.body);
      if (data['success'] != true) throw Exception(data['message'] ?? 'Failed');

      if (mounted) {
        setState(() {
          _leads.clear();
          _leads.addAll(List<Map<String, dynamic>>.from(data['leads']));
          await _cacheLeadsForNativeBackgroundLogger();
          _applyFilters();
        });
      }
    } on TimeoutException {
      if (mounted) _showSnackBar('Request timed out. Please try again.', isError: true);
    } on http.ClientException catch (e) {
      if (mounted) _showSnackBar('Network error: ${e.message}', isError: true);
    } catch (e) {
      if (mounted) _showSnackBar('Failed to load leads.', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Filters ──────────────────────────────────────────────────────────────
  void _filterLeads([String? status]) {
    setState(() { _currentFilter = status ?? 'All'; _applyFilters(); });
  }

  void _filterLeadsBySite(String? siteName) {
    setState(() { _selectedSite = siteName; _applyFilters(); });
  }

  void _applyFilters() {
    List<Map<String, dynamic>> filtered = List.from(_leads);

    if (_selectedSite != null && _selectedSite!.isNotEmpty) {
      filtered = filtered.where((l) {
        final sn = l['site_name']?.toString().trim() ?? '';
        return sn.toLowerCase() == _selectedSite!.toLowerCase();
      }).toList();
    }

    if (_currentFilter != 'All') {
      if (_currentFilter == 'New') {
        filtered = filtered.where(_isNewLead).toList();
      } else if (_currentFilter == 'Due') {
        filtered = filtered.where(_isDueLead).toList();
      } else {
        filtered = filtered.where((l) => l['status'] == _currentFilter).toList();
      }
    }

    filtered.sort((a, b) {
      final an = _isNewLead(a), bn = _isNewLead(b);
      if (an != bn) return an ? -1 : 1;
      final ad = _isDueLead(a), bd = _isDueLead(b);
      if (ad != bd) return ad ? -1 : 1;
      return 0;
    });

    setState(() { _filteredLeads = filtered; _expandedLeadIndex = null; });
  }

  bool _isNewLead(Map<String, dynamic> lead) => lead['last_call_date'] == null;
  bool _isDueLead(Map<String, dynamic> lead) =>
      _getDaysRemainingColor(lead['nextdate']) == const Color(0xFFE53935);

  // ─── Call handling ────────────────────────────────────────────────────────
  Future<void> _makePhoneCall(String phoneNumber, String leadId) async {
    if (phoneNumber.isEmpty) return;
    final cleaned = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.isEmpty) return;

    setState(() {
      _currentCallLeadId = leadId;
      _currentCallPhoneNumber = cleaned;
      _callStartTime = DateTime.now();
    });

    if (_permissionsGranted) await _startCallRecording(cleaned);
    _startCallLogChecker();

    final uri = Uri(scheme: 'tel', path: cleaned);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('No dialer');
      }
    } catch (e) {
      _stopCallRecording();
      _stopCallLogChecker();
      _resetCallState();
      await _tryAlternativeCallMethods(cleaned);
    }
  }

  Future<void> _handleCallCompleted() async {
    if (!mounted || _currentCallLeadId == null || _currentCallPhoneNumber == null) return;
    try {
      final logs = await _getCallLogs(
        _currentCallPhoneNumber!,
        _callStartTime ?? DateTime.now().subtract(const Duration(hours: 24)),
      );
      if (logs.isEmpty) return;

      final newLogs = logs.where((log) {
        final id = '${log['date']}_${log['raw_duration_seconds']}_${log['type']}';
        return !_loggedCallIds.contains(id);
      }).toList();

      for (final log in newLogs) {
        await _logCall(_currentCallLeadId!, log['duration'], callLog: log);
      }
      if (newLogs.isNotEmpty) {
        _showSnackBar('Call logged successfully');
        final lead = _leads.firstWhere(
          (l) => l['leadid']?.toString() == _currentCallLeadId,
          orElse: () => {},
        );
        final log = newLogs.first;
        await _showCallRemarksDialog({
          'leadId': _currentCallLeadId!,
          'leadName': lead['c_name']?.toString() ?? 'Customer',
          'phone': _currentCallPhoneNumber!,
          'duration': log['duration']?.toString() ?? '00:00:00',
          'durationSeconds': log['raw_duration_seconds'] ?? 0,
          'subStatus': log['subStatus']?.toString() ?? 'Outgoing',
          'callDate': DateTime.fromMillisecondsSinceEpoch(log['date'] as int).toIso8601String(),
        });
      }
    } catch (e) {
      _logDebug('Error handling call completion', data: e);
    } finally {
      _resetCallState();
      _fetchLeads();
    }
  }

  Future<void> _handleCallRecording(String leadId, String filePath) async {
    if (!mounted || filePath.isEmpty) return;
    try {
      final file = File(filePath);
      if (!await file.exists()) throw Exception('File not found: $filePath');

      var request = http.MultipartRequest('POST', Uri.parse('$_baseUrl$_recordingUploadEndpoint'));
      request.fields['leadId'] = leadId;
      request.fields['userId'] = widget.userId;
      request.fields['cCode'] = widget.cCode;
      request.files.add(
        await http.MultipartFile.fromPath('recording', filePath,
            contentType: MediaType('audio', 'mpeg')),
      );

      final response = await request.send().timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        try { await file.delete(); } catch (_) {}
      }
    } catch (e) {
      _logDebug('Recording upload error', data: e);
      try { await File(filePath).delete(); } catch (_) {}
    }
  }

  Future<List<Map<String, dynamic>>> _getCallLogs(String phoneNumber, DateTime since) async {
    try {
      final result = await _callChannel.invokeMethod('getCallLogs', {
        'phoneNumber': phoneNumber,
        'since': since.millisecondsSinceEpoch,
      });
      if (result is List) {
        return result
            .map((log) {
              final m = Map<String, dynamic>.from(log);
              return {
                'id': m['id'],
                'number': m['number']?.toString() ?? '',
                'date': m['date'] as int? ?? 0,
                'duration': m['duration']?.toString() ?? '00:00:00',
                'raw_duration_seconds': m['raw_duration_seconds'] as int? ?? 0,
                'type': m['type'] as int? ?? 0,
                'subStatus': m['subStatus']?.toString() ?? 'Unknown',
                'name': m['name']?.toString() ?? '',
              };
            })
            .where((l) => l['date'] > 0)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>?> _getLatestCallLog(String phoneNumber) async {
    try {
      final result = await _callChannel.invokeMethod('getLatestCallLog', {
        'phoneNumber': phoneNumber,
        'since': _callStartTime?.millisecondsSinceEpoch ??
            DateTime.now().subtract(_maxCallDuration).millisecondsSinceEpoch,
        'silent': true,
      });
      if (result != null) {
        final m = Map<String, dynamic>.from(result);
        if (m['date'] == null || m['duration'] == null) return null;
        final id = '${m['date']}_${m['raw_duration_seconds']}_${m['type']}';
        if (_loggedCallIds.contains(id)) return null;
        return {
          'id': m['id'],
          'number': m['number']?.toString() ?? '',
          'date': m['date'] as int? ?? 0,
          'duration': m['duration']?.toString() ?? '00:00:00',
          'raw_duration_seconds': m['raw_duration_seconds'] as int? ?? 0,
          'type': m['type'] as int? ?? 0,
          'subStatus': m['subStatus']?.toString() ?? 'Unknown',
          'name': m['name']?.toString() ?? '',
        };
      }
    } catch (_) {}
    return null;
  }

  String _determineCallStatus(int durationSeconds, int callType) {
    if (durationSeconds == 0) return 'Not Picked';
    if (durationSeconds <= 60) return 'Connected';
    if (durationSeconds <= 120) return 'Verified';
    return 'Quality';
  }

  Future<void> _logCall(String leadId, dynamic callDuration,
      {Map<String, dynamic>? callLog}) async {
    if (!mounted) return;
    final callId = callLog != null
        ? '${callLog['date']}_${callLog['raw_duration_seconds']}_${callLog['type']}'
        : 'manual_${DateTime.now().millisecondsSinceEpoch}';
    if (_loggedCallIds.contains(callId)) return;

    try {
      final body = {
        'leadId': leadId,
        'userId': widget.userId,
        'cCode': widget.cCode,
        'callLogs': [
          {
            'callDuration': callLog?['duration'] ?? callDuration,
            'callStatus': callLog != null
                ? _determineCallStatus(
                    callLog['raw_duration_seconds'] as int? ?? 0,
                    callLog['type'] as int? ?? 0)
                : 'Unknown',
            'callType': 'Phone',
            'subStatus': callLog?['subStatus'] ?? 'Outgoing',
            'callLogDate': callLog != null
                ? DateTime.fromMillisecondsSinceEpoch(callLog['date'] as int)
                    .toIso8601String()
                : DateTime.now().toIso8601String(),
            'callUniqueId': callId,
          },
        ],
      };

      final response = await http
          .post(
            Uri.parse('$_baseUrl$_callLogEndpoint'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_apiTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && callLog != null) {
          _loggedCallIds.add(callId);
          await _saveLoggedCallId(callId);
        }
      }
    } catch (e) {
      _logDebug('Error logging call', data: e);
    }
  }

  Future<void> _saveLoggedCallId(String callId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('logged_call_ids') ?? [];
      if (!list.contains(callId)) {
        list.add(callId);
        await prefs.setStringList('logged_call_ids', list);
      }
    } catch (_) {}
  }

  Future<void> _loadLoggedCallIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _loggedCallIds.addAll(prefs.getStringList('logged_call_ids') ?? []);
    } catch (_) {}
  }

  Future<void> _startCallRecording(String phoneNumber) async {
    try {
      await const MethodChannel(_recordingChannel).invokeMethod('startRecording', {
        'phoneNumber': phoneNumber,
        'leadId': _currentCallLeadId,
        'userId': widget.userId,
        'cCode': widget.cCode,
      });
    } catch (_) {}
  }

  Future<void> _stopCallRecording() async {
    try {
      await const MethodChannel(_recordingChannel).invokeMethod('stopRecording');
    } catch (_) {}
  }

  void _resetCallState() {
    setState(() {
      _currentCallLeadId = null;
      _currentCallPhoneNumber = null;
      _callStartTime = null;
    });
  }

  Future<void> _tryAlternativeCallMethods(String phoneNumber) async {
    final whatsapp = Uri.parse('https://wa.me/$phoneNumber');
    if (await canLaunchUrl(whatsapp)) { await launchUrl(whatsapp); return; }
    final sms = Uri.parse('sms:$phoneNumber');
    if (await canLaunchUrl(sms)) { await launchUrl(sms); return; }
    await Clipboard.setData(ClipboardData(text: phoneNumber));
    _showSnackBar('Number copied: $phoneNumber');
  }

  void _startCallLogChecker() {
    _callCheckTimer?.cancel();
    int attempts = 0;
    _callCheckTimer = Timer.periodic(_callCheckInterval, (timer) async {
      if (_currentCallPhoneNumber == null || !mounted) { _stopCallLogChecker(); return; }
      if (++attempts > _maxCallCheckAttempts) { _stopCallLogChecker(); return; }
      try {
        final log = await _getLatestCallLog(_currentCallPhoneNumber!);
        if (log != null) {
          final callDate = DateTime.fromMillisecondsSinceEpoch(log['date'] ?? 0);
          if (_callStartTime != null && callDate.isAfter(_callStartTime!)) {
            await _stopCallRecording();
            if (mounted) await _handleCallCompleted();
            _stopCallLogChecker();
          }
        }
      } catch (_) {}
    });
  }

  void _stopCallLogChecker() {
    _callCheckTimer?.cancel();
    _callCheckTimer = null;
    _callStartTime = null;
  }


  // ─── CRM incoming call / remarks / follow-up helpers ─────────────────────
  void _setupCallStateListener() {
    _callStateChannel.setMethodCallHandler((call) async {
      try {
        if (call.method == 'onIncomingCall') {
          final number = call.arguments?.toString() ?? '';
          final lead = _findLeadByPhone(number);

          // Unknown/personal numbers are ignored completely.
          if (lead == null) {
            _activeIncomingLeadId = null;
            _activeIncomingPhoneNumber = null;
            _activeIncomingStartTime = null;
            return null;
          }

          _activeIncomingLeadId = lead['leadid']?.toString();
          _activeIncomingPhoneNumber = _cleanPhone(number);
          _activeIncomingStartTime = DateTime.now();
          _showSnackBar('Incoming CRM call: ${lead['c_name'] ?? number}');
          return null;
        }

        if (call.method == 'onCallConnected') {
          final number = call.arguments?.toString() ?? '';
          if (_activeIncomingLeadId != null && _activeIncomingPhoneNumber == null) {
            _activeIncomingPhoneNumber = _cleanPhone(number);
          }
          _activeIncomingStartTime ??= DateTime.now();
          return null;
        }

        if (call.method == 'onCallDisconnected') {
          final args = Map<String, dynamic>.from(call.arguments ?? {});
          final number = args['number']?.toString() ?? _activeIncomingPhoneNumber ?? '';
          final wasConnected = args['wasConnected'] == true;
          await _handleIncomingCallEnded(number, wasConnected: wasConnected);
          return null;
        }
      } catch (e) {
        _logDebug('Call state event failed', data: e);
      }
      return null;
    });
  }

  String _cleanPhone(String phone) => phone.replaceAll(RegExp(r'[^0-9+]'), '');

  String _phoneKey(String phone) {
    final cleaned = _cleanPhone(phone);
    if (cleaned.length <= 10) return cleaned;
    return cleaned.substring(cleaned.length - 10);
  }

  Map<String, dynamic>? _findLeadByPhone(String phoneNumber) {
    final key = _phoneKey(phoneNumber);
    if (key.isEmpty) return null;
    for (final lead in _leads) {
      final p = lead['c_phone']?.toString() ?? '';
      final lk = _phoneKey(p);
      if (lk.isNotEmpty && (lk == key || key.endsWith(lk) || lk.endsWith(key))) {
        return lead;
      }
    }
    return null;
  }

  Future<void> _handleIncomingCallEnded(String phoneNumber, {required bool wasConnected}) async {
    final lead = _activeIncomingLeadId != null
        ? _leads.firstWhere(
            (l) => l['leadid']?.toString() == _activeIncomingLeadId,
            orElse: () => {},
          )
        : _findLeadByPhone(phoneNumber);

    // Unknown/personal numbers are ignored completely.
    if (lead == null || lead.isEmpty) {
      _activeIncomingLeadId = null;
      _activeIncomingPhoneNumber = null;
      _activeIncomingStartTime = null;
      return;
    }

    final since = _activeIncomingStartTime ?? DateTime.now().subtract(const Duration(hours: 6));
    final logs = await _getCallLogs(phoneNumber, since);
    Map<String, dynamic>? log;
    for (final l in logs) {
      final sub = l['subStatus']?.toString().toLowerCase() ?? '';
      if (sub == 'incoming' || sub == 'missed' || sub == 'rejected') {
        log = l;
        break;
      }
    }

    log ??= {
      'date': DateTime.now().millisecondsSinceEpoch,
      'duration': '00:00:00',
      'raw_duration_seconds': 0,
      'type': wasConnected ? 1 : 3,
      'subStatus': wasConnected ? 'Incoming' : 'Missed',
      'number': phoneNumber,
    };

    await _logCall(lead['leadid']?.toString() ?? '', log['duration'], callLog: log);

    final callInfo = {
      'leadId': lead['leadid']?.toString() ?? '',
      'leadName': lead['c_name']?.toString() ?? 'Customer',
      'phone': phoneNumber,
      'duration': log['duration']?.toString() ?? '00:00:00',
      'durationSeconds': log['raw_duration_seconds'] ?? 0,
      'subStatus': log['subStatus']?.toString() ?? (wasConnected ? 'Incoming' : 'Missed'),
      'callDate': DateTime.fromMillisecondsSinceEpoch(log['date'] as int).toIso8601String(),
      'callUniqueId': '${log['date']}_${log['raw_duration_seconds']}_${log['type']}',
    };

    if (mounted) {
      await _showCallRemarksDialog(callInfo);
    } else {
      await _addPendingRemarkCall(callInfo);
    }

    _activeIncomingLeadId = null;
    _activeIncomingPhoneNumber = null;
    _activeIncomingStartTime = null;
    _fetchLeads();
  }

  Future<void> _showCallRemarksDialog(Map<String, dynamic> callInfo) async {
    final remarksCtrl = TextEditingController();
    DateTime? followDate;
    TimeOfDay? followTime;
    String outcome = 'Interested';
    String priority = 'Normal';
    final outcomes = ['Interested', 'Call Again', 'No Answer', 'Not Interested', 'Wrong Number', 'Meeting', 'Ready for Sale'];
    final priorities = ['Low', 'Normal', 'High'];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: StatefulBuilder(
          builder: (ctx, setS) => SingleChildScrollView(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: _primaryColor.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
                        child: Icon(Icons.call_end_rounded, color: _primaryColor),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Call Summary', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: _textColor)),
                            Text(callInfo['leadName']?.toString() ?? 'Customer', style: GoogleFonts.poppins(fontSize: 13, color: _lightTextColor)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFF6FAFD), borderRadius: BorderRadius.circular(14)),
                    child: Wrap(
                      spacing: 14,
                      runSpacing: 8,
                      children: [
                        _miniCallInfo(Icons.phone_rounded, callInfo['subStatus']?.toString() ?? 'Call'),
                        _miniCallInfo(Icons.timer_rounded, callInfo['duration']?.toString() ?? '00:00:00'),
                        _miniCallInfo(Icons.person_rounded, callInfo['phone']?.toString() ?? ''),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: outcome,
                    decoration: _dialogInputDecoration('Call Result'),
                    items: outcomes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setS(() => outcome = v ?? outcome),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: priority,
                    decoration: _dialogInputDecoration('Priority'),
                    items: priorities.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setS(() => priority = v ?? priority),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: remarksCtrl,
                    maxLines: 4,
                    decoration: _dialogInputDecoration('Remarks / Discussion Notes').copyWith(hintText: 'What did you discuss with customer?'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDateTimeField(
                          icon: Icons.calendar_month_rounded,
                          label: 'Follow-up Date',
                          value: followDate == null ? 'Optional' : DateFormat('dd MMM yyyy').format(followDate!),
                          onTap: () async {
                            final p = await showDatePicker(
                              context: ctx,
                              initialDate: followDate ?? DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (p != null) setS(() => followDate = p);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildDateTimeField(
                          icon: Icons.access_time_rounded,
                          label: 'Time',
                          value: followTime == null ? 'Optional' : followTime!.format(ctx),
                          onTap: () async {
                            final p = await showTimePicker(context: ctx, initialTime: followTime ?? TimeOfDay.now());
                            if (p != null) setS(() => followTime = p);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () async {
                            await _addPendingRemarkCall(callInfo);
                            if (mounted) Navigator.pop(dialogContext);
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
                          ),
                          child: Text('Later', style: GoogleFonts.poppins(color: _lightTextColor, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            final ok = await _saveCallRemarks(
                              callInfo: callInfo,
                              remarks: remarksCtrl.text.trim(),
                              outcome: outcome,
                              priority: priority,
                              followDate: followDate,
                              followTime: followTime,
                            );
                            if (ok && mounted) Navigator.pop(dialogContext);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text('Save', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
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

  Widget _miniCallInfo(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: _primaryColor),
        const SizedBox(width: 5),
        Text(text, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: _textColor)),
      ],
    );
  }

  InputDecoration _dialogInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 13, color: _lightTextColor),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _primaryColor, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Future<bool> _saveCallRemarks({
    required Map<String, dynamic> callInfo,
    required String remarks,
    required String outcome,
    required String priority,
    DateTime? followDate,
    TimeOfDay? followTime,
  }) async {
    try {
      setState(() => _isLoading = true);
      final leadId = callInfo['leadId']?.toString() ?? '';
      final callDate = callInfo['callDate']?.toString() ?? DateTime.now().toIso8601String();
      final callUniqueId = callInfo['callUniqueId']?.toString().isNotEmpty == true
          ? callInfo['callUniqueId'].toString()
          : 'remarks_${leadId}_${DateTime.parse(callDate).millisecondsSinceEpoch}';

      final response = await http.post(
        Uri.parse('$_baseUrl$_callLogEndpoint'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'leadId': leadId,
          'userId': widget.userId,
          'cCode': widget.cCode,
          'username': widget.username,
          'callLogs': [
            {
              'callDuration': callInfo['duration']?.toString() ?? '00:00:00',
              'callStatus': outcome,
              'callType': 'Phone',
              'subStatus': callInfo['subStatus']?.toString() ?? 'Outgoing',
              'callLogDate': callDate,
              'callUniqueId': callUniqueId,
              'remarks': remarks,
              'outcome': outcome,
              'priority': priority,
              'remarksPending': false,
            }
          ],
        }),
      ).timeout(_apiTimeout);

      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');

      if (followDate != null) {
        await http.post(
          Uri.parse('$_baseUrl$_followUpEndpoint'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'leadId': leadId,
            'userId': widget.userId,
            'cCode': widget.cCode,
            'followupDate': DateFormat('yyyy-MM-dd').format(followDate),
            'followupTime': followTime == null ? '09:00:00' : '${followTime.hour}:${followTime.minute}:00',
            'remarks': remarks,
            'username': widget.username,
            'priority': priority,
            'outcome': outcome,
          }),
        ).timeout(_apiTimeout);
      }

      await _removePendingRemarkCall(callInfo);
      _showSnackBar('Call remarks saved successfully');
      _fetchLeads();
      return true;
    } catch (e) {
      await _addPendingRemarkCall(callInfo);
      _showSnackBar('Could not save now. Added to Pending Remarks.', isError: true);
      return false;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addPendingRemarkCall(Map<String, dynamic> callInfo) async {
    final key = '${callInfo['leadId']}_${callInfo['callDate']}_${callInfo['subStatus']}';
    final copy = Map<String, dynamic>.from(callInfo)..['pendingKey'] = key;
    _pendingRemarkCalls.removeWhere((c) => c['pendingKey'] == key);
    _pendingRemarkCalls.add(copy);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_call_remarks', jsonEncode(_pendingRemarkCalls));
    if (mounted) setState(() {});
  }

  Future<void> _removePendingRemarkCall(Map<String, dynamic> callInfo) async {
    final key = callInfo['pendingKey']?.toString() ?? '${callInfo['leadId']}_${callInfo['callDate']}_${callInfo['subStatus']}';
    _pendingRemarkCalls.removeWhere((c) => c['pendingKey'] == key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_call_remarks', jsonEncode(_pendingRemarkCalls));
    if (mounted) setState(() {});
  }

  Future<void> _loadPendingRemarkCalls() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pending_call_remarks');
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw);
      if (list is List) {
        _pendingRemarkCalls
          ..clear()
          ..addAll(list.map((e) => Map<String, dynamic>.from(e)));
      }
      if (mounted && _pendingRemarkCalls.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 500), _showPendingRemarksSheet);
      }
    } catch (_) {}
  }

  void _showPendingRemarksSheet() {
    if (!mounted || _pendingRemarkCalls.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (ctx, controller) => Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 14),
              Text('Pending Call Remarks', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: _textColor)),
              Text('${_pendingRemarkCalls.length} calls need comments/follow-up', style: GoogleFonts.poppins(fontSize: 12, color: _lightTextColor)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: _pendingRemarkCalls.length,
                  itemBuilder: (_, i) {
                    final c = _pendingRemarkCalls[i];
                    return Card(
                      elevation: 0,
                      color: const Color(0xFFF8FAFC),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: _primaryColor.withOpacity(0.12), child: Icon(Icons.notes_rounded, color: _primaryColor)),
                        title: Text(c['leadName']?.toString() ?? 'Customer', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        subtitle: Text('${c['subStatus']} • ${c['duration']} • ${c['phone']}', style: GoogleFonts.poppins(fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _showCallRemarksDialog(c);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTodayFollowupsPopup() {
    if (!mounted) return;
    final today = DateTime.now();
    final due = _leads.where((lead) {
      final raw = lead['nextdate']?.toString();
      if (raw == null || raw.isEmpty) return false;
      try {
        final d = DateTime.parse(raw).toLocal();
        return d.year == today.year && d.month == today.month && d.day == today.day;
      } catch (_) {
        return false;
      }
    }).toList();

    if (due.isEmpty) return;
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Today Follow-ups', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: _primaryColor)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: due.take(6).map((l) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(backgroundColor: _primaryColor.withOpacity(0.12), child: Icon(Icons.notifications_active_rounded, color: _primaryColor)),
                title: Text(l['c_name']?.toString() ?? 'Customer', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                subtitle: Text(l['c_phone']?.toString() ?? '', style: GoogleFonts.poppins(fontSize: 12)),
                trailing: IconButton(
                  icon: Icon(Icons.call_rounded, color: _primaryColor),
                  onPressed: () {
                    Navigator.pop(context);
                    _makePhoneCall(l['c_phone']?.toString() ?? '', l['leadid']?.toString() ?? '');
                  },
                ),
              )).toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Close', style: GoogleFonts.poppins(color: _lightTextColor))),
          ],
        ),
      );
    });
  }

  // ─── Date / time helpers ─────────────────────────────────────────────────
  String _formatDate(String? s) {
    if (s == null) return 'No date';
    try { return DateFormat('dd MMM yyyy').format(DateTime.parse(s)); }
    catch (_) { return s; }
  }

  String _formatDateDisplay(String? s) {
    if (s == null || s.isEmpty) return 'Not specified';
    try { return DateFormat('dd-MM-yyyy').format(DateTime.parse(s).toLocal()); }
    catch (_) { return s; }
  }

  String _formatTimeFromDateTime(String? s) {
    if (s == null || s.isEmpty) return 'Not specified';
    try { return DateFormat('hh:mm a').format(DateTime.parse(s).toLocal()); }
    catch (_) { return s; }
  }

  String _getDaysRemaining(String? nextDate) {
    if (nextDate == null) return 'No date';
    try {
      final diff = DateTime.parse(nextDate).difference(DateTime.now()).inDays;
      if (diff < 0) return '${-diff}d overdue';
      if (diff == 0) return 'Today';
      if (diff == 1) return 'Tomorrow';
      return '$diff days';
    } catch (_) { return 'Invalid date'; }
  }

  Color _getDaysRemainingColor(String? nextDate) {
    if (nextDate == null) return Colors.grey;
    try {
      final diff = DateTime.parse(nextDate).difference(DateTime.now()).inDays;
      if (diff < 0) return const Color(0xFFE53935);
      if (diff == 0) return const Color(0xFFFFA000);
      if (diff <= 3) return const Color(0xFF1E88E5);
      return const Color(0xFF43A047);
    } catch (_) { return Colors.grey; }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? _secondaryColor : _primaryColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
  }

  // ─── Logout ───────────────────────────────────────────────────────────────
  Future<void> _performLogout() async {
    if (!mounted) return;
    Navigator.pop(context);
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => LoginScreen()),
        (_) => false,
      );
    } catch (e) {
      if (mounted) { _showSnackBar('Logout failed', isError: true); setState(() => _isLoading = false); }
    }
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text('Logout', style: GoogleFonts.poppins()),
        content: Text('Are you sure you want to logout?', style: GoogleFonts.poppins()),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CANCEL', style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          TextButton(
            onPressed: _performLogout,
            child: Text('LOGOUT', style: GoogleFonts.poppins(color: _secondaryColor)),
          ),
        ],
      ),
    );
  }

  // ─── Action dialogs ───────────────────────────────────────────────────────
  void _showActionDialog(Map<String, dynamic> lead) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 32, offset: const Offset(0, 8))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Lead Actions', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: _primaryColor)),
              const SizedBox(height: 4),
              Text(lead['c_name']?.toString() ?? 'No Name',
                  style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade700), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.3,
                children: [
                  _buildActionTile(icon: Icons.update_rounded, color: _primaryColor, title: 'Follow Up', onTap: () => _showFollowUpDialog(lead)),
                  _buildActionTile(icon: Icons.verified_rounded, color: Colors.green, title: 'Ready for Sale', onTap: () => _showReadyForSaleDialog(lead)),
                  _buildActionTile(icon: Icons.calendar_month_rounded, color: Colors.blue, title: 'Meeting', onTap: () => _showMeetingDialog(lead)),
                  _buildActionTile(icon: Icons.block_rounded, color: Colors.red, title: 'Disqualify', onTap: () => _showDisqualifyConfirmation(lead)),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.grey.shade600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color color,
    required String title,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () { Navigator.pop(context); onTap(); },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(height: 8),
              Text(title, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w500, color: color), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  // Follow Up dialog
  void _showFollowUpDialog(Map<String, dynamic> lead) {
    DateTime selDate = DateTime.now();
    TimeOfDay selTime = TimeOfDay.now();
    final remarksCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: LayoutBuilder(builder: (ctx, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                  child: StatefulBuilder(builder: (ctx2, setS) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Schedule Follow Up', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: _primaryColor)),
                        const SizedBox(height: 14),
                        _buildDateTimeField(
                          icon: Icons.calendar_month_rounded, label: 'Date',
                          value: DateFormat('EEE, MMM d, y').format(selDate),
                          onTap: () async {
                            final p = await showDatePicker(context: ctx2, initialDate: selDate,
                                firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                            if (p != null) setS(() => selDate = p);
                          },
                        ),
                        const SizedBox(height: 10),
                        _buildDateTimeField(
                          icon: Icons.access_time_rounded, label: 'Time',
                          value: selTime.format(ctx2),
                          onTap: () async {
                            final p = await showTimePicker(context: ctx2, initialTime: selTime);
                            if (p != null) setS(() => selTime = p);
                          },
                        ),
                        const SizedBox(height: 14),
                        Text('Remarks', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey.shade700)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: remarksCtrl,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'Enter follow-up notes...',
                            hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _primaryColor, width: 1.5)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          style: GoogleFonts.poppins(fontSize: 13),
                        ),
                        const SizedBox(height: 20),
                        Row(children: [
                          Expanded(child: TextButton(
                            onPressed: () => Navigator.pop(ctx2),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey.shade600,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: Text('Cancel', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: ElevatedButton(
                            onPressed: () async {
                              Navigator.pop(ctx2);
                              try {
                                setState(() => _isLoading = true);
                                final r = await http.post(
                                  Uri.parse('$_baseUrl$_followUpEndpoint'),
                                  headers: {'Content-Type': 'application/json'},
                                  body: jsonEncode({
                                    'leadId': lead['leadid'],
                                    'userId': widget.userId,
                                    'cCode': widget.cCode,
                                    'followupDate': DateFormat('yyyy-MM-dd').format(selDate),
                                    'followupTime': '${selTime.hour}:${selTime.minute}:00',
                                    'remarks': remarksCtrl.text,
                                    'username': widget.username,
                                  }),
                                ).timeout(_apiTimeout);
                                final d = jsonDecode(r.body);
                                if (d['success'] == true) {
                                  _showSnackBar('Follow-up scheduled successfully');
                                  _fetchLeads();
                                } else {
                                  _showSnackBar(d['message'] ?? 'Failed', isError: true);
                                }
                              } catch (e) {
                                _showSnackBar('Failed to schedule follow-up', isError: true);
                              } finally {
                                if (mounted) setState(() => _isLoading = false);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryColor, foregroundColor: Colors.white,
                              elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text('Schedule', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                          )),
                        ]),
                      ],
                    );
                  }),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDateTimeField({required IconData icon, required String label, required String value, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(icon, size: 22, color: _primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade600)),
              const SizedBox(height: 2),
              Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey.shade400),
        ]),
      ),
    );
  }

  // Meeting dialog
  void _showMeetingDialog(Map<String, dynamic> lead) {
    DateTime selDate = DateTime.now();
    TimeOfDay selTime = TimeOfDay.now();
    final remarksCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: LayoutBuilder(builder: (ctx, _) {
          return SingleChildScrollView(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: StatefulBuilder(builder: (ctx2, setS) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Schedule Meeting', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.blue)),
                    const SizedBox(height: 14),
                    _buildDateTimeField(
                      icon: Icons.calendar_month_rounded, label: 'Date',
                      value: DateFormat('EEE, MMM d, y').format(selDate),
                      onTap: () async {
                        final p = await showDatePicker(context: ctx2, initialDate: selDate,
                            firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                        if (p != null) setS(() => selDate = p);
                      },
                    ),
                    const SizedBox(height: 10),
                    _buildDateTimeField(
                      icon: Icons.access_time_rounded, label: 'Time',
                      value: selTime.format(ctx2),
                      onTap: () async {
                        final p = await showTimePicker(context: ctx2, initialTime: selTime);
                        if (p != null) setS(() => selTime = p);
                      },
                    ),
                    const SizedBox(height: 14),
                    Text('Meeting Notes', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey.shade700)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: remarksCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Enter meeting agenda...',
                        hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.blue, width: 1.5)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      style: GoogleFonts.poppins(fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(child: TextButton(
                        onPressed: () => Navigator.pop(ctx2),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade600,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text('Cancel', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(ctx2);
                          try {
                            setState(() => _isLoading = true);
                            final r = await http.post(
                              Uri.parse('$_baseUrl$_meetingEndpoint'),
                              headers: {'Content-Type': 'application/json'},
                              body: jsonEncode({
                                'leadId': lead['leadid'],
                                'userId': widget.userId,
                                'cCode': widget.cCode,
                                'meetingDate': DateFormat('yyyy-MM-dd').format(selDate),
                                'meetingTime': '${selTime.hour}:${selTime.minute}:00',
                                'remarks': remarksCtrl.text,
                                'username': widget.username,
                              }),
                            ).timeout(_apiTimeout);
                            final d = jsonDecode(r.body);
                            if (d['success'] == true) {
                              _showSnackBar('Meeting scheduled successfully');
                              _fetchLeads();
                            } else {
                              _showSnackBar(d['message'] ?? 'Failed', isError: true);
                            }
                          } catch (e) {
                            _showSnackBar('Failed to schedule meeting', isError: true);
                          } finally {
                            if (mounted) setState(() => _isLoading = false);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue, foregroundColor: Colors.white,
                          elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('Schedule', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                      )),
                    ]),
                  ],
                );
              }),
            ),
          );
        }),
      ),
    );
  }

  // Disqualify dialog
  void _showDisqualifyConfirmation(Map<String, dynamic> lead) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.warning_amber_rounded, size: 32, color: Colors.red)),
              const SizedBox(height: 12),
              Text('Disqualify Lead?', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.red)),
              const SizedBox(height: 6),
              Text('Are you sure you want to disqualify ${lead['c_name']}?',
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600), textAlign: TextAlign.center),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Reason for disqualification',
                  labelStyle: GoogleFonts.poppins(fontSize: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                style: GoogleFonts.poppins(fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: Text('Cancel', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  onPressed: () async {
                    if (ctrl.text.isEmpty) { _showSnackBar('Please enter a reason', isError: true); return; }
                    Navigator.pop(context);
                    await _disqualifyLead(lead, ctrl.text);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red, foregroundColor: Colors.white,
                    elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Disqualify', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _disqualifyLead(Map<String, dynamic> lead, String reason) async {
    try {
      setState(() => _isLoading = true);
      final r = await http.post(Uri.parse('$_baseUrl$_disqualifyEndpoint'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'leadId': lead['leadid'], 'cCode': widget.cCode, 'reason': reason}))
          .timeout(_apiTimeout);
      final d = jsonDecode(r.body);
      if (d['success'] == true) { _showSnackBar('Lead disqualified successfully'); _fetchLeads(); }
      else _showSnackBar(d['message'] ?? 'Failed', isError: true);
    } catch (e) {
      _showSnackBar('Failed to disqualify lead', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Ready for Sale dialog
  void _showReadyForSaleDialog(Map<String, dynamic> lead) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.check_circle_outline, size: 32, color: Colors.green)),
                const SizedBox(height: 12),
                Text('Ready for Sale', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.green)),
                const SizedBox(height: 6),
                Text('Add any comments about why this lead is ready', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600), textAlign: TextAlign.center),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Comments (optional)',
                    labelStyle: GoogleFonts.poppins(fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                    child: Text('Cancel', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _markAsReadyForSale(lead, ctrl.text);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green, foregroundColor: Colors.white,
                      elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Confirm', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                  )),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _markAsReadyForSale(Map<String, dynamic> lead, String comment) async {
    try {
      setState(() => _isLoading = true);
      final r = await http.post(Uri.parse('$_baseUrl$_readyForSaleEndpoint'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'leadId': lead['leadid'], 'cCode': widget.cCode, 'comment': comment}))
          .timeout(_apiTimeout);
      final d = jsonDecode(r.body);
      if (d['success'] == true) { _showSnackBar('Lead marked as Ready for Sale'); _fetchLeads(); }
      else _showSnackBar(d['message'] ?? 'Failed', isError: true);
    } catch (e) {
      _showSnackBar('Failed to update lead status', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildCurrentTab()),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildCurrentTab() {
    switch (_selectedNavIndex) {
      case 1:
        return Column(
          children: [
            _buildStatsCard(),
            Expanded(child: _buildLeadList()),
          ],
        );
      case 2:
        return _buildFollowupsTab();
      case 3:
        return _buildPendingRemarksTab();
      default:
        return _buildCrmHomeTab();
    }
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 18, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: _selectedNavIndex,
          onTap: (i) {
            if (i == 4) { _switchToWebView(); return; }
            setState(() => _selectedNavIndex = i);
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: _primaryColor,
          unselectedItemColor: _lightTextColor,
          selectedLabelStyle: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700),
          unselectedLabelStyle: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w500),
          items: [
            const BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Home'),
            const BottomNavigationBarItem(icon: Icon(Icons.people_alt_rounded), label: 'Leads'),
            BottomNavigationBarItem(
              icon: _navBadge(Icons.event_available_rounded, _todayFollowupsCount),
              label: 'Follow-up',
            ),
            BottomNavigationBarItem(
              icon: _navBadge(Icons.rate_review_rounded, _pendingRemarkCalls.length),
              label: 'Remarks',
            ),
            const BottomNavigationBarItem(icon: Icon(Icons.language_rounded), label: 'Portal'),
          ],
        ),
      ),
    );
  }

  Widget _navBadge(IconData icon, int count) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (count > 0)
          Positioned(
            right: -8,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: const Color(0xFFE53935), borderRadius: BorderRadius.circular(9)),
              child: Text(count > 99 ? '99+' : '$count', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }


  int get _todayFollowupsCount => _todayFollowups.length;
  int get _overdueFollowupsCount => _leads.where((l) {
    final raw = l['nextdate']?.toString();
    if (raw == null || raw.isEmpty) return false;
    try {
      final d = DateTime.parse(raw).toLocal();
      final today = DateTime.now();
      return DateTime(d.year, d.month, d.day).isBefore(DateTime(today.year, today.month, today.day));
    } catch (_) { return false; }
  }).length;

  int get _newLeadsCount => _leads.where(_isNewLead).length;
  int get _readyForSaleCount => _leads.where((l) => (l['status']?.toString().toLowerCase() ?? '') == 'ready for sale').length;

  List<Map<String, dynamic>> get _todayFollowups {
    final today = DateTime.now();
    return _leads.where((lead) {
      final raw = lead['nextdate']?.toString();
      if (raw == null || raw.isEmpty) return false;
      try {
        final d = DateTime.parse(raw).toLocal();
        return d.year == today.year && d.month == today.month && d.day == today.day;
      } catch (_) { return false; }
    }).toList();
  }

  List<Map<String, dynamic>> get _overdueFollowups {
    final today = DateTime.now();
    return _leads.where((lead) {
      final raw = lead['nextdate']?.toString();
      if (raw == null || raw.isEmpty) return false;
      try {
        final d = DateTime.parse(raw).toLocal();
        return DateTime(d.year, d.month, d.day).isBefore(DateTime(today.year, today.month, today.day));
      } catch (_) { return false; }
    }).toList();
  }

  Widget _buildCrmHomeTab() {
    if (_isLoading) return Center(child: CircularProgressIndicator(color: _primaryColor));
    final priorityLeads = <Map<String, dynamic>>[
      ..._todayFollowups,
      ..._overdueFollowups,
      ..._filteredLeads.where(_isNewLead),
    ];
    final seen = <String>{};
    final uniquePriority = priorityLeads.where((l) => seen.add(l['leadid']?.toString() ?? l.hashCode.toString())).take(6).toList();

    return RefreshIndicator(
      onRefresh: _fetchLeads,
      color: _primaryColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          _buildHeroPerformanceCard(),
          const SizedBox(height: 14),
          _buildQuickMetricsGrid(),
          const SizedBox(height: 16),
          _buildSectionHeader('Priority Work', 'Today follow-ups, overdue, and new leads'),
          const SizedBox(height: 10),
          if (uniquePriority.isEmpty)
            _buildSoftEmptyCard('No priority work', 'You are all caught up for now.', Icons.check_circle_rounded, Colors.green)
          else
            ...uniquePriority.map((lead) => _buildMiniLeadTile(lead)).toList(),
          const SizedBox(height: 16),
          _buildSectionHeader('CRM Shortcuts', 'Fast actions for daily work'),
          const SizedBox(height: 10),
          _buildShortcutGrid(),
        ],
      ),
    );
  }

  Widget _buildHeroPerformanceCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: _headerGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: _primaryColor.withOpacity(0.25), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: Stack(
        children: [
          Positioned(right: -18, top: -18, child: Container(width: 90, height: 90, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.06)))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.auto_graph_rounded, color: Colors.white)),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Sales CRM Overview', style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12)), child: Text(DateFormat('dd MMM').format(DateTime.now()), style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: _heroStat('Total', _leads.length.toString())),
                  Expanded(child: _heroStat('Today', _todayFollowupsCount.toString())),
                  Expanded(child: _heroStat('Pending', _pendingRemarkCalls.length.toString())),
                ],
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: .08, end: 0);
  }

  Widget _heroStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: GoogleFonts.poppins(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
        Text(label, style: GoogleFonts.poppins(color: Colors.white.withOpacity(.72), fontSize: 11, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildQuickMetricsGrid() {
    final cards = [
      _metricData('Today Follow-ups', _todayFollowupsCount, Icons.event_available_rounded, const Color(0xFF049881), () => setState(() => _selectedNavIndex = 2)),
      _metricData('Overdue', _overdueFollowupsCount, Icons.warning_rounded, const Color(0xFFE53935), () { setState(() { _selectedNavIndex = 1; _currentFilter = 'Due'; _applyFilters(); }); }),
      _metricData('New Leads', _newLeadsCount, Icons.fiber_new_rounded, const Color(0xFF2196F3), () { setState(() { _selectedNavIndex = 1; _currentFilter = 'New'; _applyFilters(); }); }),
      _metricData('Pending Remarks', _pendingRemarkCalls.length, Icons.rate_review_rounded, const Color(0xFFFF9800), () => setState(() => _selectedNavIndex = 3)),
      _metricData('Ready Sale', _readyForSaleCount, Icons.verified_rounded, const Color(0xFF009688), () { setState(() { _selectedNavIndex = 1; _currentFilter = 'Ready for sale'; _applyFilters(); }); }),
      _metricData('Tasks', _notificationCount, Icons.notifications_rounded, const Color(0xFF7C4DFF), _navigateToTasks),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.82),
      itemBuilder: (_, i) => _buildMetricCard(cards[i]),
    );
  }

  Map<String, dynamic> _metricData(String title, int value, IconData icon, Color color, VoidCallback onTap) => {'title': title, 'value': value, 'icon': icon, 'color': color, 'onTap': onTap};

  Widget _buildMetricCard(Map<String, dynamic> item) {
    final color = item['color'] as Color;
    return GestureDetector(
      onTap: item['onTap'] as VoidCallback,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: color.withOpacity(.12)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 12, offset: const Offset(0, 4))]),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(.11), borderRadius: BorderRadius.circular(14)), child: Icon(item['icon'] as IconData, color: color, size: 22)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${item['value']}', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w900, color: _textColor)),
              Text(item['title'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w600, color: _lightTextColor)),
            ])),
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.25,
      children: [
        _shortcutTile('All Leads', Icons.people_alt_rounded, _primaryColor, () => setState(() => _selectedNavIndex = 1)),
        _shortcutTile('Tasks', Icons.task_alt_rounded, const Color(0xFF7C4DFF), _navigateToTasks),
        _shortcutTile('Pending Notes', Icons.notes_rounded, const Color(0xFFFF9800), _showPendingRemarksSheet),
        _shortcutTile('Web Portal', Icons.language_rounded, const Color(0xFF0E637A), _switchToWebView),
      ],
    );
  }

  Widget _shortcutTile(String title, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: color.withOpacity(.09),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [Icon(icon, color: color), const SizedBox(width: 10), Expanded(child: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 12, color: color)))]),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Row(
      children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800, color: _textColor)),
          Text(subtitle, style: GoogleFonts.poppins(fontSize: 11, color: _lightTextColor)),
        ])),
      ],
    );
  }

  Widget _buildMiniLeadTile(Map<String, dynamic> lead) {
    final status = lead['status']?.toString() ?? 'Lead';
    final color = _statusColors[status] ?? _primaryColor;
    final phone = lead['c_phone']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: color.withOpacity(.12), child: Text((lead['c_name']?.toString().isNotEmpty == true ? lead['c_name'].toString()[0] : 'C').toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.bold))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(lead['c_name']?.toString() ?? 'Customer', maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w800, color: _textColor)),
            const SizedBox(height: 2),
            Text('$status • ${_getDaysRemaining(lead['nextdate']?.toString())}', style: GoogleFonts.poppins(fontSize: 11, color: _lightTextColor)),
          ])),
          IconButton(onPressed: () => _showCustomerTimeline(lead), icon: Icon(Icons.timeline_rounded, color: color)),
          IconButton(onPressed: () => _makePhoneCall(phone, lead['leadid']?.toString() ?? ''), icon: Icon(Icons.call_rounded, color: _primaryColor)),
        ],
      ),
    );
  }

  Widget _buildSoftEmptyCard(String title, String subtitle, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: color.withOpacity(.12))),
      child: Row(children: [Icon(icon, color: color), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w800, color: _textColor)), Text(subtitle, style: GoogleFonts.poppins(fontSize: 12, color: _lightTextColor))]))]),
    );
  }

  Widget _buildFollowupsTab() {
    final items = [..._todayFollowups, ..._overdueFollowups];
    final seen = <String>{};
    final unique = items.where((l) => seen.add(l['leadid']?.toString() ?? l.hashCode.toString())).toList();
    if (_isLoading) return Center(child: CircularProgressIndicator(color: _primaryColor));
    if (unique.isEmpty) return Padding(padding: const EdgeInsets.all(16), child: _buildSoftEmptyCard('No follow-ups due', 'Today and overdue follow-ups will show here.', Icons.event_available_rounded, Colors.green));
    return RefreshIndicator(
      onRefresh: _fetchLeads,
      color: _primaryColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          _buildSectionHeader('Follow-up Center', 'Today and overdue customer follow-ups'),
          const SizedBox(height: 10),
          ...unique.map(_buildFollowupTile),
        ],
      ),
    );
  }

  Widget _buildFollowupTile(Map<String, dynamic> lead) {
    final dueColor = _getDaysRemainingColor(lead['nextdate']?.toString());
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border(left: BorderSide(color: dueColor, width: 4)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: dueColor.withOpacity(.1), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.event_note_rounded, color: dueColor)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(lead['c_name']?.toString() ?? 'Customer', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w800, color: _textColor)),
          Text('${lead['c_phone'] ?? ''}', style: GoogleFonts.poppins(fontSize: 11.5, color: _lightTextColor)),
          const SizedBox(height: 4),
          Text('${_formatDate(lead['nextdate']?.toString())} • ${_getDaysRemaining(lead['nextdate']?.toString())}', style: GoogleFonts.poppins(fontSize: 11.5, color: dueColor, fontWeight: FontWeight.w700)),
        ])),
        IconButton(onPressed: () => _showFollowUpDialog(lead), icon: Icon(Icons.edit_calendar_rounded, color: dueColor)),
        IconButton(onPressed: () => _makePhoneCall(lead['c_phone']?.toString() ?? '', lead['leadid']?.toString() ?? ''), icon: Icon(Icons.call_rounded, color: _primaryColor)),
      ]),
    );
  }

  Widget _buildPendingRemarksTab() {
    if (_pendingRemarkCalls.isEmpty) return Padding(padding: const EdgeInsets.all(16), child: _buildSoftEmptyCard('No pending remarks', 'Calls without notes will appear here.', Icons.check_circle_rounded, Colors.green));
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        _buildSectionHeader('Pending Remarks', 'Complete call notes and next follow-up'),
        const SizedBox(height: 10),
        ..._pendingRemarkCalls.map((c) => _buildPendingRemarkTile(c)),
      ],
    );
  }

  Widget _buildPendingRemarkTile(Map<String, dynamic> c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: const Color(0xFFFF9800).withOpacity(.12), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.rate_review_rounded, color: Color(0xFFFF9800))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c['leadName']?.toString() ?? 'Customer', style: GoogleFonts.poppins(fontWeight: FontWeight.w800, color: _textColor)),
          Text('${c['subStatus']} • ${c['duration']} • ${c['phone']}', style: GoogleFonts.poppins(fontSize: 11.5, color: _lightTextColor)),
        ])),
        ElevatedButton(onPressed: () => _showCallRemarksDialog(c), style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text('Add', style: GoogleFonts.poppins(fontWeight: FontWeight.w700))),
      ]),
    );
  }

  void _showCustomerTimeline(Map<String, dynamic> lead) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: .62,
        minChildSize: .42,
        maxChildSize: .9,
        builder: (ctx, controller) => Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 14),
            Row(children: [
              CircleAvatar(backgroundColor: _primaryColor.withOpacity(.12), child: Icon(Icons.person_rounded, color: _primaryColor)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(lead['c_name']?.toString() ?? 'Customer', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w800, color: _textColor)), Text(lead['c_phone']?.toString() ?? '', style: GoogleFonts.poppins(fontSize: 12, color: _lightTextColor))])),
              IconButton(onPressed: () => _makePhoneCall(lead['c_phone']?.toString() ?? '', lead['leadid']?.toString() ?? ''), icon: Icon(Icons.call_rounded, color: _primaryColor)),
            ]),
            const SizedBox(height: 16),
            Text('Customer Timeline', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w800, color: _textColor)),
            const SizedBox(height: 10),
            Expanded(child: ListView(controller: controller, children: _timelineItemsForLead(lead).map((e) => _timelineTile(e['icon'] as IconData, e['title'] as String, e['subtitle'] as String, e['color'] as Color)).toList())),
          ]),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _timelineItemsForLead(Map<String, dynamic> lead) {
    final items = <Map<String, dynamic>>[];
    items.add({'icon': Icons.person_add_alt_1_rounded, 'title': 'Lead assigned', 'subtitle': _formatDate(lead['assign_date']?.toString()), 'color': const Color(0xFF2196F3)});
    if (lead['last_call_date'] != null) items.add({'icon': Icons.phone_in_talk_rounded, 'title': 'Last call', 'subtitle': '${_formatDateDisplay(lead['last_call_date']?.toString())} • ${lead['last_call_duration'] ?? 'N/A'}', 'color': _primaryColor});
    if (lead['last_followup_date'] != null) items.add({'icon': Icons.event_available_rounded, 'title': 'Follow-up added', 'subtitle': '${_formatDate(lead['last_followup_date']?.toString())} • ${lead['last_followup_remarks'] ?? ''}', 'color': const Color(0xFF673AB7)});
    if (lead['last_meeting_date'] != null) items.add({'icon': Icons.groups_rounded, 'title': 'Meeting scheduled', 'subtitle': '${_formatDate(lead['last_meeting_date']?.toString())} • ${lead['last_meeting_remarks'] ?? ''}', 'color': const Color(0xFF795548)});
    if (lead['status'] != null) items.add({'icon': Icons.flag_rounded, 'title': 'Current status', 'subtitle': lead['status'].toString(), 'color': _statusColors[lead['status']?.toString()] ?? _primaryColor});
    return items;
  }

  Widget _timelineTile(IconData icon, String title, String subtitle, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: color.withOpacity(.12), shape: BoxShape.circle), child: Icon(icon, color: color, size: 18)), Container(width: 2, height: 28, color: color.withOpacity(.16))]),
        const SizedBox(width: 12),
        Expanded(child: Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w800, color: _textColor, fontSize: 13)), const SizedBox(height: 3), Text(subtitle, style: GoogleFonts.poppins(color: _lightTextColor, fontSize: 11.5))]))),
      ]),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _headerGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(color: const Color(0xFF049881).withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 8)),
          BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Stack(
        children: [
          // Decorative circle top-right
          Positioned(
            top: -30, right: -20,
            child: Container(
              width: 120, height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
              ),
            ),
          ),
          Positioned(
            top: 20, right: 60,
            child: Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.04),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              children: [
                Row(
                  children: [
                    // Avatar / brand icon
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.25), width: 1),
                      ),
                      child: const Icon(Icons.dashboard_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SmartCRM',
                            style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                          Text('Dashboard',
                            style: GoogleFonts.poppins(color: Colors.white.withOpacity(0.7), fontSize: 11)),
                        ],
                      ),
                    ),
                    _buildHeaderButton(
                      icon: Icons.open_in_browser_rounded,
                      label: 'Portal',
                      onTap: _switchToWebView,
                    ),
                    const SizedBox(width: 4),
                    // Notification bell
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.notifications_rounded, color: Colors.white, size: 22),
                            onPressed: _navigateToTasks,
                            padding: const EdgeInsets.all(8),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        if (_notificationCount > 0)
                          Positioned(
                            right: 2, top: 2,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF4757),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                              child: Text(
                                _notificationCount > 99 ? '99+' : _notificationCount.toString(),
                                style: GoogleFonts.poppins(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 2),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: IconButton(
                        icon: const Icon(LineIcons.alternateSignOut, color: Colors.white, size: 20),
                        onPressed: _showLogoutConfirmation,
                        padding: const EdgeInsets.all(8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildSiteDropdown(),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.08, end: 0);
  }

Widget _buildHeaderButton({
  required IconData icon,
  required String label,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 8,
      ),
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFF59E0B),
            Color(0xFFEF7C00),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withOpacity(0.35),
            blurRadius: 16,
            spreadRadius: 1,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: Colors.white,
            size: 14,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: GoogleFonts.dmSans(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    ),
  );
}
  // ─── Site dropdown ────────────────────────────────────────────────────────
  Widget _buildSiteDropdown() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.25), width: 1),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedSite,
          isExpanded: true,
          isDense: true,
          dropdownColor: const Color(0xFF026D5E),
          icon: _isFetchingSites
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70),
          hint: Row(children: [
            const Icon(Icons.location_on_rounded, size: 14, color: Colors.white70),
            const SizedBox(width: 6),
            Text('All Sites', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
          ]),
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
          items: [
            DropdownMenuItem<String>(
              value: null,
              child: Row(children: [
                const Icon(Icons.public_rounded, size: 14, color: Colors.white70),
                const SizedBox(width: 6),
                Text('All Sites', style: GoogleFonts.poppins(fontSize: 13, color: Colors.white)),
              ]),
            ),
            ..._sites.map((s) {
              final name = s['site_name']?.toString() ?? 'Unknown';
              return DropdownMenuItem<String>(
                value: name,
                child: Text(name, style: GoogleFonts.poppins(fontSize: 13, color: Colors.white), overflow: TextOverflow.ellipsis),
              );
            }),
          ],
          onChanged: (v) { setState(() { _selectedSite = v; _filterLeadsBySite(v); }); },
        ),
      ),
    );
  }

  // ─── Stats / filters ──────────────────────────────────────────────────────
  Widget _buildStatsCard() {
    final total = _filteredLeads.length;
    final newC = _filteredLeads.where(_isNewLead).length;
    final dueC = _filteredLeads.where(_isDueLead).length;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: Column(
        children: [
          // Stats row
          Row(
            children: [
              _buildStatItem('Total Leads', total.toString(), Icons.people_alt_rounded,
                color: const Color(0xFF049881), isActive: _currentFilter == 'All', onTap: () => _filterLeads('All')),
              const SizedBox(width: 10),
              _buildStatItem('New', newC.toString(), Icons.fiber_new_rounded,
                color: const Color(0xFF2196F3), isActive: _currentFilter == 'New', onTap: () => _filterLeads('New')),
              const SizedBox(width: 10),
              _buildStatItem('Overdue', dueC.toString(), Icons.warning_amber_rounded,
                color: const Color(0xFFE53935), isActive: _currentFilter == 'Due', onTap: () => _filterLeads('Due')),
            ],
          ),
          const SizedBox(height: 12),
          // Filter chips
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _filterChip('All'),
                _filterChip('New lead'),
                _filterChip('Meeting'),
                _filterChip('Follow up'),
                _filterChip('Pending'),
                _filterChip('Ready for sale'),
                _filterChip('Disqualified'),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 80.ms);
  }

  Widget _buildStatItem(String title, String value, IconData icon,
      {Color color = const Color(0xFF049881), bool isActive = false, VoidCallback? onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: isActive ? color : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: isActive ? color.withOpacity(0.3) : Colors.black.withOpacity(0.05),
                blurRadius: isActive ? 12 : 6,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(
              color: isActive ? color : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isActive ? Colors.white.withOpacity(0.2) : color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: isActive ? Colors.white : color, size: 18),
              ),
              const SizedBox(height: 8),
              Text(value,
                style: GoogleFonts.poppins(
                  fontSize: 20, fontWeight: FontWeight.w800,
                  color: isActive ? Colors.white : _textColor,
                )),
              const SizedBox(height: 2),
              Text(title,
                style: GoogleFonts.poppins(
                  fontSize: 10, fontWeight: FontWeight.w500,
                  color: isActive ? Colors.white.withOpacity(0.85) : _lightTextColor,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label) {
    final active = _currentFilter == label;
    final chipColors = {
      'All': const Color(0xFF049881),
      'New lead': const Color(0xFF2196F3),
      'Meeting': const Color(0xFF7C4DFF),
      'Follow up': const Color(0xFF673AB7),
      'Pending': const Color(0xFFFF9800),
      'Ready for sale': const Color(0xFF009688),
      'Disqualified': const Color(0xFFFC0000),
    };
    final c = chipColors[label] ?? _primaryColor;
    return GestureDetector(
      onTap: () => _filterLeads(label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? c : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? c : Colors.grey.shade200, width: 1.5),
          boxShadow: active ? [BoxShadow(color: c.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))] : [],
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: active ? Colors.white : _lightTextColor,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ─── Lead list ────────────────────────────────────────────────────────────
  Widget _buildLeadList() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: _primaryColor));
    }
    if (_filteredLeads.isEmpty) return _buildEmptyState();

    return RefreshIndicator(
      onRefresh: _fetchLeads,
      color: _primaryColor,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
        itemCount: _filteredLeads.length,
        itemBuilder: (_, i) => _buildLeadCard(_filteredLeads[i], i),
      ),
    );
  }

  // ─── Lead card ────────────────────────────────────────────────────────────
  Widget _buildLeadCard(Map<String, dynamic> lead, int index) {
    final isExpanded = index == _expandedLeadIndex;
    final status = lead['status']?.toString() ?? '';
    final statusColor = _statusColors[status] ?? _primaryColor;
    final daysRemaining = _getDaysRemaining(lead['nextdate']?.toString());
    final daysColor = _getDaysRemainingColor(lead['nextdate']?.toString());
    final isNew = _isNewLead(lead);
    final isDue = _isDueLead(lead);
    final showAction = status != 'Closed' && status != 'Disqualified';

    // Card background based on state
    Color bg = Colors.white;
    Color leftBorderColor = statusColor;
    if (isNew) { bg = const Color(0xFFF0F9FF); leftBorderColor = const Color(0xFF2196F3); }
    else if (isDue) { bg = const Color(0xFFFFF5F5); leftBorderColor = const Color(0xFFE53935); }

    final initials = (lead['c_name']?.toString() ?? 'N')
        .split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: leftBorderColor, width: 4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _expandedLeadIndex = isExpanded ? null : index),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Avatar circle
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [statusColor.withOpacity(0.8), statusColor],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Center(
                        child: Text(initials,
                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  lead['c_name']?.toString() ?? 'No Name',
                                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: _textColor),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 5),
                              if (isNew) _badge('NEW', const Color(0xFF2196F3)),
                              if (isDue && !isNew) _badge('DUE', const Color(0xFFE53935)),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: statusColor.withOpacity(0.25)),
                                ),
                                child: Text(status,
                                  style: GoogleFonts.poppins(fontSize: 10, color: statusColor, fontWeight: FontWeight.w600)),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.schedule_rounded, size: 12, color: daysColor),
                                  const SizedBox(width: 3),
                                  Text(daysRemaining,
                                    style: GoogleFonts.poppins(fontSize: 11, color: daysColor, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Call button — prominent green
                    GestureDetector(
                      onTap: () => _makePhoneCall(lead['c_phone']?.toString() ?? '', lead['leadid']?.toString() ?? ''),
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF049881), Color(0xFF026D5E)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(color: const Color(0xFF049881).withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 3)),
                          ],
                        ),
                        child: const Icon(Icons.call_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),

              // ── Expanded details ────────────────────────────────────────
              if (isExpanded) ...[
                const Divider(height: 16),
                _detailRow(LineIcons.phone, 'Phone', lead['c_phone']?.toString() ?? 'Not specified',
                    isPhone: true, phoneNumber: lead['c_phone']?.toString(), leadId: lead['leadid']?.toString()),
                _detailRow(LineIcons.calendar, 'Assigned Date', _formatDate(lead['assign_date']?.toString())),
                _detailRow(LineIcons.clock, 'Next Action',
                    '${_formatDate(lead['nextdate']?.toString())} ($daysRemaining)', valueColor: daysColor),
                if (lead['last_call_date'] != null)
                  _detailRow(LineIcons.phoneVolume, 'Last Call',
                      '${_formatDateDisplay(lead['last_call_date']?.toString())} (${lead['last_call_duration']?.toString() ?? 'N/A'})'),
                if (status == 'Meeting' && lead['last_meeting_date'] != null) ...[
                  _detailRow(LineIcons.calendarCheck, 'Meeting Date', _formatDate(lead['last_meeting_date']?.toString())),
                  _detailRow(LineIcons.clock, 'Meeting Time', _formatTimeFromDateTime(lead['last_meeting_date']?.toString())),
                  if (lead['last_meeting_remarks'] != null)
                    _detailRow(LineIcons.comment, 'Meeting Notes', lead['last_meeting_remarks']?.toString() ?? ''),
                ],
                if (status == 'Follow up' && lead['last_followup_date'] != null) ...[
                  _detailRow(LineIcons.clock, 'Follow-up Date', _formatDate(lead['last_followup_date']?.toString())),
                  _detailRow(LineIcons.clock, 'Follow-up Time', _formatTimeFromDateTime(lead['last_followup_date']?.toString())),
                  if (lead['last_followup_remarks'] != null)
                    _detailRow(LineIcons.comment, 'Follow-up Notes', lead['last_followup_remarks']?.toString() ?? ''),
                ],
                if ((status == 'Ready for sale' || status == 'Disqualified') && lead['reason'] != null)
                  _detailRow(
                    status == 'Ready for sale' ? LineIcons.checkCircle : LineIcons.timesCircle,
                    status == 'Ready for sale' ? 'Ready Reason' : 'Disqualify Reason',
                    lead['reason']?.toString() ?? '',
                    valueColor: status == 'Ready for sale' ? Colors.green : Colors.red,
                  ),
                if (lead['site_name'] != null)
                  _detailRow(LineIcons.mapMarker, 'Site', lead['site_name']?.toString() ?? ''),
                if (showAction) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF049881), Color(0xFF026D5E)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: [BoxShadow(color: const Color(0xFF049881).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))],
                    ),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.bolt_rounded, size: 18),
                      label: Text('Take Action', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                      onPressed: () => _showActionDialog(lead),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: GoogleFonts.poppins(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
    );
  }

  Widget _detailRow(IconData icon, String label, String value,
      {bool isPhone = false, String? phoneNumber, String? leadId, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: _lightTextColor.withOpacity(0.7)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.poppins(fontSize: 11, color: _lightTextColor)),
                const SizedBox(height: 1),
                if (isPhone && phoneNumber != null)
                  GestureDetector(
                    onTap: () => _makePhoneCall(phoneNumber, leadId ?? ''),
                    child: Text(value, style: GoogleFonts.poppins(fontSize: 13, color: _primaryColor, fontWeight: FontWeight.w500)),
                  )
                else
                  Text(value, style: GoogleFonts.poppins(fontSize: 13, color: valueColor ?? _textColor, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Empty state ──────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    final site = _selectedSite != null && _selectedSite!.isNotEmpty;
    final filterLabel = _currentFilter == 'All' ? '' : '$_currentFilter ';
    final title = site ? 'No ${filterLabel}leads for $_selectedSite' : 'No ${filterLabel}leads';
    final sub = site
        ? 'There are no ${filterLabel}leads for this site'
        : _currentFilter == 'All'
            ? "You don't have any leads assigned"
            : 'There are no $_currentFilter leads';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LineIcons.user, size: 56, color: _lightTextColor.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(title, style: GoogleFonts.poppins(fontSize: 16, color: _lightTextColor, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(sub, style: GoogleFonts.poppins(fontSize: 13, color: _lightTextColor.withOpacity(0.7)), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _fetchLeads,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text('Refresh', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
