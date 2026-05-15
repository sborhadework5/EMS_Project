import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';

class LiveLocationPage extends StatefulWidget {
  final String uid;
  final String employeeName;

  const LiveLocationPage({
    super.key,
    required this.uid,
    required this.employeeName,
  });

  @override
  State<LiveLocationPage> createState() => _LiveLocationPageState();
}

class _LiveLocationPageState extends State<LiveLocationPage> {
  final MapController _mapController = MapController();
  LatLng? _currentPosition;
  DateTime? _lastUpdated;
  bool _hasValidLocation = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.employeeName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Text(
              "Live Location",
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: Colors.indigo[800],
        foregroundColor: Colors.white,
        actions: [
          // Re-center button
          if (_currentPosition != null)
            IconButton(
              icon: const Icon(Icons.my_location),
              tooltip: "Center on employee",
              onPressed: () {
                _mapController.move(_currentPosition!, 15.0);
              },
            ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final lastLoc = data['last_location'] as Map<String, dynamic>?;

          final double lat = (lastLoc?['lat'] ?? 0.0).toDouble();
          final double lng = (lastLoc?['lng'] ?? 0.0).toDouble();
          final Timestamp? ts = lastLoc?['last_updated'] as Timestamp?;

          // lat == 0 && lng == 0 means never updated (default value)
          _hasValidLocation = !(lat == 0.0 && lng == 0.0);

          if (_hasValidLocation) {
            _currentPosition = LatLng(lat, lng);
            _lastUpdated = ts?.toDate();
          }

          return Column(
            children: [
              // Status bar
              _buildStatusBar(data),

              // Map
              Expanded(
                child: _hasValidLocation
                    ? _buildMap()
                    : _buildNoLocationPlaceholder(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusBar(Map<String, dynamic> data) {
    final lastLoc = data['last_location'] as Map<String, dynamic>?;
    final Timestamp? ts = lastLoc?['last_updated'] as Timestamp?;
    final String timeAgo = ts != null ? _timeAgo(ts.toDate()) : "Never";
    final double dist = (data['total_distance_today'] ?? 0.0).toDouble();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white,
      child: Row(
        children: [
          // Live indicator dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _hasValidLocation ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _hasValidLocation ? "Live" : "No data",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _hasValidLocation ? Colors.green[700] : Colors.grey,
            ),
          ),
          const SizedBox(width: 16),
          Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            "Updated $timeAgo",
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const Spacer(),
          Icon(Icons.directions_walk, size: 14, color: Colors.indigo[800]),
          const SizedBox(width: 4),
          Text(
            "${dist.toStringAsFixed(2)} km today",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.indigo[800],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentPosition!,
        initialZoom: 15.0,
        maxZoom: 18.0,
        minZoom: 5.0,
      ),
      children: [
        // OpenStreetMap tiles (free, no API key)
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.emsProject',
        ),

        // Employee marker
        MarkerLayer(
          markers: [
            Marker(
              point: _currentPosition!,
              width: 80,
              height: 80,
              child: Column(
                children: [
                  // Name bubble
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.indigo[800],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.employeeName.split(' ').first,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Pin icon
                  Icon(
                    Icons.location_pin,
                    color: Colors.indigo[800],
                    size: 32,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNoLocationPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.location_off, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            "No location data yet",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "${widget.employeeName} hasn't shared their location today.",
            style: TextStyle(color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return "${diff.inSeconds}s ago";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    if (diff.inHours < 24) return "${diff.inHours}h ago";
    return DateFormat('dd MMM, hh:mm a').format(dt);
  }
}