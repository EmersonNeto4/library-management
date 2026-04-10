from flask import Blueprint, jsonify, request
from ..auth import require_role
from ..db import get_connection

librarian_bp = Blueprint('librarian', __name__)

def make_response(status, results=None, errors=None):
    body = {"status": status}
    if errors is not None:
        body["errors"] = errors
    if results is not None:
        body["results"] = results
    return jsonify(body), status


# ── Query auxiliar reutilizável ──────────────────────────────────────────────
# Devolve livros com autor agregado, cópias disponíveis e géneros agregados.
# O parâmetro WHERE é injectado pelo chamador.

def _fetch_books(cur, where_clause, params):
    """
    Executa a query de livros com o WHERE indicado.
    Devolve lista de dicts com: ISBN, book_name, author, pages,
    copies, available_copies, genres.
    """
    cur.execute(
        f"""
        SELECT
            b.isbn,
            b.title,
            ARRAY_AGG(DISTINCT a.name)       AS author,
            b.pages,
            b.copies,
            b.copies - COUNT(l.loan_id) FILTER (
                WHERE l.return_date IS NULL
            )                                AS available_copies,
            ARRAY_AGG(DISTINCT g.genre_name) AS genres
        FROM books b
        JOIN books_genres bg ON bg.books_isbn = b.isbn
        JOIN genres       g  ON g.genre_id    = bg.genres_genre_id
        JOIN author_books ab ON ab.books_isbn  = b.isbn
        JOIN author       a  ON a.author_id    = ab.author_author_id
        LEFT JOIN loans   l  ON l.books_isbn   = b.isbn
        {where_clause}
        GROUP BY b.isbn, b.title, b.pages, b.copies
        ORDER BY b.title
        """,
        params
    )
    rows = cur.fetchall()
    results = []
    for row in rows:
        isbn, title, author, pages, copies, available_copies, genres = row
        results.append({
            "ISBN": isbn,
            "book_name": title,
            "author": author,
            "pages": pages,
            "copies": copies,
            "available_copies": available_copies,
            "genres": genres if genres else []
        })
    return results


# ── 4. GET /list_books_by_genre ──────────────────────────────────────────────
@librarian_bp.route('/list_books_by_genre', methods=['GET'])
@require_role('admin', 'librarian')
def list_books_by_genre(user_id, role):
    data = request.get_json()

    if not data or "genre_name" not in data:
        return make_response(400, errors="Campo obrigatório em falta: genre_name")

    conn = get_connection()
    cur = conn.cursor()
    try:
        # Verificar se o género existe e obter o seu ID
        cur.execute("SELECT genre_id FROM genres WHERE LOWER(genre_name) = LOWER(%s)", (data["genre_name"],))
        row = cur.fetchone()
        if not row:
            return make_response(400, errors="Género não encontrado")
        genre_id = row[0]

        results = _fetch_books(
            cur,
            "WHERE b.isbn IN (SELECT books_isbn FROM books_genres WHERE genres_genre_id = %s)",
            (genre_id,)
        )
        return make_response(200, results=results)
    except Exception as e:
        return make_response(500, errors=str(e))
    finally:
        cur.close()
        conn.close()


# ── 5. GET /find_book_by_name ────────────────────────────────────────────────
@librarian_bp.route('/find_book_by_name', methods=['GET'])
@require_role('admin', 'librarian')
def find_book_by_name(user_id, role):
    data = request.get_json()

    if not data or "book_name" not in data:
        return make_response(400, errors="Campo obrigatório em falta: book_name")

    conn = get_connection()
    cur = conn.cursor()
    try:
        results = _fetch_books(
            cur,
            "WHERE LOWER(b.title) LIKE LOWER(%s)",
            (f"%{data['book_name']}%",)
        )
        if not results:
            return make_response(400, errors="Nenhum livro encontrado com esse nome")
        return make_response(200, results=results)
    except Exception as e:
        return make_response(500, errors=str(e))
    finally:
        cur.close()
        conn.close()


# ── 6. GET /find_book_by_isbn ────────────────────────────────────────────────
@librarian_bp.route('/find_book_by_isbn', methods=['GET'])
@require_role('admin', 'librarian')
def find_book_by_isbn(user_id, role):
    data = request.get_json()

    if not data or "ISBN" not in data:
        return make_response(400, errors="Campo obrigatório em falta: ISBN")

    conn = get_connection()
    cur = conn.cursor()
    try:
        results = _fetch_books(
            cur,
            "WHERE b.isbn = %s",
            (data["ISBN"],)
        )
        if not results:
            return make_response(400, errors="Livro não encontrado")
        return make_response(200, results=results)
    except Exception as e:
        return make_response(500, errors=str(e))
    finally:
        cur.close()
        conn.close()
