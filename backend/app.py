# backend/app.py
import os
import json
import firebase_admin
from firebase_admin import credentials, firestore, auth
from flask import Flask, request, jsonify
from flask_cors import CORS
from geopy.distance import geodesic

firebase_keys = os.environ.get('FIREBASE_CREDENTIALS')

if firebase_keys:
    # If it finds the environment variable, it means it's running on Render
    cred_dict = json.loads(firebase_keys)
    cred = credentials.Certificate(cred_dict)
else:
    # If not, it means it's running locally on your Mac
    cred = credentials.Certificate("serviceAccountKey.json")

firebase_admin.initialize_app(cred)
db = firestore.client()

app = Flask(__name__)

CORS(app, resources={r"/*": {"origins": "*"}})

@app.route('/register_user', methods=['POST'])
def register_user():
    try:
        data = request.json
        print(f"Data received from Flutter: {data}") # Debug line

        # 1. Create user in Firebase Auth
        user = auth.create_user(
            email=data['email'].strip(),
            password=data['password']
        )
            
            # 2. Store in Firestore
        db.collection('users').document(user.uid).set({
            'name': data['name'],
            'email': data['email'],
            'role': 'Employee',
            'created_at': firestore.SERVER_TIMESTAMP
        })
            
        return jsonify({"message": "User registered successfully"}), 201
    except Exception as e:
        print(f"Error occurred: {e}") # This will show in your terminal!
        return jsonify({"error": str(e)}), 400

@app.route('/user/stats/<uid>', methods=['GET'])
def get_user_stats(uid):
    try:
        # Fetching attendance and leave count from Firestore
        user_ref = db.collection('users').document(uid)
        doc = user_ref.get()
            
        if not doc.exists:
            return jsonify({"error": "User not found"}), 404

        # In a real app, you'd calculate this from an 'attendance' collection
        # For now, we return mock data that matches your UI cards
        stats = {
            "attendance_rate": "98%",
            "leaves_taken": "02",
            "role": doc.to_dict().get('role', 'Employee')
        }
        return jsonify(stats), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500



@app.route('/attendance/clock', methods=['POST'])
def clock_in_out():
    try:
        data = request.json
        uid = data.get('uid')
        action = data.get('action') 
            
        if not uid or not action:
            return jsonify({"error": "Missing UID or Action"}), 400

        # Reference to the user's document
        user_ref = db.collection('users').document(uid)
            
        # Add to attendance collection
        db.collection('attendance').add({
            'uid': uid,            # This MUST be a string for Flutter to query it
            'timestamp': firestore.SERVER_TIMESTAMP,
            'type': action,
            'status': 'Present' if action == 'in' else 'Completed'
        })
            
        return jsonify({"message": f"Successfully clocked {action}"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
        


from datetime import datetime, timezone

@app.route('/user/update_location', methods=['POST'])
def update_location():
    try:
        data = request.json
        uid = data.get('uid')
        new_lat = float(data.get('latitude'))
        new_lng = float(data.get('longitude'))
        new_coords = (new_lat, new_lng)

        user_ref = db.collection('users').document(uid)
            
        # 1. Log to History for verification/auditing
        user_ref.collection('location_history').add({
                'latitude': new_lat,
                'longitude': new_lng,
                'timestamp': firestore.SERVER_TIMESTAMP
            })

        user_doc = user_ref.get()
        distance_increment = 0.0

        if user_doc.exists:
            user_data = user_doc.to_dict()
            last_loc = user_data.get('last_location', {})
            last_time = last_loc.get('last_updated')
                
            is_same_day = False
            if last_time:
                # Convert Firestore timestamp to Python datetime
                last_dt = last_time.replace(tzinfo=timezone.utc)
                now_dt = datetime.now(timezone.utc)
                is_same_day = (last_dt.date() == now_dt.date())

            if is_same_day and last_loc.get('lat'):
                old_coords = (last_loc['lat'], last_loc['lng'])
                dist_moved = geodesic(old_coords, new_coords).km
                    
                # 0.01 km = 10 meters (Jitter filter)
                # Also add a "Sanity Check" (e.g., if dist > 50km in 1 min, it's a GPS error)
                if 0.01 <= dist_moved <= 5.0: 
                    distance_increment = dist_moved
            else:
                # It's a new day or first-ever location! 
                # We update the location but set increment to 0.0
                # Optional: Reset total_distance_today to 0 in Firestore if it's a new day
                user_ref.update({'total_distance_today': 0.0}) 
                distance_increment = 0.0

            # 2. Update Main User Doc
        user_ref.update({
            'last_location': {
                'lat': new_lat,
                'lng': new_lng,
                'last_updated': firestore.SERVER_TIMESTAMP
            },
            'total_distance_today': firestore.Increment(distance_increment)
        })

        return jsonify({"status": "success", "added": distance_increment}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
        
if __name__ == '__main__':
        # Cloud Run provides a port, or we default to 8080 locally
    port = int(os.environ.get('PORT', 8080))
    app.run(debug=False, host='0.0.0.0', port=port)