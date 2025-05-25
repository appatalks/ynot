import os
from flask import Flask, request, jsonify
import mysql.connector
from mysql.connector import pooling
import logging

app = Flask(__name__)

# Load environment variables
DB_HOST = os.getenv('DB_HOST', 'localhost')
DB_USER = os.getenv('DB_USER', 'api_gateway')
# DB_PASSWORD = os.getenv('DB_PASSWORD', 'your_mysql_password')
DB_NAME = os.getenv('DB_NAME', 'api_gateway_fifo')
SSL_CERT_PATH = os.getenv('SSL_CERT_PATH', 'cert.pem')
SSL_KEY_PATH = os.getenv('SSL_KEY_PATH', 'key.pem')

# Configure logging
logging.basicConfig(level=logging.INFO)

# Setup MySQL connection pooling
dbconfig = {
    "host": DB_HOST,
    "user": DB_USER,
    # "password": DB_PASSWORD,
    "database": DB_NAME
}
connection_pool = pooling.MySQLConnectionPool(pool_name="apipool",
                                              pool_size=32,
                                              **dbconfig)

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
        return jsonify({'status': 'success'}), 201
    except mysql.connector.Error as err:
        logging.error(f"Error: {err}")
        return jsonify({'status': 'error', 'message': 'Database error'}), 500
    finally:
        cursor.close()
        conn.close()

# Endpoint to retrieve and delete the oldest data (FIFO)
@app.route('/api/deliver', methods=['GET'])
def deliver_data():
    try:
        conn = connection_pool.get_connection()
        cursor = conn.cursor(dictionary=True)
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

# Custom error handler
@app.errorhandler(404)
def not_found_error(error):
    return jsonify({'status': 'error', 'message': 'Resource not found'}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({'status': 'error', 'message': 'Internal server error'}), 500

if __name__ == "__main__":
    context = (SSL_CERT_PATH, SSL_KEY_PATH)
    app.run(debug=False, ssl_context=context)
