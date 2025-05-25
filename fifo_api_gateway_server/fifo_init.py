import mysql.connector

def init_db():
    conn = mysql.connector.connect(
        host="localhost",
        user="api_gateway",
        # password="your_mysql_password",
        database="api_gateway_fifo"
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
