from flask import Blueprint, jsonify, request
from auth import require_role
from db import get_connection
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


# ── 11. GET /available_books_by_genre ────────────────────────────────────────
# Endpoint público — sem autenticação necessária.
@user_bp.route('/available_books_by_genre', methods=['GET'])
def available_books_by_genre():
    data = request.get_json()

    if not data or "genre_id" not in data:
        return make_response(400, errors="Campo obrigatório em falta: genre_id")

    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute("SELECT genre_id FROM genres WHERE genre_id = %s", (data["genre_id"],))
        if not cur.fetchone():
            return make_response(400, errors="Género não encontrado")

        cur.execute(
            """
            SELECT
                b.isbn,
                b.title,
                b.copies,
                b.copies - COUNT(l.loan_id) FILTER (
                    WHERE l.return_date IS NULL
                )                                                        AS available_copies,
                b.description,
                PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY r.rating)   AS raiting
            FROM books b
            JOIN books_genres bg ON bg.books_isbn       = b.isbn
            LEFT JOIN loans   l  ON l.books_isbn        = b.isbn
            LEFT JOIN reviews r  ON r.books_isbn        = b.isbn
            WHERE bg.genres_genre_id = %s
            GROUP BY b.isbn, b.title, b.copies, b.description
            HAVING b.copies - COUNT(l.loan_id) FILTER (
                WHERE l.return_date IS NULL
            ) > 0
            ORDER BY b.title
            """,
            (data["genre_id"],)
        )
        rows = cur.fetchall()
        results = [
            {
                "ISBN": row[0],
                "book_name": row[1],
                "copies": row[2],
                "available_copies": int(row[3]),
                "book_description": row[4],
                "raiting": float(row[5]) if row[5] is not None else None
            }
            for row in rows
        ]
        return make_response(200, results=results)
    except Exception as e:
        return make_response(500, errors=str(e))
    finally:
        cur.close()
        conn.close()


# ── 12. GET /check_book ───────────────────────────────────────────────────────
# Endpoint público — sem autenticação necessária.
@user_bp.route('/check_book', methods=['GET'])
def check_book():
    data = request.get_json()

    if not data or "ISBN" not in data:
        return make_response(400, errors="Campo obrigatório em falta: ISBN")

    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            """
            SELECT b.title, AVG(r.rating) AS overall_rating
            FROM books b
            LEFT JOIN reviews r ON r.books_isbn = b.isbn
            WHERE b.isbn = %s
            GROUP BY b.title
            """,
            (data["ISBN"],)
        )
        book_row = cur.fetchone()
        if not book_row:
            return make_response(400, errors="Livro não encontrado")

        title, overall_rating = book_row

        cur.execute(
            """
            SELECT rating, comment
            FROM reviews
            WHERE books_isbn = %s
            ORDER BY review_date DESC
            """,
            (data["ISBN"],)
        )
        reviews = [
            {"rating": row[0], "comment": row[1]}
            for row in cur.fetchall()
        ]

        result = {
            "ISBN": data["ISBN"],
            "book_name": title,
            "overall_rating": float(overall_rating) if overall_rating is not None else None,
            "reviews": reviews
        }
        return make_response(200, results=[result])
    except Exception as e:
        return make_response(500, errors=str(e))
    finally:
        cur.close()
        conn.close()
