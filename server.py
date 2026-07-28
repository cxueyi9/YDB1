from flask import Flask, request, render_template_string, jsonify, redirect, url_for
import sqlite3

app = Flask(__name__)
DATABASE = 'logs.db'

def get_db():
    conn = sqlite3.connect(DATABASE)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    with app.app_context():
        db = get_db()
        db.execute('''
            CREATE TABLE IF NOT EXISTS records (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                idx INTEGER NOT NULL,
                total INTEGER NOT NULL,
                account TEXT NOT NULL,
                time TEXT NOT NULL,
                device TEXT NOT NULL
            )
        ''')
        db.commit()

@app.route('/upload', methods=['POST'])
def upload():
    data = request.get_json()
    if not data or not isinstance(data, list):
        return jsonify({"status": "error", "msg": "invalid data"}), 400
    db = get_db()
    try:
        for record in data:
            db.execute(
                "INSERT INTO records (idx, total, account, time, device) VALUES (?, ?, ?, ?, ?)",
                (record['index'], record['total'], record['account'], record['time'], record['device'])
            )
        db.commit()
        return jsonify({"status": "ok", "count": len(data)})
    except Exception as e:
        return jsonify({"status": "error", "msg": str(e)}), 500

@app.route('/', methods=['GET', 'POST'])
def index():
    db = get_db()
    if request.method == 'POST':
        # 批量删除
        ids = request.form.getlist('delete_ids')
        if ids:
            placeholders = ','.join('?' for _ in ids)
            db.execute(f"DELETE FROM records WHERE id IN ({placeholders})", ids)
            db.commit()
        return redirect(url_for('index'))

    account_filter = request.args.get('account', '')
    time_filter = request.args.get('time', '')
    query = "SELECT * FROM records WHERE 1=1"
    params = []
    if account_filter:
        query += " AND account LIKE ?"
        params.append(f'%{account_filter}%')
    if time_filter:
        query += " AND time LIKE ?"
        params.append(f'%{time_filter}%')
    query += " ORDER BY id DESC LIMIT 500"
    records = db.execute(query, params).fetchall()
    return render_template_string(HTML_TEMPLATE, records=records)

HTML_TEMPLATE = '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>填充日志</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: center; }
        th { background-color: #f2f2f2; }
        .filter { margin-bottom: 10px; }
        .filter input { padding: 5px; margin-right: 10px; }
    </style>
</head>
<body>
    <h2>日志列表</h2>
    <div class="filter">
        <form method="get">
            账号筛选: <input type="text" name="account" value="{{ request.args.get('account', '') }}" placeholder="输入账号">
            时间筛选: <input type="text" name="time" value="{{ request.args.get('time', '') }}" placeholder="2026/7/27">
            <button type="submit">筛选</button>
            <a href="/">清除</a>
        </form>
    </div>
    <form method="post" onsubmit="return confirm('确定删除选中的记录吗？');">
        <table>
            <tr>
                <th><input type="checkbox" id="selectAll" onclick="toggleCheckboxes(this)"></th>
                <th>序号</th>
                <th>顺序</th>
                <th>账号</th>
                <th>时间</th>
                <th>本机标识</th>
                <th>总数</th>
            </tr>
            {% for r in records %}
            <tr>
                <td><input type="checkbox" name="delete_ids" value="{{ r['id'] }}"></td>
                <td>{{ r['id'] }}</td>
                <td>{{ r['idx'] }}/{{ r['total'] }}</td>
                <td>{{ r['account'] }}</td>
                <td>{{ r['time'] }}</td>
                <td>{{ r['device'][-6:] if r['device']|length > 6 else r['device'] }}</td>
                <td>{{ r['total'] }}</td>
            </tr>
            {% endfor %}
        </table>
        <br>
        <button type="submit">删除选中记录</button>
    </form>
    <script>
        function toggleCheckboxes(source) {
            const checkboxes = document.getElementsByName('delete_ids');
            for (let cb of checkboxes) cb.checked = source.checked;
        }
    </script>
</body>
</html>
'''

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000, debug=True)