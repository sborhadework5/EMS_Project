import 'dart:async';
import 'dart:io' show Platform;
import 'package:ems_project/screens/action_pages.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'package:workmanager/workmanager.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../api_service.dart'; // Ensure this path is correct
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:permission_handler/permission_handler.dart' hide ServiceStatus;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // Add this import
import 'package:ems_project/screens/admin/admin_home.dart'; // Adjust 'ems_project' to your actual project name
import 'package:ems_project/screens/time_card_page.dart';

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
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
    showBadge: false,
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
      initialNotificationTitle: 'EMS APP : Work In Progress..',
      initialNotificationContent: ' ',
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
  // 1. Initialize Firebase for the background process
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }

  final ApiService apiService = ApiService();

  // 2. Setup Foreground Notification (Android only)
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: "EMS Live Tracking",
      content: "Initializing location services...",
    );
  }

  // 3. Monitor GPS Hardware Status
  // If user turns off GPS manually, log them out and stop service
  Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
    if (status == ServiceStatus.disabled) {
      FirebaseAuth.instance.signOut();
      service.invoke('forceLogout');
      service.stopSelf();
    }
  });

  // 4. THE STREAM: Replaces the Timer for better accuracy
  const LocationSettings locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 20, // Trigger API update only after moving 20 meters
  );

  Geolocator.getPositionStream(locationSettings: locationSettings).listen((
    Position position,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Sync real-time movement to your Flask backend
      final result = await apiService.updateLiveLocation(
        user.uid,
        position.latitude,
        position.longitude,
      );

      // Update the persistent notification with live feedback
      if (service is AndroidServiceInstance) {
        double added = (result['added'] ?? 0.0).toDouble();

        service.setForegroundNotificationInfo(
          title: "EMS: Tracking Active",
          content: added > 0
              ? "Movement detected: Tracking your work travel..."
              : "Stationary: Location synchronized.",
        );
      }

      // Notify UI to refresh stats (Distance, etc.) if app is open
      service.invoke('update');
    } catch (e) {
      debugPrint("Background Sync Error: $e");
    }
  }, onError: (e) => debugPrint("Location Stream Error: $e"));

  // 5. Allow manual service stop from UI
  service.on('stopService').listen((event) {
    service.stopSelf();
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
      _startLocationServiceListener();
      _getCurrentLocationOnce();
    } else {
      // Optional: On Web, you can use a simple timer to refresh data
      // since background services don't exist.
      Timer.periodic(const Duration(minutes: 5), (timer) => _fetchUserData());
    }
    _requestPermissions();
  }

  void _startLocationServiceListener() {
    // 1. Listen while the app is in the foreground
    Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
      if (status == ServiceStatus.disabled) {
        _performLogout();
      }
    });

    // 2. Listen for the 'forceLogout' event from the background service
    FlutterBackgroundService().on('forceLogout').listen((event) {
      _performLogout();
    });
  }

  void _performLogout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      // Navigate back to login screen (Replace 'LoginPage' with your actual class)
      // Navigator.of(context).pushAndRemoveUntil(...)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Location disabled. You have been logged out."),
          backgroundColor: Colors.red,
        ),
      );
    }
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
    if (kIsWeb) {
      // Web only needs basic location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      return; // Exit early for web
    }

    // Mobile specific permissions (Background, Notifications)
    if (Platform.isAndroid) {
      var notifyStatus = await Permission.notification.status;
      if (!notifyStatus.isGranted) await Permission.notification.request();
    }

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
      distanceFilter: 100, // Only trigger if moved 10 meters
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
    bool isLocationEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isLocationEnabled) {
      _performLogout();
      return;
    }

    if (!mounted) return;

    User? user = FirebaseAuth.instance.currentUser;
    int retryCount = 0;
    while (user == null && retryCount < 5) {
      await Future.delayed(const Duration(milliseconds: 500));
      user = FirebaseAuth.instance.currentUser;
      retryCount++;
    }

    if (user == null) {
      setState(() => isLoading = false);
      return; // Stop here if user isn't fully loaded yet
    }

    try {
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
            labelStyle: const TextStyle(color: Colors.black),
          ),
        ],
      ),
    );
  }

  // Find this section in home.dart
  Widget _buildSummaryStats() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        // Changed from Column if you only have one card now
        children: [
          _statCard(
            "Attendance",
            attendance,
            Icons.calendar_today,
            Colors.orange,
          ),
          // REMOVE OR COMMENT OUT THE CODE BELOW:
          /* const SizedBox(width: 15),
        _statCard(
          "Travelled",
          distanceDisplay,
          Icons.directions_walk,
          Colors.blue,
        ),
        */
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
      {'title': 'Time Card', 'icon': Icons.receipt_long},
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
    } else if (title == 'Time Card') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const TimeCardPage()),
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

    // NEW: Capture location and time before the existing logic starts
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    String formattedDate = DateFormat(
      'yyyy-MM-dd HH:mm:ss',
    ).format(DateTime.now());

    bool previousState = isClockedIn;
    String action = isClockedIn ? "out" : "in";

    // 1. INSTANT UI FEEDBACK
    setState(() => isClockedIn = !isClockedIn);

    try {
      // 2. ULTRA-FAST WRITE (Direct to Firebase)
      // Updated with location and display_time while keeping the rest same
      await FirebaseFirestore.instance.collection('attendance').add({
        'uid': user.uid,
        'timestamp': FieldValue.serverTimestamp(),
        'type': action,
        'status': action == 'in' ? 'Present' : 'Completed',
        // Added new fields here
        'latitude': position.latitude,
        'longitude': position.longitude,
        'display_time': formattedDate,
      });

      // 3. BACKGROUND API HIT (Optional)
      // If you use this, you can now pass the extra data to your Flask service
      // ApiService().clockInOut(user.uid, action, position.latitude, position.longitude, formattedDate);

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
