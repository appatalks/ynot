import os
import mysql.connector
from dotenv import load_dotenv

def init_db():
    conn = mysql.connector.connect(
        host=os.getenv('DB_HOST', ''),
        user=os.getenv('DB_USER', ''),
        password=os.getenv('DB_PASSWORD', ''),
        database=os.getenv('DB_NAME', '')
    )
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS api_calls (
            id INT AUTO_INCREMENT PRIMARY KEY,
            data TEXT NOT NULL,
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    conn.commit()
    conn.close()

if __name__ == "__main__":
    init_db()
