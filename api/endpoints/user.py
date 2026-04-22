from flask import Blueprint, jsonify, request
from ..auth import require_role
from ..db import get_connection
import hashlib

user_bp = Blueprint('user', __name__)

def make_response(status, results=None, errors=None):
    body = {"status": status}
    if errors is not None:
        body["errors"] = errors
    if results is not None:
        body["results"] = results
    return jsonify(body), status


# ── 1. POST /user ────────────────────────────────────────────────────────────
# Endpoint público — qualquer pessoa pode registar-se como reader ou librarian.
# Admins são inseridos diretamente na base de dados.
@user_bp.route('/user', methods=['POST'])
def register_user():
    data = request.get_json()

    required = ["username", "email", "password", "role"]
    for field in required:
        if field not in data:
            return make_response(400, errors=f"Campo obrigatório em falta: {field}")

    new_role = data['role']
    if new_role not in ['librarian', 'reader']:
        return make_response(400, errors="Role inválido. Use: librarian ou reader")

    if new_role == "librarian" and "n_mec" not in data:
        return make_response(400, errors="Campo obrigatório em falta: n_mec")
    if new_role == "reader" and "n_estudante" not in data:
        return make_response(400, errors="Campo obrigatório em falta: n_estudante")

    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute("SELECT user_id FROM users WHERE username = %s", (data["username"],))
        if cur.fetchone():
            return make_response(400, errors="Username já existe")

        cur.execute("SELECT user_id FROM users WHERE email = %s", (data["email"],))
        if cur.fetchone():
            return make_response(400, errors="Email já existe")

        password_hash = hashlib.md5(data["password"].encode()).hexdigest()
        cur.execute(
            "INSERT INTO users (username, email, password) VALUES (%s, %s, %s) RETURNING user_id",
            (data["username"], data["email"], password_hash)
        )
        new_user_id = cur.fetchone()[0]

        if new_role == "librarian":
            cur.execute(
                "INSERT INTO librarian (users_user_id, n_mec) VALUES (%s, %s)",
                (new_user_id, data["n_mec"])
            )
        else:
            cur.execute(
                "INSERT INTO reader (users_user_id, n_estudante) VALUES (%s, %s)",
                (new_user_id, data["n_estudante"])
            )

        conn.commit()
        return make_response(200, results=new_user_id)
    except Exception as e:
        conn.rollback()
        return make_response(500, errors=str(e))
    finally:
        cur.close()
        conn.close()
