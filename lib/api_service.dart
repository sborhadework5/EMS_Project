import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Use 10.0.2.2 if using Android Emulator, or your PC's IP for physical devices
  final String baseUrl = "http://192.168.1.118:5000";

  Future<Map<String, dynamic>> fetchHomeData() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/home'));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception("Failed to load data");
      }
    } catch (e) {
      return {"message": "Error connecting to server: $e"};
    }
  }

  Future<Map<String, dynamic>> fetchUserStats(String uid) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/user/stats/$uid'));
      if (response.statusCode == 200) {
        // Use 'as Map<String, dynamic>' to tell Dart exactly what this is
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  Future<Map<String, dynamic>> clockInOut(String uid, String action) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/attendance/clock'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "uid": uid,
          "action": action, // 'in' or 'out'
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {"error": "Server returned ${response.statusCode}"};
      }
    } catch (e) {
      return {"error": "Connection failed: $e"};
    }
  }
}
