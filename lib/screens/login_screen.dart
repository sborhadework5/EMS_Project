import 'package:ems_project/screens/admin/admin_home.dart'; // Import Admin Home
import 'package:ems_project/screens/home.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatelessWidget {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  LoginScreen({super.key});

  Future<void> _login(BuildContext context) async {
    String email = _emailController.text.trim().toLowerCase();
    String password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter email and password")),
      );
      return;
    }

    try {
    // STEP 1: Sign in FIRST. This populates request.auth in Firebase.
    UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    // STEP 2: Now that we are authenticated, we can safely fetch the document
    var userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userCredential.user!.uid) // Use the UID directly, no need for 'where' query
        .get();

    if (!userDoc.exists) {
      throw "User record not found in database.";
    }

    var userData = userDoc.data()!;
    String role = userData['role'] ?? 'employee';

    if (!context.mounted) return;

    // STEP 3: Redirection
    if (role == 'admin') {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AdminHomePage()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const HomePage()));
    }

  } on FirebaseAuthException catch (e) {
      String errorMsg = "Login Failed";
      if (e.code == 'user-not-found') errorMsg = "No user found with this email.";
      if (e.code == 'wrong-password') errorMsg = "Incorrect password.";
      
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_person, size: 80, color: Colors.indigo),
              const SizedBox(height: 20),
              const Text(
                "EMS LOGIN",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.indigo),
              ),
              const Text("Secure Employee Management System", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 40),
              
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.email_outlined),
                  labelText: "Official Email",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),
              
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock_outline),
                  labelText: "Password",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 30),
              
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _login(context),
                  child: const Text("SIGN IN", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Contact Admin if you cannot log in",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}