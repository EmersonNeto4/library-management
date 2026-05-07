from flask import Blueprint, jsonify, request
from auth import require_role
from db import get_connection

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

    if not data or "genre_id" not in data:
        return make_response(400, errors="Campo obrigatório em falta: genre_id")

    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute("SELECT genre_id FROM genres WHERE genre_id = %s", (data["genre_id"],))
        if not cur.fetchone():
            return make_response(400, errors="Género não encontrado")

        results = _fetch_books(
            cur,
            "WHERE b.isbn IN (SELECT books_isbn FROM books_genres WHERE genres_genre_id = %s)",
            (data["genre_id"],)
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
            "WHERE b.title ILIKE %s",
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


# ── 7. GET /loaned_books ─────────────────────────────────────────────────────
@librarian_bp.route('/loaned_books', methods=['GET'])
@require_role('admin', 'librarian')
def loaned_books(user_id, role):
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            """
            SELECT b.isbn, b.title, u.user_id, u.username, l.loan_date
            FROM loans l
            JOIN books b ON b.isbn = l.books_isbn
            JOIN users u ON u.user_id = l.users_user_id
            WHERE l.return_date IS NULL
            ORDER BY l.loan_date
            """
        )
        rows = cur.fetchall()
        results = [
            {
                "ISBN": row[0],
                "book_name": row[1],
                "loaner_id": row[2],
                "loaner_name": row[3],
                "loan_date": str(row[4])
            }
            for row in rows
        ]
        return make_response(200, results=results)
    except Exception as e:
        return make_response(500, errors=str(e))
    finally:
        cur.close()
        conn.close()


# ── 8. GET /loaned_book ───────────────────────────────────────────────────────
@librarian_bp.route('/loaned_book', methods=['GET'])
@require_role('admin', 'librarian')
def loaned_book(user_id, role):
    data = request.get_json()

    if not data or "ISBN" not in data:
        return make_response(400, errors="Campo obrigatório em falta: ISBN")

    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute("SELECT isbn FROM books WHERE isbn = %s", (data["ISBN"],))
        if not cur.fetchone():
            return make_response(400, errors="Livro não encontrado")

        cur.execute(
            """
            SELECT u.user_id, u.username, l.loan_date
            FROM loans l
            JOIN users u ON u.user_id = l.users_user_id
            WHERE l.books_isbn = %s
            ORDER BY l.loan_date DESC
            """,
            (data["ISBN"],)
        )
        rows = cur.fetchall()
        results = [
            {
                "loaner_id": row[0],
                "loaner_name": row[1],
                "loan_date": str(row[2])
            }
            for row in rows
        ]
        return make_response(200, results=results)
    except Exception as e:
        return make_response(500, errors=str(e))
    finally:
        cur.close()
        conn.close()


# ── 9. GET /TopLoanedBooks/<N> ────────────────────────────────────────────────
@librarian_bp.route('/TopLoanedBooks/<int:n>', methods=['GET'])
@require_role('admin', 'librarian')
def top_loaned_books(user_id, role, n):
    if n < 1:
        return make_response(400, errors="N deve ser maior que 0")

    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            """
            SELECT b.isbn, b.title, COUNT(l.loan_id) AS loaned_times, MAX(l.loan_date) AS last_loaned
            FROM books b
            JOIN loans l ON l.books_isbn = b.isbn
            GROUP BY b.isbn, b.title
            ORDER BY loaned_times DESC
            LIMIT %s
            """,
            (n,)
        )
        rows = cur.fetchall()
        results = [
            {
                "ISBN": row[0],
                "book_name": row[1],
                "loaned_times": row[2],
                "last_loaned": str(row[3]),
                "rank": rank
            }
            for rank, row in enumerate(rows, start=1)
        ]
        return make_response(200, results=results)
    except Exception as e:
        return make_response(500, errors=str(e))
    finally:
        cur.close()
        conn.close()


# ── 10. GET /TopLoaners/<N> ───────────────────────────────────────────────────
@librarian_bp.route('/TopLoaners/<int:n>', methods=['GET'])
@require_role('admin', 'librarian')
def top_loaners(user_id, role, n):
    if n < 1:
        return make_response(400, errors="N deve ser maior que 0")

    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            """
            SELECT
                u.user_id,
                u.username,
                COUNT(l.loan_id)          AS loaned_books_quantity,
                ARRAY_AGG(DISTINCT b.title) AS loaned_books,
                MAX(l.loan_date)           AS last_loaned_book_date,
                (
                    SELECT b2.title
                    FROM loans l2
                    JOIN books b2 ON b2.isbn = l2.books_isbn
                    WHERE l2.users_user_id = u.user_id
                    ORDER BY l2.loan_date DESC
                    LIMIT 1
                ) AS last_loaned_book
            FROM users u
            JOIN loans l ON l.users_user_id = u.user_id
            JOIN books b ON b.isbn = l.books_isbn
            GROUP BY u.user_id, u.username
            ORDER BY loaned_books_quantity DESC
            LIMIT %s
            """,
            (n,)
        )
        rows = cur.fetchall()
        results = [
            {
                "loaner_id": row[0],
                "loaner_name": row[1],
                "loaned_books_quantity": row[2],
                "loaned_books": row[3],
                "last_loaned_book_date": str(row[4]),
                "last_loaned_book": row[5]
            }
            for row in rows
        ]
        return make_response(200, results=results)
    except Exception as e:
        return make_response(500, errors=str(e))
    finally:
        cur.close()
        conn.close()


# ── 16. GET /report/TopLoanedGenres12Months/<N> ───────────────────────────────
@librarian_bp.route('/report/TopLoanedGenres12Months/<int:n>', methods=['GET'])
@require_role('admin', 'librarian')
def top_loaned_genres_12_months(user_id, role, n):
    if n < 1:
        return make_response(400, errors="N deve ser maior que 0")

    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            """
            SELECT g.genre_name, COUNT(l.loan_id) AS borrow_count
            FROM loans l
            JOIN books_genres bg ON bg.books_isbn      = l.books_isbn
            JOIN genres       g  ON g.genre_id         = bg.genres_genre_id
            WHERE l.loan_date >= CURRENT_DATE - INTERVAL '12 months'
            GROUP BY g.genre_id, g.genre_name
            ORDER BY borrow_count DESC
            LIMIT %s
            """,
            (n,)
        )
        rows = cur.fetchall()
        results = [
            {"genre": row[0], "borrow_count": row[1]}
            for row in rows
        ]
        return make_response(200, results=results)
    except Exception as e:
        return make_response(500, errors=str(e))
    finally:
        cur.close()
        conn.close()