# backend/app.py
import firebase_admin
from firebase_admin import credentials, firestore, auth
from flask import Flask, request, jsonify
from flask_cors import CORS

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



# app.py update
@app.route('/attendance/clock', methods=['POST'])
def clock_in_out():
    try:
        data = request.json
        uid = data.get('uid')
        action = data.get('action') # 'in' or 'out'
        
        # Reference to the user's document
        user_ref = db.collection('users').document(uid)
        
        # Add to attendance collection
        db.collection('attendance').add({
            'user_id': user_ref, # Storing as a DocumentReference
            'uid': uid,
            'timestamp': firestore.SERVER_TIMESTAMP,
            'type': action,
            'status': 'Present' if action == 'in' else 'Completed'
        })
        
        return jsonify({"message": f"Successfully clocked {action}"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)