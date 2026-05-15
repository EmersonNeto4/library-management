from flask import request, jsonify
from db import get_connection
import hashlib
import functools

def check_auth(username, password):
    conn = get_connection()
    cur = conn.cursor()

    password_hash = hashlib.md5(password.encode()).hexdigest()

    cur.execute(
        "SELECT user_id FROM users WHERE username = %s AND password = %s",
        (username, password_hash)
    )

    user = cur.fetchone()
    if not user:
        cur.close()
        conn.close()
        return None

    user_id = user[0]

    cur.execute("SELECT users_user_id FROM admin WHERE users_user_id = %s", (user_id,))
    if cur.fetchone():
        role = 'admin'
    else:
        cur.execute("SELECT users_user_id FROM librarian WHERE users_user_id = %s", (user_id,))
        if cur.fetchone():
            role = 'librarian'
        else:
            role = 'reader'

    cur.close()
    conn.close()
    return (user_id, role)

def require_role(*roles):
    """Decorator que verifica autenticação e role a partir do body JSON."""
    def decorator(f):
        @functools.wraps(f)
        def wrapper(*args, **kwargs):
            data = request.get_json()
            if not data or "username" not in data or "password" not in data:
                return jsonify({"status": 401, "errors": "Credenciais em falta (username e password obrigatórios)"}), 401

            user = check_auth(data["username"], data["password"])
            if not user:
                return jsonify({"status": 401, "errors": "Credenciais inválidas"}), 401

            user_id, role = user
            if roles and role not in roles:
                return jsonify({"status": 403, "errors": "Sem permissão"}), 403

            return f(*args, user_id=user_id, role=role, **kwargs)
        return wrapper
    return decorator
