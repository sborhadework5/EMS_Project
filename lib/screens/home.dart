import 'dart:async';

import 'package:ems_project/screens/action_pages.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'package:workmanager/workmanager.dart';
import 'package:geolocator/geolocator.dart';
import '../api_service.dart'; // Ensure this path is correct

Timer? _locationTimer;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? userName;
  String role = 'Employee';
  String attendance = "...";
  String leaves = "...";
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
    _checkCurrentClockStatus();
    _startLiveTracking();
  }

  @override
  void dispose() {
    _locationTimer?.cancel(); // Clean up the timer when app closes
    super.dispose();
  }

  void _startLiveTracking() {
    // 1. Initial hit
    _sendLocationToBackend();

    // 2. Repeat every 15 minutes
    _locationTimer = Timer.periodic(const Duration(minutes: 15), (timer) {
      _sendLocationToBackend();
    });
  }

  Future<void> _sendLocationToBackend() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        // Hit your Flask API
        await ApiService().updateLiveLocation(
          user.uid,
          position.latitude,
          position.longitude,
        );
        print(
          "Location synced to Flask: ${position.latitude}, ${position.longitude}",
        );
      }
    } catch (e) {
      print("Location tracking error: $e");
    }
  }

  Future<void> _fetchUserData() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        Map<String, dynamic> response = {};
        try {
          response = await ApiService()
              .fetchUserStats(user.uid)
              .timeout(const Duration(seconds: 4));
        } catch (e) {
          print("Backend stats unreachable: $e");
        }

        if (userDoc.exists && mounted) {
          final data = userDoc.data() as Map<String, dynamic>;
          setState(() {
            // Check BOTH keys to be safe
            userName = data['full_name'] ?? "User";
            role = data['role'] ?? "Employee";
            attendance = response['attendance_rate'] ?? "0%";
            leaves = response['leaves_taken'] ?? "0";
          });
        }
      }
    } catch (e) {
      print("UI Sync Error: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.indigo[800],
        foregroundColor: Colors.white,
        title: const Text(
          "Dashboard",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  _buildSummaryStats(),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Text(
                      "Quick Actions",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _buildActionGrid(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.indigo[800],
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Welcome back,",
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          Text(
            userName ?? "Loading...",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Chip(
            label: Text(role.toUpperCase()),
            backgroundColor: Colors.white24,
            labelStyle: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStats() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        children: [
          _statCard(
            "Attendance",
            attendance,
            Icons.calendar_today,
            Colors.orange,
          ),
          const SizedBox(width: 15),
          _statCard("Leaves", leaves, Icons.beach_access, Colors.green),
        ],
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
        ),
        child: Column(
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.1),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(title, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionGrid() {
    final actions = _getMenuItemsByRole();
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 15,
        mainAxisSpacing: 15,
        childAspectRatio: 1.2,
      ),
      itemCount: actions.length,
      itemBuilder: (context, index) {
        return InkWell(
          onTap: () => _handleAction(actions[index]['title']),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  actions[index]['icon'],
                  size: 35,
                  color: Colors.indigo[800],
                ),
                const SizedBox(height: 10),
                Text(
                  actions[index]['title'],
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _getMenuItemsByRole() {
    if (role.toLowerCase() == 'admin') {
      return [
        {'title': 'Employees', 'icon': Icons.people},
        {'title': 'Payroll', 'icon': Icons.payments},
        {'title': 'Assets', 'icon': Icons.inventory},
        {'title': 'Reports', 'icon': Icons.analytics},
      ];
    }
    return [
      {'title': 'Clock In/Out', 'icon': Icons.timer},
      {'title': 'My Attendance', 'icon': Icons.history},
      {'title': 'Apply Leave', 'icon': Icons.note_add},
      {'title': 'ID Card', 'icon': Icons.badge},
    ];
  }

  // Inside _HomePageState in home.dart

  void _handleAction(String title) {
    if (title == 'Clock In/Out') {
      _showClockDialog();
    } else if (title == 'My Attendance') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const AttendanceHistoryPage()),
      );
    } else if (title == 'Apply Leave') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ApplyLeavePage()),
      );
    } else if (title == 'ID Card') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const IDCardPage()),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Opening $title...")));
    }
  }

  // Inside home.dart -> _HomePageState

  // Inside _HomePageState in home.dart

  bool isClockedIn = false; // Add this variable at the top of your state

  Future<void> _checkCurrentClockStatus() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final query = await FirebaseFirestore.instance
          .collection('attendance')
          .where('uid', isEqualTo: uid)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final lastAction = query.docs.first.data()['type'];
        setState(() {
          // If last action was 'in', then isClockedIn should be true
          isClockedIn = (lastAction == 'in');
        });
        print("Current Status: ${isClockedIn ? 'Clocked IN' : 'Clocked OUT'}");
      }
    } catch (e) {
      print("Error checking status: $e");
    }
  }

  Future<void> _handleClockInOut() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  String action = isClockedIn ? "out" : "in";
  setState(() => isLoading = true); // This starts the loading spinner

  try {
    // We add a timeout so the app doesn't spin forever if the server is slow
    final response = await ApiService().clockInOut(user.uid, action).timeout(
      const Duration(seconds: 10),
    );

    if (mounted) {
      if (response.containsKey('message')) {
        setState(() => isClockedIn = !isClockedIn);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message']), backgroundColor: Colors.green),
        );
      } else {
        // This catches the '500' or 'error' message from Flask
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Server Error: ${response['error']}"), backgroundColor: Colors.red),
        );
      }
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Connection Timeout: Check if Flask is running"), backgroundColor: Colors.orange),
    );
  } finally {
    // This stops the loading spinner no matter what happens
    if (mounted) setState(() => isLoading = false);
  }
}

  void _showClockDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isClockedIn ? "Clock Out" : "Clock In"),
        content: Text(
          "Confirm you want to ${isClockedIn ? 'Clock Out' : 'Clock In'} for now?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isClockedIn ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              _handleClockInOut();
            },
            child: const Text("Confirm"),
          ),
        ],
      ),
    );
  }
}
