import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Use 10.0.2.2 if using Android Emulator, or your PC's IP for physical devices
  final String baseUrl = "https://ems-project-pvxd.onrender.com";

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

  Future<Map<String, dynamic>> registerUser({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/register_user'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "name": name,
          "email": email,
          "password": password,
        }),
      );

      final responseData = json.decode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        // Check if UID exists in the map
        if (responseData.containsKey('uid')) {
          return responseData; 
        } else {
          throw "Server response missing UID";
        }
      } else {
        // Catch specific error messages from Flask
        throw responseData['error'] ?? "Failed to register user";
      }
    } catch (e) {
      throw e.toString();
    }
  }

  Future<Map<String, dynamic>> fetchUserStats(String uid) async {
    final response = await http.get(Uri.parse('$baseUrl/user/stats/$uid'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return {};
  }

  Future<Map<String, dynamic>> clockInOut(String uid, String action) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/attendance/clock'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"uid": uid, "action": action}),
          )
          .timeout(
            const Duration(seconds: 5),
          ); // Lower timeout for snappier feedback

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {"error": "Server error: ${response.statusCode}"};
      }
    } on TimeoutException {
      return {"error": "Connection timed out. Syncing in background..."};
    } catch (e) {
      return {"error": "Connection failed: $e"};
    }
  }

  // Change 'Future<void>' to 'Future<Map<String, dynamic>>'
  Future<Map<String, dynamic>> updateLiveLocation(
    String uid,
    double lat,
    double lng,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/user/update_location'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uid': uid, 'latitude': lat, 'longitude': lng}),
      );

      if (response.statusCode == 200) {
        // This is the important part: returning the data from Flask
        return jsonDecode(response.body);
      } else {
        return {'added': 0.0};
      }
    } catch (e) {
      print("API Error: $e");
      return {'added': 0.0};
    }
  }
}
