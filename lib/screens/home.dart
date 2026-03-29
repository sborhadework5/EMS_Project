import 'dart:async';
import 'dart:io' show Platform;
import 'package:ems_project/screens/action_pages.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'package:workmanager/workmanager.dart';
import 'package:geolocator/geolocator.dart';
import '../api_service.dart'; // Ensure this path is correct
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // Add this import
import 'package:ems_project/screens/admin/admin_home.dart'; // Adjust 'ems_project' to your actual project name

Timer? _locationTimer;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EMS Project',
      theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
      // This tells the app to load HomePage first
      home: const HomePage(),
    );
  }
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'ems_tracking_channel', // ID
    'EMS Live Tracking', // Title
    description: 'This channel is used for persistent location tracking.',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true, // THIS keeps the app alive
      notificationChannelId: 'ems_tracking_channel',
      initialNotificationTitle: 'EMS Tracking Active',
      initialNotificationContent: 'Initializing location services...',
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

// 2. The Logic (MUST be a Top-Level function)
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
  final ApiService apiService = ApiService();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: "EMS Tracking Active",
      content: "Your distance is being recorded...",
    );
  }

  // FIXED: Set to 5 minutes (300 seconds)
  Timer.periodic(const Duration(minutes: 5), (timer) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Use high accuracy but a strict timeout
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      final result = await apiService.updateLiveLocation(
        user.uid,
        position.latitude,
        position.longitude,
      );

      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          // You can pass the updated distance from your Flask response here
          double added = result['added'] ?? 0.0;
          service.setForegroundNotificationInfo(
            title: "EMS Tracking: ACTIVE",
            content: "Last sync successful. Tracking your work travel...",
          );
        }
      }

      service.invoke('update'); // Notifies UI if app is open
    } catch (e) {
      debugPrint("Background Sync Error: $e");
    }
  });
}

@pragma('vm:entry-point')
bool onIosBackground(ServiceInstance service) {
  return true;
}

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
  String distanceDisplay = "0.00 km";

  @override
  void initState() {
    super.initState();
    _fetchUserData();
    _checkCurrentClockStatus();
    if (!kIsWeb) {
      _startLiveTracking();
      _listenToBackgroundUpdates();
      _getCurrentLocationOnce();
    } else {
      // Optional: On Web, you can use a simple timer to refresh data
      // since background services don't exist.
      Timer.periodic(const Duration(minutes: 5), (timer) => _fetchUserData());
    }
    _requestPermissions();
  }

  Future<void> _getCurrentLocationOnce() async {
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    _sendLocationToBackend(position);
  }

  void _listenToBackgroundUpdates() {
    FlutterBackgroundService().on('update').listen((event) {
      if (mounted) {
        _fetchUserData(); // This pulls the fresh 'total_distance_today' from Firestore
      }
    });
  }

  Future<void> _requestPermissions() async {
    // 1. Request Notification Permission (Crucial for Android 13+)
    if (!kIsWeb && Platform.isAndroid) {
      var notifyStatus = await Permission.notification.status;
      if (!notifyStatus.isGranted) {
        await Permission.notification.request();
      }
    }

    // 2. Request Location Permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.whileInUse) {
      await Permission.locationAlways.request();
    }
  }

  @override
  void dispose() {
    _locationTimer?.cancel(); // Clean up the timer when app closes
    super.dispose();
  }

  void _startLiveTracking() {
    // Define settings for background behavior
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Only trigger if moved 10 meters
    );

    Geolocator.getPositionStream(locationSettings: locationSettings).listen((
      Position position,
    ) {
      _sendLocationToBackend(position);
    }, onError: (e) => print("Stream Error: $e"));
  }

  Future<void> _sendLocationToBackend(Position position) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await ApiService().updateLiveLocation(
      user.uid,
      position.latitude,
      position.longitude,
    );

    // Refresh UI
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    if (!mounted) return;

    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => isLoading = false);
      return; // Stop here if user isn't fully loaded yet
    }

    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // 1. Get Distance directly from Firestore (Most Reliable)
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.server));

        // 2. Get Stats from Flask
        Map<String, dynamic> response = {};
        try {
          response = await ApiService().fetchUserStats(user.uid);
        } catch (e) {
          print("API Error: $e");
        }

        if (userDoc.exists && mounted) {
          final data = userDoc.data() as Map<String, dynamic>;
          setState(() {
            // Check if your Firestore field name matches: 'full_name' or 'name'
            userName = data['full_name'] ?? data['name'] ?? "User";
            role = data['role'] ?? "Employee";

            // Calculate distance
            double dist = (data['total_distance_today'] ?? 0.0).toDouble();
            distanceDisplay = "${dist.toStringAsFixed(2)} km";

            // Calculate Attendance (ensure Flask returns 'attendance_rate')
            attendance = response['attendance_rate'] ?? "0%";
            leaves = response['leaves_taken'] ?? "0";
            isLoading = false; // Turn off spinner here
          });
        }
      }
    } catch (e) {
      print("UI Sync Error: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // REPLACED: Point to the new Admin Hub instead of just the list
    if (kIsWeb && role.toLowerCase() == 'admin') {
      return const AdminHomePage();
    }
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
      child: Column(
        // Changed to column to add a second row if needed
        children: [
          Row(
            children: [
              _statCard(
                "Attendance",
                attendance,
                Icons.calendar_today,
                Colors.orange,
              ),
              const SizedBox(width: 15),
              _statCard(
                "Travelled",
                distanceDisplay,
                Icons.directions_walk,
                Colors.blue,
              ),
            ],
          ),
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

    bool previousState = isClockedIn;
    String action = isClockedIn ? "out" : "in";

    // 1. INSTANT UI FEEDBACK
    setState(() => isClockedIn = !isClockedIn);

    try {
      // 2. ULTRA-FAST WRITE (Direct to Firebase)
      // This bypasses the Flask "middle-man" for the log entry
      await FirebaseFirestore.instance.collection('attendance').add({
        'uid': user.uid,
        'timestamp': FieldValue.serverTimestamp(),
        'type': action,
        'status': action == 'in' ? 'Present' : 'Completed',
      });

      // 3. BACKGROUND API HIT (Optional)
      // Only use this if your Flask backend sends emails/notifications
      // ApiService().clockInOut(user.uid, action);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Successfully clocked $action"),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      // 4. ROLLBACK ON FAILURE
      if (mounted) {
        setState(() => isClockedIn = previousState);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Offline: Could not clock $action"),
            backgroundColor: Colors.red,
          ),
        );
      }
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
