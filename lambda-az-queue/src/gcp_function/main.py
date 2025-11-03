import functions_framework
from flask import jsonify

# In a real app, you would query a database (e.g., Firestore, Spanner)
DATA_DB = {
    "user-abc-12345": {"name": "Jane Doe", "status": "active", "level": 7},
    "user-xyz-67890": {"name": "John Doe", "status": "inactive", "level": 3}
}

@functions_framework.http
def get_user_data(request):
    request_json = request.get_json(silent=True)
    if not request_json or 'userId' not in request_json:
        return jsonify({"error": "Invalid request, userId is required"}), 400

    user_id = request_json['userId']
    user_data = DATA_DB.get(user_id)

    if user_data:
        return jsonify(user_data), 200
    else:
        return jsonify({"error": "User not found"}), 404
