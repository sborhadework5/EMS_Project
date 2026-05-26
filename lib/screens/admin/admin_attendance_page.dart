import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AdminAttendancePage extends StatefulWidget {
  const AdminAttendancePage({super.key});

  @override
  State<AdminAttendancePage> createState() => _AdminAttendancePageState();
}

class _AdminAttendancePageState extends State<AdminAttendancePage> {
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "Attendance Reports",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo[800],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('role', isEqualTo: 'employee')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final users = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['full_name'] ?? '').toString().toLowerCase();
                  final id = (data['emp_id'] ?? '').toString().toLowerCase();
                  return name.contains(_searchQuery) || id.contains(_searchQuery);
                }).toList();

                if (users.isEmpty) {
                  return const Center(child: Text("No employees found."));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final data = users[index].data() as Map<String, dynamic>;
                    final uid = users[index].id;
                    return _buildEmployeeCard(data, uid);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.indigo[800],
      child: TextField(
        onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: "Search by name or ID...",
          hintStyle: const TextStyle(color: Colors.white60),
          prefixIcon: const Icon(Icons.search, color: Colors.white60),
          filled: true,
          fillColor: Colors.white.withOpacity(0.1),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeCard(Map<String, dynamic> data, String uid) {
    final String name = data['full_name'] ?? 'Unknown';
    final String empId = data['emp_id'] ?? '-';
    final String dept = data['department'] ?? '-';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
      color: Colors.white,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Colors.indigo[100],
          child: Text(
            name[0].toUpperCase(),
            style: TextStyle(
              color: Colors.indigo[800],
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          "ID: $empId  •  $dept",
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: ElevatedButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AdminEmployeeTimeCardPage(
                uid: uid,
                employeeName: name,
              ),
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo[800],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            textStyle: const TextStyle(fontSize: 13),
          ),
          child: const Text("View"),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Per-employee timecard viewed by admin
// ─────────────────────────────────────────────

class AdminEmployeeTimeCardPage extends StatefulWidget {
  final String uid;
  final String employeeName;

  const AdminEmployeeTimeCardPage({
    super.key,
    required this.uid,
    required this.employeeName,
  });

  @override
  State<AdminEmployeeTimeCardPage> createState() =>
      _AdminEmployeeTimeCardPageState();
}

class _AdminEmployeeTimeCardPageState
    extends State<AdminEmployeeTimeCardPage> {
  // Default: current full month
  late DateTime _startDate;
  late DateTime _endDate;

  bool _isLoading = false;
  List<Map<String, dynamic>> _timeCards = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);          // 1st of month
    _endDate = DateTime(now.year, now.month + 1, 0);        // last day of month
    _fetchTimeCards();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: Colors.indigo[800]!,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchTimeCards();
    }
  }

  // Navigate month by month
  void _changeMonth(int delta) {
    setState(() {
      final newMonth = DateTime(_startDate.year, _startDate.month + delta, 1);
      _startDate = newMonth;
      _endDate = DateTime(newMonth.year, newMonth.month + 1, 0);
    });
    _fetchTimeCards();
  }

  Future<void> _fetchTimeCards() async {
    setState(() => _isLoading = true);

    try {
      final query = await FirebaseFirestore.instance
          .collection('attendance')
          .where('uid', isEqualTo: widget.uid)
          .orderBy('timestamp', descending: false)
          .get();

      debugPrint("Admin fetch — docs: ${query.docs.length} for ${widget.employeeName}");

      final Map<String, List<Map<String, dynamic>>> grouped = {};

      for (final doc in query.docs) {
        final data = doc.data();
        final String? displayTimeStr = data['display_time'] as String?;
        final Timestamp? ts = data['timestamp'] as Timestamp?;

        DateTime? displayTime;
        if (displayTimeStr != null && displayTimeStr.isNotEmpty) {
          try {
            displayTime = DateFormat('yyyy-MM-dd HH:mm:ss')
                .parse(displayTimeStr, true)
                .toLocal();
          } catch (_) {
            displayTime = ts?.toDate();
          }
        } else {
          displayTime = ts?.toDate();
        }

        if (displayTime == null) continue;

        // Filter within selected date range
        final dateOnly = DateTime(
            displayTime.year, displayTime.month, displayTime.day);
        final startOnly =
            DateTime(_startDate.year, _startDate.month, _startDate.day);
        final endOnly =
            DateTime(_endDate.year, _endDate.month, _endDate.day);

        if (dateOnly.isBefore(startOnly) || dateOnly.isAfter(endOnly)) continue;

        final dateKey = DateFormat('yyyy-MM-dd').format(displayTime);
        grouped.putIfAbsent(dateKey, () => []);
        grouped[dateKey]!.add({...data, '_displayTime': displayTime});
      }

      final List<Map<String, dynamic>> cards = [];
      final int totalDays = _endDate.difference(_startDate).inDays + 1;

      for (int i = 0; i < totalDays; i++) {
        final day = _startDate.add(Duration(days: i));
        final key = DateFormat('yyyy-MM-dd').format(day);
        final records = grouped[key] ?? [];

        records.sort((a, b) {
          return (a['_displayTime'] as DateTime)
              .compareTo(b['_displayTime'] as DateTime);
        });

        DateTime? punchIn;
        DateTime? punchOut;

        for (final r in records) {
          if (r['type'] == 'in' && punchIn == null) {
            punchIn = r['_displayTime'] as DateTime;
          }
          if (r['type'] == 'out') {
            punchOut = r['_displayTime'] as DateTime;
          }
        }

        Duration? duration;
        if (punchIn != null && punchOut != null) {
          duration = punchOut.difference(punchIn);
          if (duration.isNegative) duration = null;
        }

        cards.add({
          'date': day,
          'punchIn': punchIn,
          'punchOut': punchOut,
          'duration': duration,
          'allRecords': records,
        });
      }

      if (mounted) {
        setState(() {
          _timeCards = cards.reversed.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Admin TimeCard error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _computeSummary() {
    int presentDays = 0;
    int absentDays = 0;
    Duration totalWorked = Duration.zero;

    for (final card in _timeCards) {
      final date = card['date'] as DateTime;
      final isWeekend = date.weekday == DateTime.saturday ||
          date.weekday == DateTime.sunday;
      final isFuture = date.isAfter(DateTime.now());

      if (card['punchIn'] != null) {
        presentDays++;
        if (card['duration'] != null) {
          totalWorked += card['duration'] as Duration;
        }
      } else if (!isWeekend && !isFuture) {
        absentDays++;
      }
    }

    return {
      'present': presentDays,
      'absent': absentDays,
      'totalWorked': totalWorked,
    };
  }

  @override
  Widget build(BuildContext context) {
    final summary = _computeSummary();
    final fmt = DateFormat('MMM yyyy');
    final bool isFullMonth = _startDate.day == 1 &&
        _endDate.day == DateTime(_endDate.year, _endDate.month + 1, 0).day;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.employeeName,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Text(
              "Time Card",
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: Colors.indigo[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: "Pick custom range",
            onPressed: _pickDateRange,
          ),
        ],
      ),
      body: Column(
        children: [
          // Month navigator header
          Container(
            color: Colors.indigo[800],
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: Colors.white),
                  onPressed: () => _changeMonth(-1),
                  tooltip: "Previous month",
                ),
                GestureDetector(
                  onTap: _pickDateRange,
                  child: Column(
                    children: [
                      Text(
                        isFullMonth
                            ? fmt.format(_startDate)
                            : "${DateFormat('dd MMM').format(_startDate)} → ${DateFormat('dd MMM yyyy').format(_endDate)}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isFullMonth)
                        const Text(
                          "Tap range icon to pick custom dates",
                          style: TextStyle(
                              color: Colors.white60, fontSize: 11),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: Colors.white),
                  // Disable next if already on current month
                  onPressed: DateTime(_startDate.year, _startDate.month)
                          .isBefore(
                              DateTime(DateTime.now().year, DateTime.now().month))
                      ? () => _changeMonth(1)
                      : null,
                  tooltip: "Next month",
                ),
              ],
            ),
          ),

          // Summary chips
          _buildSummaryRow(summary),

          // Cards list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _timeCards.every((c) => (c['allRecords'] as List).isEmpty)
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _timeCards.length,
                        itemBuilder: (context, index) =>
                            _buildTimeCardTile(_timeCards[index]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(Map<String, dynamic> summary) {
    final Duration worked = summary['totalWorked'] as Duration;
    final int h = worked.inHours;
    final int m = worked.inMinutes.remainder(60);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          _summaryChip("${summary['present']}", "Present",
              Colors.green[700]!, Colors.green[50]!),
          const SizedBox(width: 10),
          _summaryChip("${summary['absent']}", "Absent",
              Colors.red[700]!, Colors.red[50]!),
          const SizedBox(width: 10),
          _summaryChip("${h}h ${m}m", "Total worked",
              Colors.indigo[800]!, Colors.indigo[50]!),
        ],
      ),
    );
  }

  Widget _summaryChip(
      String value, String label, Color textColor, Color bgColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: textColor)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 11, color: textColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeCardTile(Map<String, dynamic> card) {
    final DateTime date = card['date'] as DateTime;
    final DateTime? punchIn = card['punchIn'] as DateTime?;
    final DateTime? punchOut = card['punchOut'] as DateTime?;
    final Duration? duration = card['duration'] as Duration?;
    final List allRecords = card['allRecords'] as List;

    final bool isToday = DateFormat('yyyy-MM-dd').format(date) ==
        DateFormat('yyyy-MM-dd').format(DateTime.now());
    final bool isWeekend = date.weekday == DateTime.saturday ||
        date.weekday == DateTime.sunday;
    final bool isFuture = date.isAfter(DateTime.now());

    String status;
    Color statusColor;
    Color statusBg;

    if (isFuture) {
      status = "Upcoming";
      statusColor = Colors.grey[600]!;
      statusBg = Colors.grey[100]!;
    } else if (isWeekend) {
      status = "Weekend";
      statusColor = Colors.blueGrey[600]!;
      statusBg = Colors.blueGrey[50]!;
    } else if (punchIn != null && punchOut != null) {
      status = "Complete";
      statusColor = Colors.green[700]!;
      statusBg = Colors.green[50]!;
    } else if (punchIn != null) {
      status = isToday ? "In progress" : "No punch out";
      statusColor = Colors.orange[700]!;
      statusBg = Colors.orange[50]!;
    } else {
      status = "Absent";
      statusColor = Colors.red[700]!;
      statusBg = Colors.red[50]!;
    }

    final timeFmt = DateFormat('hh:mm a');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
      color: Colors.white,
      child: ExpansionTile(
        tilePadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateFormat('dd').format(date),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isToday ? Colors.indigo[800] : Colors.black87,
              ),
            ),
            Text(
              DateFormat('EEE').format(date).toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                color: isToday ? Colors.indigo[600] : Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            if (isToday) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.indigo[800],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  "Today",
                  style: TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
        subtitle: allRecords.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    _timeChip(
                      Icons.login,
                      punchIn != null ? timeFmt.format(punchIn) : "--:--",
                      Colors.green[700]!,
                    ),
                    const SizedBox(width: 10),
                    _timeChip(
                      Icons.logout,
                      punchOut != null ? timeFmt.format(punchOut) : "--:--",
                      Colors.red[700]!,
                    ),
                    const Spacer(),
                    if (duration != null)
                      Text(
                        "${duration.inHours}h ${duration.inMinutes.remainder(60)}m",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo[800],
                        ),
                      ),
                  ],
                ),
              ),
        // Expanded punch log
        children: allRecords.isEmpty
            ? [
                Text(
                  isWeekend
                      ? "Weekend — no records expected."
                      : isFuture
                          ? "Not yet."
                          : "No punch records for this day.",
                  style:
                      TextStyle(color: Colors.grey[500], fontSize: 13),
                )
              ]
            : [
                const Divider(height: 1),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "All punches",
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 6),
                ...allRecords.map((r) {
                  final bool isIn = r['type'] == 'in';
                  final DateTime dt = r['_displayTime'] as DateTime;
                  final double? lat =
                      (r['latitude'] as num?)?.toDouble();
                  final double? lng =
                      (r['longitude'] as num?)?.toDouble();
                  final bool hasLocation = lat != null &&
                      lng != null &&
                      !(lat == 0.0 && lng == 0.0);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isIn ? Icons.login : Icons.logout,
                          size: 16,
                          color: isIn
                              ? Colors.green[700]
                              : Colors.red[700],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isIn ? "Punch In" : "Punch Out",
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                              if (hasLocation)
                                Text(
                                  "${lat!.toStringAsFixed(4)}, ${lng!.toStringAsFixed(4)}",
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[500]),
                                ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              timeFmt.format(dt),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                            Text(
                              DateFormat('dd MMM').format(dt),
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
      ),
    );
  }

  Widget _timeChip(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            "No records for this period",
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            "${widget.employeeName} has no attendance data here.",
            style: TextStyle(color: Colors.grey[400]),
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: _pickDateRange,
            icon: const Icon(Icons.date_range),
            label: const Text("Pick a different range"),
          ),
        ],
      ),
    );
  }
}