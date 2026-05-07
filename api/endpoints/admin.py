from flask import Blueprint, jsonify, request
from auth import require_role
from db import get_connection

admin_bp = Blueprint('admin', __name__)

def make_response(status, results=None, errors=None):
    body = {"status": status}
    if errors is not None:
        body["errors"] = errors
    if results is not None:
        body["results"] = results
    return jsonify(body), status


# ── 2. POST /book ─────────────────────────────────────────────────────────────
@admin_bp.route('/book', methods=['POST'])
@require_role('admin')
def add_book(user_id, role):
    data = request.get_json()

    required = ["ISBN", "book_name", "author", "book_description", "pages", "copies", "genres"]
    for field in required:
        if field not in data:
            return make_response(400, errors=f"Campo obrigatório em falta: {field}")

    if not isinstance(data["genres"], list) or len(data["genres"]) == 0:
        return make_response(400, errors="É necessário pelo menos um género")

    if data["copies"] < 1:
        return make_response(400, errors="É necessário adicionar pelo menos uma cópia")

    if data["pages"] <= 0:
        return make_response(400, errors="O número de páginas deve ser maior que 0")

    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute("SELECT isbn FROM books WHERE isbn = %s", (data["ISBN"],))
        if cur.fetchone():
            return make_response(400, errors="Livro com este ISBN já existe")

        cur.execute(
            """
            INSERT INTO books (isbn, title, description, pages, copies)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (data["ISBN"], data["book_name"], data["book_description"],
             data["pages"], data["copies"])
        )

        # Géneros
        for genre in data["genres"]:
            cur.execute("SELECT genre_id FROM genres WHERE genre_name = %s", (genre,))
            row = cur.fetchone()
            if not row:
                conn.rollback()
                return make_response(400, errors=f"Género não encontrado: {genre}")
            cur.execute(
                "INSERT INTO books_genres (books_isbn, genres_genre_id) VALUES (%s, %s)",
                (data["ISBN"], row[0])
            )

        # Autores (string separada por vírgula)
        for author_name in data["author"].split(","):
            author_name = author_name.strip()
            cur.execute("SELECT author_id FROM author WHERE name = %s", (author_name,))
            row = cur.fetchone()
            if row:
                author_id = row[0]
            else:
                cur.execute(
                    "INSERT INTO author (name) VALUES (%s) RETURNING author_id",
                    (author_name,)
                )
                author_id = cur.fetchone()[0]
            cur.execute(
                "INSERT INTO author_books (author_author_id, books_isbn) VALUES (%s, %s)",
                (author_id, data["ISBN"])
            )

        conn.commit()
        return make_response(200, results=data["ISBN"])
    except Exception as e:
        conn.rollback()
        return make_response(500, errors=str(e))
    finally:
        cur.close()
        conn.close()


# ── 3. PUT /update_copies ─────────────────────────────────────────────────────
@admin_bp.route('/update_copies', methods=['PUT'])
@require_role('admin')
def update_copies(user_id, role):
    data = request.get_json()

    required = ["ISBN", "copies"]
    for field in required:
        if field not in data:
            return make_response(400, errors=f"Campo obrigatório em falta: {field}")

    if data["copies"] < 0:
        return make_response(400, errors="O número de cópias não pode ser negativo")

    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute("SELECT copies FROM books WHERE isbn = %s", (data["ISBN"],))
        book = cur.fetchone()
        if not book:
            return make_response(400, errors="Livro não encontrado")

        # Contar cópias actualmente em empréstimo
        cur.execute(
            """
            SELECT COUNT(*) FROM loans
            WHERE books_isbn = %s AND return_date IS NULL
            """,
            (data["ISBN"],)
        )
        on_loan = cur.fetchone()[0]

        if data["copies"] < on_loan:
            return make_response(
                400,
                errors=f"Não é possível reduzir abaixo do número de cópias em empréstimo ({on_loan})"
            )

        cur.execute(
            "UPDATE books SET copies = %s WHERE isbn = %s",
            (data["copies"], data["ISBN"])
        )
        conn.commit()
        return make_response(200, results=data["ISBN"])
    except Exception as e:
        conn.rollback()
        return make_response(500, errors=str(e))
    finally:
        cur.close()
        conn.close()