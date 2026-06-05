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

  // ─── Call tracking ────────────────────────────────────────────────────────
  static const _callChannel = MethodChannel('com.your.app/call_tracker');
  String? _currentCallLeadId;
  String? _currentCallPhoneNumber;
  Timer? _callCheckTimer;
  DateTime? _callStartTime;
  final Set<String> _loggedCallIds = {};

  // ─── Design tokens ────────────────────────────────────────────────────────
  final Color _primaryColor = const Color(0xFF049881);
  final Color _secondaryColor = const Color(0xFF8B0000);
  final Color _backgroundColor = const Color(0xFFF8F9FA);
  final Color _cardColor = Colors.white;
  final Color _textColor = const Color(0xFF333333);
  final Color _lightTextColor = const Color(0xFF757575);
  final List<Color> _headerGradient = [
    const Color(0xFF049881),
    const Color(0xFF028174),
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
      _fetchLeads();
    });
  }

  @override
  void dispose() {
    _callCheckTimer?.cancel();
    _notificationTimer?.cancel();
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
      if (newLogs.isNotEmpty) _showSnackBar('Call logged successfully');
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

  // [CHANGED] Smart status based on duration + ring time + call type
  String _determineCallStatus(int durationSeconds, int callType) {
    // callType: 1=Incoming, 2=Outgoing, 3=Missed, 5=Rejected/Busy
    
    // Missed call (OS detected)
    if (callType == 3) return 'Not Answered';
    
    // Rejected / Busy (customer cut the call)
    if (callType == 5) return 'Busy';

    // Outgoing call
    if (callType == 2) {
      if (durationSeconds == 0) {
        // Call placed but 0 duration — not connected at all
        return 'Not Connected';
      }
      if (durationSeconds <= 3) {
        // Very quick end — customer rejected / busy
        return 'Busy';
      }
      if (durationSeconds <= 25) {
        // Short call — rang but customer disconnected quickly
        return 'Not Answered';
      }
      if (durationSeconds <= 120) {
        // Brief conversation
        return 'Connected';
      }
      if (durationSeconds <= 300) {
        return 'Verified';
      }
      return 'Quality';
    }

    // Incoming call
    if (callType == 1) {
      if (durationSeconds == 0) return 'Missed';
      if (durationSeconds <= 120) return 'Connected';
      return 'Quality';
    }

    // Fallback
    if (durationSeconds == 0) return 'Not Connected';
    if (durationSeconds <= 25) return 'Not Answered';
    if (durationSeconds <= 120) return 'Connected';
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
            _buildStatsCard(),
            Expanded(child: _buildLeadList()),
          ],
        ),
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: _headerGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          // [CHANGED] Responsive header row — no overflow on small screens
          Row(
            children: [
              Expanded(
                child: Text(
                  'Dashboard',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // [CHANGED] Web View button
              _buildHeaderButton(
                icon: Icons.open_in_browser_rounded,
                label: 'Portal',
                onTap: _switchToWebView,
              ),
              // Notification bell
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined, color: Colors.white, size: 26),
                    onPressed: _navigateToTasks,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  if (_notificationCount > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          _notificationCount > 99 ? '99+' : _notificationCount.toString(),
                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              IconButton(
                icon: const Icon(LineIcons.alternateSignOut, color: Colors.white, size: 24),
                onPressed: _showLogoutConfirmation,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildSiteDropdown(),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.05, end: 0);
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
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedSite,
          isExpanded: true,
          isDense: true,
          icon: _isFetchingSites
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.arrow_drop_down),
          hint: Text('All Sites', style: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 13)),
          style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF333333)),
          items: [
            DropdownMenuItem<String>(
              value: null,
              child: Text('All Sites', style: GoogleFonts.poppins(fontSize: 13)),
            ),
            ..._sites.map((s) {
              final name = s['site_name']?.toString() ?? 'Unknown';
              return DropdownMenuItem<String>(
                value: name,
                child: Text(name, style: GoogleFonts.poppins(fontSize: 13), overflow: TextOverflow.ellipsis),
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
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          // Stat items row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('Total', total.toString(), LineIcons.users, isActive: _currentFilter == 'All', onTap: () => _filterLeads('All')),
              _buildStatItem('New', newC.toString(), LineIcons.star, isActive: _currentFilter == 'New', onTap: () => _filterLeads('New')),
              _buildStatItem('Due', dueC.toString(), LineIcons.clock, isActive: _currentFilter == 'Due', onTap: () => _filterLeads('Due')),
            ],
          ),
          const SizedBox(height: 10),
          // Filter chips — horizontal scroll, no overflow
          SizedBox(
            height: 34,
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
      {bool isActive = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isActive ? _primaryColor : _primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: isActive ? Colors.white : _primaryColor, size: 18),
          ),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: isActive ? _primaryColor : _textColor)),
          Text(title, style: GoogleFonts.poppins(fontSize: 11, color: isActive ? _primaryColor : _lightTextColor)),
        ],
      ),
    );
  }

  Widget _filterChip(String label) {
    final active = _currentFilter == label;
    return GestureDetector(
      onTap: () => _filterLeads(label),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _primaryColor : _primaryColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? _primaryColor : _primaryColor.withOpacity(0.2)),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(fontSize: 11, color: active ? Colors.white : _primaryColor, fontWeight: FontWeight.w500),
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
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
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

    Color bg = _cardColor;
    if (isNew) bg = const Color(0xFFE3F2FD);
    else if (isDue) bg = const Color(0xFFFFEBEE);

    return Card(
      color: bg,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _expandedLeadIndex = isExpanded ? null : index),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            children: [
              // ── Card header row ─────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Name + badges + status
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                lead['c_name']?.toString() ?? 'No Name',
                                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            if (isNew) _badge('NEW', _primaryColor),
                            if (isDue && !isNew) _badge('DUE', Colors.red),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Status + days — wrapped so no overflow on small screen
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: statusColor.withOpacity(0.3)),
                              ),
                              child: Text(status, style: GoogleFonts.poppins(fontSize: 11, color: statusColor, fontWeight: FontWeight.w500)),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LineIcons.calendar, size: 12, color: daysColor),
                                const SizedBox(width: 3),
                                Text(daysRemaining, style: GoogleFonts.poppins(fontSize: 11, color: daysColor, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Call button
                  GestureDetector(
                    onTap: () => _makePhoneCall(lead['c_phone']?.toString() ?? '', lead['leadid']?.toString() ?? ''),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: _primaryColor.withOpacity(0.1), shape: BoxShape.circle),
                      child: Icon(LineIcons.phone, color: _primaryColor, size: 22),
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
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      label: Text('Take Action', style: GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 13)),
                      onPressed: () => _showActionDialog(lead),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 1,
                      ),
                    ),
                  ),
                ],
              ],
            ],
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
