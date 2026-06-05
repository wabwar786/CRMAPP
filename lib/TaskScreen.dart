import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:line_icons/line_icons.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class TaskScreen extends StatefulWidget {
  final String userId;
  final String username;

  const TaskScreen({super.key, required this.userId, required this.username});

  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  // Design system
  final Color _primaryColor = const Color(0xFF049881);
  final Color _secondaryColor = const Color(0xFF8B0000);
  final Color _accentColor = const Color(0xFF81C784);
  final Color _backgroundColor = const Color(0xFFF0F4F8);
  final Color _cardColor = const Color.fromARGB(255, 255, 255, 255);
  final Color _textColor = const Color(0xFF333333);
  final Color _lightTextColor = const Color(0xFF757575);
  final Color _highlightColor = const Color(0xFFE3F2FD);

  final List<Color> _headerGradient = [
    const Color(0xFF049881),
    const Color(0xFF028174),
  ];

  final Map<String, Color> _statusColors = {
    'New': Colors.blue,
    'Pending': Colors.orange,
    'Completed': Colors.green,
  };

  static const String _baseUrl = 'https://smartcrmbackend-production-56c0.up.railway.app';

  // State variables
  List<Map<String, dynamic>> _tasks = [];
  bool _isLoading = false;
  String _currentFilter = 'All';
  int? _expandedTaskIndex;

  @override
  void initState() {
    super.initState();
    _fetchTasks();
  }

  Future<void> _fetchTasks() async {
    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/tasks'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': widget.userId}),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to load tasks');
      }

      final data = jsonDecode(response.body);
      if (data['success'] != true) {
        throw Exception(data['message'] ?? 'Failed to load tasks');
      }

      setState(() {
        _tasks = List<Map<String, dynamic>>.from(data['tasks']);
      });
    } catch (e) {
      _showSnackBar('Failed to load tasks: ${e.toString()}', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateTaskStatus(String taskId, String status) async {
    final TextEditingController notesController = TextEditingController();
    final bool isPending = status == 'Pending';
    final Color statusColor = isPending ? Colors.orange : Colors.green;

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 40,
                  spreadRadius: 0,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with icon
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isPending ? Icons.pending_actions : Icons.task_alt,
                        color: statusColor,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        isPending ? 'Mark as Pending' : 'Mark as Completed',
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: _textColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Subtitle
                Text(
                  isPending
                      ? 'Please provide the reason for pending status'
                      : 'Add completion notes (optional)',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: _lightTextColor,
                  ),
                ),
                const SizedBox(height: 16),

                // Text field
                TextField(
                  controller: notesController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: isPending
                        ? 'e.g. Waiting for client response...'
                        : 'e.g. Completed all requirements...',
                    hintStyle: GoogleFonts.poppins(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: statusColor, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                  ),
                  maxLines: 4,
                  minLines: 3,
                  style: GoogleFonts.poppins(fontSize: 15),
                ),
                const SizedBox(height: 28),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: Colors.grey.shade300,
                              width: 1.5,
                            ),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          if (isPending && notesController.text.isEmpty) {
                            _showSnackBar(
                              'Please provide a reason for pending status',
                            );
                            return;
                          }

                          Navigator.pop(context);
                          await _submitTaskUpdate(
                            taskId,
                            status,
                            notesController.text,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: statusColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                          shadowColor: Colors.transparent,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(width: 8),
                            Text(
                              isPending ? ' Pending' : 'Complete ',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submitTaskUpdate(
    String taskId,
    String status,
    String notes,
  ) async {
    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/update-task'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'taskId': taskId,
          'userId': widget.userId,
          'status': status,
          'notes':
              notes, // This is only used for the history log, not for updating task notes
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to update task status: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      if (data['success'] != true) {
        throw Exception(data['message'] ?? 'Failed to update task status');
      }

      _showSnackBar('Task status updated successfully');
      await _fetchTasks(); // Refresh the task list
    } catch (e) {
      _showSnackBar(
        'Failed to update task status: ${e.toString()}',
        isError: true,
      );
      debugPrint('Error updating task status: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _filterTasks(String status) {
    setState(() {
      _currentFilter = status;
    });
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'No date';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('dd MMM yyyy').format(date);
    } catch (e) {
      return dateString;
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? _secondaryColor : _primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

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
        ],
      ),
      child: Stack(
        children: [
          Positioned(top: -30, right: -20,
            child: Container(width: 120, height: 120,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.05)))),
          Positioned(top: 30, right: 70,
            child: Container(width: 50, height: 50,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.04)))),
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 20, left: 16, right: 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 18),
                        onPressed: () => Navigator.pop(context),
                        padding: const EdgeInsets.all(8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('My Tasks',
                            style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                          Text('Manage your assignments',
                            style: GoogleFonts.poppins(color: Colors.white.withOpacity(0.7), fontSize: 11)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.task_alt_rounded, color: Colors.white, size: 14),
                          const SizedBox(width: 5),
                          Text('${_tasks.length}',
                            style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildFilterChips(),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          const SizedBox(width: 12), // Add left padding
          _buildFilterChip('All', _currentFilter == 'All'),
          const SizedBox(width: 12),
          _buildFilterChip('New', _currentFilter == 'New'),
          const SizedBox(width: 12),
          _buildFilterChip('Pending', _currentFilter == 'Pending'),
          const SizedBox(width: 12),
          _buildFilterChip('Completed', _currentFilter == 'Completed'),
          const SizedBox(width: 12), // Add right padding
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected) {
    return GestureDetector(
      onTap: () => _filterTasks(label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _primaryColor : Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? _primaryColor : Colors.white.withOpacity(0.4),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _primaryColor.withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 0,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.8),
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    final totalCount = _tasks.length;
    final newCount = _tasks.where((task) => task['status'] == 'New').length;
    final pendingCount = _tasks.where((task) => task['status'] == 'Pending').length;
    final completedCount = _tasks.where((task) => task['status'] == 'Completed').length;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: Row(
        children: [
          _buildStatItem('Total', totalCount.toString(), Icons.assignment_rounded, const Color(0xFF049881)),
          const SizedBox(width: 10),
          _buildStatItem('New', newCount.toString(), Icons.fiber_new_rounded, const Color(0xFF2196F3)),
          const SizedBox(width: 10),
          _buildStatItem('Pending', pendingCount.toString(), Icons.pending_actions_rounded, const Color(0xFFFF9800)),
          const SizedBox(width: 10),
          _buildStatItem('Done', completedCount.toString(), Icons.check_circle_rounded, const Color(0xFF4CAF50)),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildStatItem(String title, String value, IconData icon, Color color) {
    final isActive = _currentFilter == title || (_currentFilter == 'All' && title == 'Total');
    return Expanded(
      child: GestureDetector(
        onTap: () => _filterTasks(title == 'Total' ? 'All' : title),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? color : Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: isActive ? color.withOpacity(0.3) : Colors.black.withOpacity(0.05),
                blurRadius: isActive ? 10 : 5,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(icon, color: isActive ? Colors.white : color, size: 20),
              const SizedBox(height: 6),
              Text(value,
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800,
                  color: isActive ? Colors.white : const Color(0xFF1A2332))),
              Text(title,
                style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w500,
                  color: isActive ? Colors.white.withOpacity(0.85) : const Color(0xFF6B7A8D)),
                textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskItem(Map<String, dynamic> task, int index) {
    final isExpanded = index == _expandedTaskIndex;
    final status = task['status']?.toString() ?? 'New';
    final statusColor = _statusColors[status] ?? _primaryColor;
    final isCompleted = status == 'Completed';

    final borderColors = {
      'New': const Color(0xFF2196F3),
      'Pending': const Color(0xFFFF9800),
      'Completed': const Color(0xFF4CAF50),
    };
    final leftColor = borderColors[status] ?? _primaryColor;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 5, 14, 8),
      decoration: BoxDecoration(
        color: isCompleted ? const Color(0xFFF1FFF6) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: leftColor, width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _expandedTaskIndex = isExpanded ? null : index),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Status icon circle
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: leftColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: leftColor.withOpacity(0.2)),
                      ),
                      child: Icon(
                        isCompleted ? Icons.check_circle_rounded :
                          status == 'Pending' ? Icons.pending_actions_rounded : Icons.assignment_rounded,
                        color: leftColor, size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(task['title']?.toString() ?? 'No Title',
                                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14,
                                    color: isCompleted ? const Color(0xFF6B7A8D) : const Color(0xFF1A2332),
                                    decoration: isCompleted ? TextDecoration.lineThrough : null),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                              if (status == 'New')
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2196F3).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text('NEW',
                                    style: GoogleFonts.poppins(fontSize: 9, color: const Color(0xFF2196F3), fontWeight: FontWeight.w800)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Row(
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
                              const SizedBox(width: 8),
                              Icon(Icons.calendar_today_rounded, size: 12, color: _lightTextColor),
                              const SizedBox(width: 4),
                              Text(_formatDate(task['due_date']?.toString()),
                                style: GoogleFonts.poppins(fontSize: 11, color: _lightTextColor, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!isCompleted)
                      GestureDetector(
                        onTap: () => _updateTaskStatus(task['task_id'].toString(), 'Completed'),
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF049881), Color(0xFF026D5E)],
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(color: const Color(0xFF049881).withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 2))],
                          ),
                          child: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                  ],
                ),
              if (isExpanded) ...[
                const Divider(height: 20),
                _buildDetailRow(
                  LineIcons.infoCircle,
                  'Description',
                  task['notes']?.toString() ?? 'No description provided',
                ),
                _buildDetailRow(
                  LineIcons.calendar,
                  'Due Date',
                  _formatDate(task['due_date']?.toString()),
                ),
                if (task['status'] == 'Pending' ||
                    task['status'] == 'Completed')
                  _buildDetailRow(
                    LineIcons.comment,
                    'Status Notes',
                    task['status_notes']?.toString() ?? 'No notes provided',
                  ),
                if (!isCompleted) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      // Always show the Pending button if task is not completed
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.pending_actions_rounded, size: 16),
                          label: Text('Pending', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                          onPressed: () => _updateTaskStatus(task['task_id'].toString(), 'Pending'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            side: const BorderSide(color: Colors.orange, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF049881), Color(0xFF026D5E)],
                              begin: Alignment.centerLeft, end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: Text('Complete', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                            onPressed: () => _updateTaskStatus(task['task_id'].toString(), 'Completed'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: _lightTextColor.withOpacity(0.7)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: _lightTextColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: _textColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LineIcons.tasks,
                size: 60,
                color: _lightTextColor.withOpacity(0.3),
              ),
              const SizedBox(height: 20),
              Text(
                'No tasks assigned',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  color: _lightTextColor,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'You currently don\'t have any tasks assigned to you',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: _lightTextColor.withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _fetchTasks,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  'Refresh',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredTasks = _currentFilter == 'All'
        ? _tasks
        : _tasks.where((task) => task['status'] == _currentFilter).toList();

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildStatsCard(),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: _primaryColor),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchTasks,
                      color: _primaryColor,
                      child: filteredTasks.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 20),
                              itemCount: filteredTasks.length,
                              itemBuilder: (context, index) =>
                                  _buildTaskItem(filteredTasks[index], index),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
