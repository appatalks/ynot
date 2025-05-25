import os
import hashlib
import base64
import time
from flask import Flask, request, jsonify
import mysql.connector
from mysql.connector import pooling
import logging
import json
from dotenv import load_dotenv
from datetime import datetime
from functools import wraps

app = Flask(__name__)

# Load environment variables from .env file
load_dotenv()

# Load environment variables
DB_HOST = os.getenv('DB_HOST')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')
DB_NAME = os.getenv('DB_NAME')
ALLOWED_IPS = os.getenv('ALLOWED_IPS')

# Configure logging
logging.basicConfig(level=logging.INFO)

# Setup MySQL connection pooling
dbconfig = {
    "host": DB_HOST,
    "user": DB_USER,
    "password": DB_PASSWORD,
    "database": DB_NAME
}
connection_pool = pooling.MySQLConnectionPool(pool_name="apipool",
                                              pool_size=32,
                                              **dbconfig)

def ip_restricted(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if request.remote_addr not in ALLOWED_IPS:
            return jsonify({'status': 'error', 'message': 'Forbidden: Access is denied.'}), 403
        return f(*args, **kwargs)
    return decorated_function

# Endpoint to save data to the database
@app.route('/api/save', methods=['POST'])
def save_data():
    data = request.json.get('data')
    if not data:
        return jsonify({'status': 'error', 'message': 'No data provided'}), 400

    try:
        conn = connection_pool.get_connection()
        cursor = conn.cursor()
        cursor.execute('INSERT INTO api_calls (data) VALUES (%s)', (data,))
        conn.commit()

        # Get the last inserted ID and the current timestamp
        cursor.execute('SELECT LAST_INSERT_ID(), NOW()')
        last_id = cursor.fetchone()[0]

        # Get the current EPOCH time
        epoch_time = int(time.time())

        # Generate a 7-character salt
        salt = base64.urlsafe_b64encode(os.urandom(16)).decode('utf-8')[:7]

        # Create the identifier
        identifier = f"{last_id}-{epoch_time}-{salt}"

        return jsonify({'status': 'success', 'message': f'Message enqueued: x_id={identifier}'}), 202
    except mysql.connector.Error as err:
        logging.error(f"Error: {err}")
        return jsonify({'status': 'error', 'message': 'Database error'}), 500
    finally:
        cursor.close()
        conn.close()

# Endpoint to retrieve and delete the oldest data (FIFO) or a specific record
@app.route('/api/deliver', methods=['GET'])
@ip_restricted
def deliver_data():
    x_id = request.args.get('x_id')

    try:
        conn = connection_pool.get_connection()
        cursor = conn.cursor(dictionary=True)

        if x_id:
            # Extract ID from the x_id
            parts = x_id.split('-')
            record_id = parts[0]  # The ID is the first part
            cursor.execute('SELECT * FROM api_calls WHERE id = %s', (record_id,))
        else:
            cursor.execute('SELECT * FROM api_calls ORDER BY timestamp ASC LIMIT 1')

        row = cursor.fetchone()
        if not row:
            return jsonify({'status': 'error', 'message': 'No data available'}), 404

        cursor.execute('DELETE FROM api_calls WHERE id = %s', (row['id'],))
        conn.commit()
        
        return jsonify({'data': row['data']}), 200

    except mysql.connector.Error as err:
        logging.error(f"Error: {err}")
        return jsonify({'status': 'error', 'message': 'Database error'}), 500
    finally:
        cursor.close()
        conn.close()

# Endpoint to log the response for a given x_id
# @app.route('/api/xlog', methods=['POST'])
# def xlog_response():
# PLACEHOLDER


@app.route('/api/status', methods=['GET'])
def get_status():
    x_id = request.args.get('x_id')
    if not x_id:
        return jsonify({'status': 'error', 'message': 'x_id is required'}), 400

    try:
        conn = connection_pool.get_connection()
        cursor = conn.cursor(dictionary=True)

        # Check if the response for the x_id is already logged
        # PLACEHOLDER
        
        # If not delivered, check the queue position
        parts = x_id.split('-')

        record_id = parts[0]  # The ID is the first part
        cursor.execute('SELECT id FROM api_calls WHERE id = %s', (record_id,))
        call_row = cursor.fetchone()

        cursor.execute('SELECT COUNT(*) AS queue_position FROM api_calls WHERE id <= %s', (record_id,))
        position_row = cursor.fetchone()
        if position_row is None:
            return jsonify({'status': 'queued', 'queue_position': 0}), 200

        queue_position = position_row['queue_position']

        return jsonify({'status': 'queued', 'queue_position': queue_position}), 200
    
    except mysql.connector.Error as err:
        logging.error(f"Error: {err}")
        return jsonify({'status': 'error', 'message': 'Database error'}), 500
    finally:
        cursor.close()
        conn.close()


# Custom error handler
@app.errorhandler(404)
def not_found_error(error):
    return jsonify({'status': 'error', 'message': 'Resource not found'}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({'status': 'error', 'message': 'Internal server error'}), 500

if __name__ == "__main__":
    app.run(debug=False)
