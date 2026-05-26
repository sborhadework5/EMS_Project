import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class TimeCardPage extends StatefulWidget {
  const TimeCardPage({super.key});

  @override
  State<TimeCardPage> createState() => _TimeCardPageState();
}

class _TimeCardPageState extends State<TimeCardPage> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 6));
  DateTime _endDate = DateTime.now();
  bool _isLoading = false;

  // Holds processed daily summaries: { 'date': DateTime, 'punchIn': DateTime?, 'punchOut': DateTime?, 'duration': Duration? }
  List<Map<String, dynamic>> _timeCards = [];

  @override
  void initState() {
    super.initState();
    _fetchTimeCards();
  }

  Future<void> _pickDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.indigo[800]!,
              onPrimary: Colors.white,
              surface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchTimeCards();
    }
  }

  Future<void> _fetchTimeCards() async {
    setState(() => _isLoading = true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Only filter by uid — no timestamp filter in Firestore query
      // This avoids the composite index requirement and UTC offset issues
      final query = await FirebaseFirestore.instance
          .collection('attendance')
          .where('uid', isEqualTo: uid)
          .orderBy('timestamp', descending: false)
          .get();

      debugPrint("Total attendance docs fetched: ${query.docs.length}");

      // Group by date parsed from display_time string
      final Map<String, List<Map<String, dynamic>>> grouped = {};

      for (final doc in query.docs) {
        final data = doc.data();
        final String? displayTimeStr = data['display_time'] as String?;
        final Timestamp? ts = data['timestamp'] as Timestamp?;

        DateTime? displayTime;

        // Try parsing display_time first ("2026-05-17 20:53:23")
        if (displayTimeStr != null && displayTimeStr.isNotEmpty) {
          try {
            displayTime = DateFormat('yyyy-MM-dd HH:mm:ss')
                .parse(displayTimeStr, true)
                .toLocal();
          } catch (e) {
            debugPrint("Failed to parse display_time: $displayTimeStr — $e");
            displayTime = ts?.toDate();
          }
        } else {
          displayTime = ts?.toDate();
        }

        if (displayTime == null) continue;

        // Only include records within selected date range
        final dateOnly =
            DateTime(displayTime.year, displayTime.month, displayTime.day);
        final startOnly =
            DateTime(_startDate.year, _startDate.month, _startDate.day);
        final endOnly = DateTime(_endDate.year, _endDate.month, _endDate.day);

        if (dateOnly.isBefore(startOnly) || dateOnly.isAfter(endOnly)) continue;

        final dateKey = DateFormat('yyyy-MM-dd').format(displayTime);
        grouped.putIfAbsent(dateKey, () => []);
        grouped[dateKey]!.add({
          ...data,
          '_displayTime': displayTime,
        });

        debugPrint(
            "Grouped $dateKey — type: ${data['type']} — time: $displayTime");
      }

      // Build one card per day in selected range
      final List<Map<String, dynamic>> cards = [];
      final int totalDays = _endDate.difference(_startDate).inDays + 1;

      for (int i = 0; i < totalDays; i++) {
        final day = _startDate.add(Duration(days: i));
        final key = DateFormat('yyyy-MM-dd').format(day);
        final records = grouped[key] ?? [];

        // Sort within day by display_time ascending
        records.sort((a, b) {
          final aTime = a['_displayTime'] as DateTime;
          final bTime = b['_displayTime'] as DateTime;
          return aTime.compareTo(bTime);
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

      debugPrint(
          "Time cards built: ${cards.length}, days with data: ${grouped.keys.length}");
    } catch (e) {
      debugPrint("TimeCard fetch error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Summary totals across selected range
  Map<String, dynamic> _computeSummary() {
    int presentDays = 0;
    int absentDays = 0;
    Duration totalWorked = Duration.zero;

    for (final card in _timeCards) {
      final date = card['date'] as DateTime;
      // Skip future dates and weekends from absent count
      final isWeekend =
          date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
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

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "Time Card",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo[800],
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: _pickDateRange,
            icon: const Icon(Icons.date_range, color: Colors.white, size: 18),
            label: const Text("Range", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Date range header
          _buildDateRangeHeader(),

          // Summary row
          _buildSummaryRow(summary),

          // Time card list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _timeCards.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _timeCards.length,
                        itemBuilder: (context, index) {
                          return _buildTimeCardTile(_timeCards[index]);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRangeHeader() {
    final fmt = DateFormat('dd MMM yyyy');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.indigo[800],
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.calendar_today, color: Colors.white70, size: 14),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _pickDateRange,
            child: Text(
              "${fmt.format(_startDate)}  →  ${fmt.format(_endDate)}",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          _summaryChip(
            "${summary['present']}",
            "Present",
            Colors.green[700]!,
            Colors.green[50]!,
          ),
          const SizedBox(width: 10),
          _summaryChip(
            "${summary['absent']}",
            "Absent",
            Colors.red[700]!,
            Colors.red[50]!,
          ),
          const SizedBox(width: 10),
          _summaryChip(
            "${h}h ${m}m",
            "Total worked",
            Colors.indigo[800]!,
            Colors.indigo[50]!,
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(
    String value,
    String label,
    Color textColor,
    Color bgColor,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: textColor)),
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
    final bool isWeekend =
        date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    final bool isFuture = date.isAfter(DateTime.now());

    // Status
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
    } else if (punchIn != null && punchOut == null) {
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
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
              DateFormat('MMM').format(date).toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                color: isToday ? Colors.indigo[600] : Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            Text(
              DateFormat('EEEE').format(date),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            if (isToday) ...[
              const SizedBox(width: 8),
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
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              // Punch in time
              _timeChip(
                Icons.login,
                punchIn != null ? timeFmt.format(punchIn) : "--:--",
                Colors.green[700]!,
              ),
              const SizedBox(width: 8),
              // Punch out time
              _timeChip(
                Icons.logout,
                punchOut != null ? timeFmt.format(punchOut) : "--:--",
                Colors.red[700]!,
              ),
              const Spacer(),
              // Duration
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
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        // Expanded: show all individual punches of that day
        children: allRecords.isEmpty
            ? [
                Text(
                  "No punch records for this day.",
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                ),
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
                      color: Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                ...allRecords.map((r) {
                  final bool isIn = r['type'] == 'in';
                  final DateTime dt = r['_displayTime'] as DateTime;
                  final double? lat = (r['latitude'] as num?)?.toDouble();
                  final double? lng = (r['longitude'] as num?)?.toDouble();
                  final bool hasLocation =
                      lat != null && lng != null && !(lat == 0.0 && lng == 0.0);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isIn ? Icons.login : Icons.logout,
                          size: 16,
                          color: isIn ? Colors.green[700] : Colors.red[700],
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
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (hasLocation)
                                Text(
                                  "${lat!.toStringAsFixed(4)}, ${lng!.toStringAsFixed(4)}",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[500],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              DateFormat('hh:mm a').format(dt),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              DateFormat('dd MMM').format(dt),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
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
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
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
            "No records found",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "No attendance data for the selected range.",
            style: TextStyle(color: Colors.grey[400]),
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: _pickDateRange,
            icon: const Icon(Icons.date_range),
            label: const Text("Change date range"),
          ),
        ],
      ),
    );
  }
}
