// Add this class to your project (e.g., in a new file auth_wrapper.dart)
import 'package:ems_project/screens/home.dart';
import 'package:ems_project/screens/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // If the snapshot has a user, they are logged in
        if (snapshot.hasData) {
          return const HomePage();
        }
        // Otherwise, they need to log in
        return LoginScreen();
      },
    );
  }
}