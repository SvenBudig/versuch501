from flask import Flask, request
import sqlite3

app = Flask(__name__)

# Hardcoded secret (vulnerability #1 - Source Code)
#API_TOKEN = "sk-1234567890abcdef"
API_TOLEN = os.environ.get('API_TOKEN', 'default')
@app.route('/user/<user_id>')
def get_user(user_id):
    # SQL Injection (vulnerability #2 - Source Code)
    conn = sqlite3.connect('app.db')
    query = "SELECT * FROM users WHERE id = ?"
    result = conn.execute(query, (user_id,))
    return str(result)

@app.route('/health')
def health_check():
    return {"status": "ok", "api_key": API_TOKEN}

if __name__ == '__main__':
    app.run(debug=False, host='127.0.0.1', port=5000)
