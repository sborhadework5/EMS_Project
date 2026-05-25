import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// action_pages.dart - Update the AttendanceHistoryPage
// import 'package:intl/intl.dart'; // Add intl: ^0.19.0 to pubspec.yaml

// action_pages.dart
class AttendanceHistoryPage extends StatelessWidget {
  const AttendanceHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Attendance"),
        backgroundColor: Colors.indigo[800],
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('attendance')
            .where('uid', isEqualTo: uid)
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // This will show if the Index is missing!
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No attendance records found."));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final data =
                  snapshot.data!.docs[index].data() as Map<String, dynamic>;
              // Formatting the date without the intl package for now
              DateTime? date = (data['timestamp'] as Timestamp?)?.toDate();

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: data['type'] == 'in'
                        ? Colors.green[100]
                        : Colors.red[100],
                    child: Icon(
                      data['type'] == 'in' ? Icons.login : Icons.logout,
                      color: data['type'] == 'in' ? Colors.green : Colors.red,
                    ),
                  ),
                  title:
                      Text("Clocked ${data['type'].toString().toUpperCase()}"),
                  subtitle: Text(date != null
                      ? date.toString().split('.')[0]
                      : "Processing..."),
                  trailing: Text(
                    data['status'] ?? "Present",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// action_pages.dart - Update ApplyLeavePage
class ApplyLeavePage extends StatefulWidget {
  const ApplyLeavePage({super.key});

  @override
  State<ApplyLeavePage> createState() => _ApplyLeavePageState();
}

class _ApplyLeavePageState extends State<ApplyLeavePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _reasonController = TextEditingController();
  String _leaveType = "Sick Leave";
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isSubmitting = false;

  static const Map<String, int> _maxAllowed = {
    "Sick Leave": 12,
    "Casual Leave": 6,
    "Vacation": 15,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  int get _requestedDays {
    if (_startDate == null || _endDate == null) return 0;
    return _endDate!.difference(_startDate!).inDays + 1;
  }

  Future<int> _usedDaysThisYear(String uid, String leaveType) async {
    // Simplified query — no composite index needed
    final snapshot = await FirebaseFirestore.instance
        .collection('leaves')
        .where('uid', isEqualTo: uid)
        .where('status', isEqualTo: 'Approved')
        .get();

    final startOfYear = DateTime(DateTime.now().year, 1, 1);
    int total = 0;
    for (var doc in snapshot.docs) {
      final data = doc.data();
      // Filter type and date client-side
      if (data['type'] != leaveType) continue;
      final appliedAt = (data['applied_at'] as Timestamp?)?.toDate();
      if (appliedAt == null || appliedAt.isBefore(startOfYear)) continue;
      total += (data['days'] as int? ?? 1);
    }
    return total;
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(primary: Colors.indigo[800]!),
        ),
        child: child!,
      ),
    );
    if (range != null) {
      setState(() {
        _startDate = range.start;
        _endDate = range.end;
      });
    }
  }

  Future<void> _submitLeave() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (_startDate == null || _endDate == null) {
      _showSnack("Please select a date range", isError: true);
      return;
    }
    if (_reasonController.text.trim().isEmpty) {
      _showSnack("Please enter a reason", isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Balance check
      final used = await _usedDaysThisYear(uid, _leaveType);
      final allowed = _maxAllowed[_leaveType] ?? 0;
      final remaining = allowed - used;

      if (_requestedDays > remaining) {
        _showSnack(
          "Insufficient balance. You have $remaining day(s) left for $_leaveType.",
          isError: true,
        );
        return;
      }

      // Overlap check
      final overlap = await FirebaseFirestore.instance
          .collection('leaves')
          .where('uid', isEqualTo: uid)
          .get();

      for (var doc in overlap.docs) {
        final d = doc.data();
        final existStart = (d['start_date'] as Timestamp).toDate();
        final existEnd = (d['end_date'] as Timestamp).toDate();
        if (!(_endDate!.isBefore(existStart) ||
            _startDate!.isAfter(existEnd))) {
          _showSnack(
            "You already have a ${d['status']} leave overlapping these dates.",
            isError: true,
          );
          return;
        }
      }

      await FirebaseFirestore.instance.collection('leaves').add({
        'uid': uid,
        'type': _leaveType,
        'reason': _reasonController.text.trim(),
        'status': 'Pending',
        'days': _requestedDays,
        'start_date': Timestamp.fromDate(_startDate!),
        'end_date': Timestamp.fromDate(_endDate!),
        'applied_at': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _showSnack("Leave request submitted successfully!");
        _reasonController.clear();
        setState(() {
          _startDate = null;
          _endDate = null;
        });
        _tabController.animateTo(1);
      }
    } catch (e) {
      _showSnack("Error: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red[700] : Colors.green[700],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Leave Management"),
        backgroundColor: Colors.indigo[800],
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.note_add), text: "Apply"),
            Tab(icon: Icon(Icons.history), text: "My Leaves"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildApplyTab(), _buildHistoryTab()],
      ),
    );
  }

  Widget _buildApplyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: _leaveType,
            decoration: InputDecoration(
              labelText: "Leave Type",
              prefixIcon: const Icon(Icons.category_outlined),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: _maxAllowed.keys
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (val) => setState(() => _leaveType = val!),
          ),
          const SizedBox(height: 16),

          // Balance indicator
          FutureBuilder<int>(
            future: _usedDaysThisYear(
                FirebaseAuth.instance.currentUser!.uid, _leaveType),
            builder: (context, snap) {
              final used = snap.data ?? 0;
              final allowed = _maxAllowed[_leaveType] ?? 0;
              final remaining = allowed - used;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: remaining <= 2 ? Colors.red[50] : Colors.indigo[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: remaining <= 2
                          ? Colors.red[200]!
                          : Colors.indigo[100]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 18,
                        color: remaining <= 2
                            ? Colors.red[700]
                            : Colors.indigo[700]),
                    const SizedBox(width: 8),
                    Text(
                      snap.hasData
                          ? "$remaining of $allowed day(s) remaining for $_leaveType this year"
                          : "Loading balance...",
                      style: TextStyle(
                          color: remaining <= 2
                              ? Colors.red[700]
                              : Colors.indigo[700],
                          fontWeight: FontWeight.w500,
                          fontSize: 13),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // Date range picker
          GestureDetector(
            onTap: _pickDateRange,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[400]!),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.date_range, color: Colors.indigo[800]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _startDate == null
                        ? const Text("Select date range",
                            style: TextStyle(color: Colors.grey))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${DateFormat('dd MMM yyyy').format(_startDate!)}  →  "
                                "${DateFormat('dd MMM yyyy').format(_endDate!)}",
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              Text("$_requestedDays day(s) requested",
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[600])),
                            ],
                          ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey[400]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _reasonController,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: "Reason for Leave",
              alignLabelWithHint: true,
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 60),
                child: Icon(Icons.edit_note),
              ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submitLeave,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo[800],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(_isSubmitting ? "Submitting..." : "Submit Request"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('leaves')
          .where('uid', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(child: Text("Error: ${snapshot.error}"));
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs
          ..sort((a, b) {
            final aTime = (a.data() as Map<String, dynamic>)['applied_at'] as Timestamp?;
            final bTime = (b.data() as Map<String, dynamic>)['applied_at'] as Timestamp?;
            if (aTime == null || bTime == null) return 0;
            return bTime.compareTo(aTime);
          });

        if (!snapshot.hasData || docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox_outlined, size: 60, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text("No leave requests yet",
                    style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final data =
                snapshot.data!.docs[index].data() as Map<String, dynamic>;
            return _buildLeaveCard(data);
          },
        );
      },
    );
  }

  Widget _buildLeaveCard(Map<String, dynamic> data) {
    final status = data['status'] ?? 'Pending';
    final Color statusColor = status == 'Approved'
        ? Colors.green
        : status == 'Rejected'
            ? Colors.red
            : Colors.orange;
    final startDate = (data['start_date'] as Timestamp?)?.toDate();
    final endDate = (data['end_date'] as Timestamp?)?.toDate();
    final appliedAt = (data['applied_at'] as Timestamp?)?.toDate();
    final days = data['days'] ?? 1;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(data['type'] ?? 'Leave',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(status,
                      style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.date_range, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  startDate != null && endDate != null
                      ? "${DateFormat('dd MMM').format(startDate)} – ${DateFormat('dd MMM yyyy').format(endDate)}  ($days day${days > 1 ? 's' : ''})"
                      : "Date not set",
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(data['reason'] ?? '',
                style: const TextStyle(fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            if (data['admin_remark'] != null &&
                (data['admin_remark'] as String).isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.comment_outlined,
                      size: 13, color: Colors.indigo[400]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text("Admin: ${data['admin_remark']}",
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.indigo[600],
                            fontStyle: FontStyle.italic)),
                  ),
                ],
              ),
            ],
            if (appliedAt != null) ...[
              const SizedBox(height: 8),
              Text("Applied on ${DateFormat('dd MMM yyyy').format(appliedAt)}",
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
          ],
        ),
      ),
    );
  }
}

// action_pages.dart - Update IDCardPage
class IDCardPage extends StatelessWidget {
  const IDCardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text("Digital ID Card")),
      body: FutureBuilder<DocumentSnapshot>(
        future:
            FirebaseFirestore.instance.collection('users').doc(user?.uid).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          var userData = snapshot.data!.data() as Map<String, dynamic>;

          return Center(
            child: Card(
              elevation: 15,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Container(
                width: 320,
                height: 500,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    colors: [Colors.indigo[900]!, Colors.indigo[700]!],
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    const CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.person, size: 80, color: Colors.indigo),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      userData['name']?.toUpperCase() ?? "NAME",
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      userData['role'] ?? "Employee",
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 30),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      color: Colors.white,
                      child: Text(
                        "UID: ${user?.uid.substring(0, 8)}",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, letterSpacing: 2),
                      ),
                    ),
                    const Spacer(),
                    const Text("EMS SYSTEM",
                        style: TextStyle(color: Colors.white38, fontSize: 12)),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
