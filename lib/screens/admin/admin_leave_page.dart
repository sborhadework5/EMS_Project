import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AdminLeavePage extends StatefulWidget {
  const AdminLeavePage({super.key});

  @override
  State<AdminLeavePage> createState() => _AdminLeavePageState();
}

class _AdminLeavePageState extends State<AdminLeavePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Leave Requests",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[800],
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: "Pending"),
            Tab(text: "Approved"),
            Tab(text: "Rejected"),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: Colors.indigo[800],
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Search employee name...",
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildLeaveList("Pending"),
                _buildLeaveList("Approved"),
                _buildLeaveList("Rejected"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveList(String status) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('leaves')
          .where('status', isEqualTo: status)
          .orderBy('applied_at', descending: true)
          .snapshots(),
      builder: (context, leaveSnap) {
        if (leaveSnap.hasError) {
          return Center(child: Text("Error: ${leaveSnap.error}"));
        }
        if (!leaveSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final leaves = leaveSnap.data!.docs;

        if (leaves.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline,
                    size: 60,
                    color: status == 'Pending'
                        ? Colors.orange[300]
                        : Colors.grey[400]),
                const SizedBox(height: 12),
                Text("No $status requests",
                    style: TextStyle(color: Colors.grey[600], fontSize: 16)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: leaves.length,
          itemBuilder: (context, index) {
            final leaveData =
                leaves[index].data() as Map<String, dynamic>;
            final leaveId = leaves[index].id;
            final uid = leaveData['uid'] as String?;

            if (uid == null) return const SizedBox.shrink();

            // Fetch employee name from users collection
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .get(),
              builder: (context, userSnap) {
                final employeeName = userSnap.hasData && userSnap.data!.exists
                    ? (userSnap.data!.data()
                            as Map<String, dynamic>)['full_name'] ??
                        'Unknown'
                    : 'Loading...';

                // Apply search filter
                if (_searchQuery.isNotEmpty &&
                    !employeeName.toLowerCase().contains(_searchQuery)) {
                  return const SizedBox.shrink();
                }

                return _buildLeaveCard(
                  leaveData: leaveData,
                  leaveId: leaveId,
                  employeeName: employeeName,
                  status: status,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildLeaveCard({
    required Map<String, dynamic> leaveData,
    required String leaveId,
    required String employeeName,
    required String status,
  }) {
    final startDate = (leaveData['start_date'] as Timestamp?)?.toDate();
    final endDate = (leaveData['end_date'] as Timestamp?)?.toDate();
    final appliedAt = (leaveData['applied_at'] as Timestamp?)?.toDate();
    final days = leaveData['days'] ?? 1;

    final Color statusColor = status == 'Approved'
        ? Colors.green
        : status == 'Rejected'
            ? Colors.red
            : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.indigo[100],
                  child: Text(
                    employeeName.isNotEmpty ? employeeName[0].toUpperCase() : '?',
                    style: TextStyle(
                        color: Colors.indigo[900],
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(employeeName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(leaveData['type'] ?? 'Leave',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 13)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
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

            const Divider(height: 20),

            // ── Details ──
            _infoRow(
              Icons.date_range,
              startDate != null && endDate != null
                  ? "${DateFormat('dd MMM yyyy').format(startDate)} → ${DateFormat('dd MMM yyyy').format(endDate)}"
                  : "No dates set",
            ),
            const SizedBox(height: 6),
            _infoRow(
              Icons.timer_outlined,
              "$days day${days > 1 ? 's' : ''} requested",
            ),
            const SizedBox(height: 6),
            _infoRow(Icons.edit_note, leaveData['reason'] ?? ''),

            if (leaveData['admin_remark'] != null &&
                (leaveData['admin_remark'] as String).isNotEmpty) ...[
              const SizedBox(height: 6),
              _infoRow(
                Icons.comment_outlined,
                "Remark: ${leaveData['admin_remark']}",
                color: Colors.indigo[700]!,
              ),
            ],

            if (appliedAt != null) ...[
              const SizedBox(height: 4),
              Text(
                "Applied: ${DateFormat('dd MMM yyyy, hh:mm a').format(appliedAt)}",
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],

            // ── Action buttons (only for Pending) ──
            if (status == 'Pending') ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _showActionDialog(leaveId, 'Rejected', employeeName),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text("Reject"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _showActionDialog(leaveId, 'Approved', employeeName),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text("Approve"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, {Color? color}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color ?? Colors.grey[600]),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
                fontSize: 13, color: color ?? Colors.grey[800]),
          ),
        ),
      ],
    );
  }

  void _showActionDialog(String leaveId, String newStatus, String name) {
    final remarkController = TextEditingController();
    final isApproving = newStatus == 'Approved';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(isApproving ? Icons.check_circle : Icons.cancel,
                color: isApproving ? Colors.green : Colors.red),
            const SizedBox(width: 8),
            Text("${isApproving ? 'Approve' : 'Reject'} Leave"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "${isApproving ? 'Approving' : 'Rejecting'} leave request for $name.",
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: remarkController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: "Remark (optional)",
                hintText: isApproving
                    ? "e.g. Approved as requested"
                    : "e.g. Insufficient notice period",
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isApproving ? Colors.green[700] : Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(context);
              await _updateLeaveStatus(
                  leaveId, newStatus, remarkController.text.trim());
            },
            child: Text(isApproving ? "Approve" : "Reject"),
          ),
        ],
      ),
    );
  }

  Future<void> _updateLeaveStatus(
      String leaveId, String newStatus, String remark) async {
    try {
      await FirebaseFirestore.instance
          .collection('leaves')
          .doc(leaveId)
          .update({
        'status': newStatus,
        'admin_remark': remark,
        'actioned_at': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Leave $newStatus successfully"),
          backgroundColor:
              newStatus == 'Approved' ? Colors.green[700] : Colors.red,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    }
  }
}
