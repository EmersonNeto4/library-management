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
# Qualquer utilizador autenticado (admin, librarian ou reader).
@user_bp.route('/available_books_by_genre', methods=['GET'])
@require_role('admin', 'librarian', 'reader')
def available_books_by_genre(user_id, role):
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
                AVG(r.rating)                                            AS raiting
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
# Qualquer utilizador autenticado (admin, librarian ou reader).
@user_bp.route('/check_book', methods=['GET'])
@require_role('admin', 'librarian', 'reader')
def check_book(user_id, role):
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


# ── 13. POST /borrow_book ─────────────────────────────────────────────────────
# Qualquer utilizador autenticado pode pedir empréstimo.
#
# Estratégia de concorrência: SELECT FOR UPDATE
#   Ao bloquear a linha do livro com FOR UPDATE, garantimos que apenas uma
#   transação de cada vez pode verificar e registar um empréstimo para o mesmo
#   livro. Qualquer outra transação concorrente fica em espera até que a
#   primeira faça COMMIT ou ROLLBACK. Desta forma, o par "verificar cópias
#   disponíveis → inserir empréstimo" é atómico e nunca resulta em
#   available_copies negativo.
@user_bp.route('/borrow_book', methods=['POST'])
@require_role('admin', 'librarian', 'reader')
def borrow_book(user_id, role):
    data = request.get_json()

    if not data or "user_id" not in data or "ISBN" not in data:
        return make_response(400, errors="Campos obrigatórios em falta: user_id, ISBN")

    borrower_id = data["user_id"]
    isbn = data["ISBN"]

    conn = get_connection()
    cur = conn.cursor()
    try:
        # Passo 1 — bloquear a linha do livro (FOR UPDATE).
        # Transações concorrentes para o mesmo ISBN ficam em espera aqui até
        # esta transação terminar, eliminando a race condition nas cópias.
        cur.execute(
            "SELECT copies FROM books WHERE isbn = %s FOR UPDATE",
            (isbn,)
        )
        book_row = cur.fetchone()
        if not book_row:
            conn.rollback()
            return make_response(400, errors="Livro não encontrado")

        copies = book_row[0]

        # Passo 2 — calcular cópias disponíveis depois de adquirir o lock.
        # Lê apenas empréstimos committed (READ COMMITTED por defeito no PostgreSQL),
        # pelo que inclui empréstimos registados por transações que já fizeram commit.
        cur.execute(
            "SELECT COUNT(*) FROM loans WHERE books_isbn = %s AND return_date IS NULL",
            (isbn,)
        )
        active_book_loans = cur.fetchone()[0]
        available_copies = copies - active_book_loans

        if available_copies <= 0:
            conn.rollback()
            return make_response(400, errors="Sem cópias disponíveis para empréstimo")

        # Passo 3 — verificar limite de 5 livros simultâneos por utilizador.
        cur.execute(
            "SELECT COUNT(*) FROM loans WHERE users_user_id = %s AND return_date IS NULL",
            (borrower_id,)
        )
        if cur.fetchone()[0] >= 5:
            conn.rollback()
            return make_response(400, errors="Limite de 5 livros emprestados em simultâneo atingido")

        # Passo 4 — verificar se o utilizador já tem este livro emprestado.
        # A constraint unique_active_loan na BD também impede isto, mas assim
        # devolvemos uma mensagem de erro clara em vez de um erro de constraint.
        cur.execute(
            "SELECT loan_id FROM loans WHERE users_user_id = %s AND books_isbn = %s AND return_date IS NULL",
            (borrower_id, isbn)
        )
        if cur.fetchone():
            conn.rollback()
            return make_response(400, errors="Utilizador já tem este livro emprestado")

        # Passo 5 — registar o empréstimo e libertar o lock.
        cur.execute(
            "INSERT INTO loans (books_isbn, users_user_id) VALUES (%s, %s)",
            (isbn, borrower_id)
        )
        conn.commit()
        return make_response(200, results=isbn)
    except Exception as e:
        conn.rollback()
        return make_response(500, errors=str(e))
    finally:
        cur.close()
        conn.close()


# ── 14. POST /report/submit_review ───────────────────────────────────────────
# Qualquer utilizador autenticado que já tenha emprestado o livro (histórico).
# Upsert: INSERT se não existe review; UPDATE se já existe.
@user_bp.route('/report/submit_review', methods=['POST'])
@require_role('admin', 'librarian', 'reader')
def submit_review(user_id, role):
    data = request.get_json()

    required = ["user_id", "ISBN", "rating", "comment"]
    if not data or any(f not in data for f in required):
        missing = [f for f in required if not data or f not in data]
        return make_response(400, errors=f"Campos obrigatórios em falta: {', '.join(missing)}")

    reviewer_id = data["user_id"]
    isbn = data["ISBN"]
    rating = data["rating"]
    comment = data["comment"]

    if not isinstance(rating, int) or not (1 <= rating <= 5):
        return make_response(400, errors="rating deve ser um inteiro entre 1 e 5")

    conn = get_connection()
    cur = conn.cursor()
    try:
        # Verificar se o livro existe
        cur.execute("SELECT isbn FROM books WHERE isbn = %s", (isbn,))
        if not cur.fetchone():
            return make_response(400, errors="Livro não encontrado")

        # Verificar se o utilizador já emprestou este livro (histórico — não
        # apenas empréstimos activos, pois pode ter devolvido e querer avaliar)
        cur.execute(
            "SELECT loan_id FROM loans WHERE users_user_id = %s AND books_isbn = %s LIMIT 1",
            (reviewer_id, isbn)
        )
        if not cur.fetchone():
            return make_response(400, errors="Utilizador não tem histórico de empréstimo para este livro")

        # Upsert: INSERT se não existe; UPDATE se já existe (conflito na PK).
        # ON CONFLICT actua sobre a PRIMARY KEY (books_isbn, users_user_id).
        cur.execute(
            """
            INSERT INTO reviews (rating, comment, books_isbn, users_user_id)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (books_isbn, users_user_id)
            DO UPDATE SET
                rating      = EXCLUDED.rating,
                comment     = EXCLUDED.comment,
                review_date = NOW()
            """,
            (rating, comment, isbn, reviewer_id)
        )
        conn.commit()
        return make_response(200, results=isbn)
    except Exception as e:
        conn.rollback()
        return make_response(500, errors=str(e))
    finally:
        cur.close()
        conn.close()


# ── 15. POST /return_book ─────────────────────────────────────────────────────
# Qualquer utilizador autenticado pode devolver um livro que tenha emprestado.
# O registo de empréstimo é mantido na BD (return_date preenchido, não apagado).
@user_bp.route('/return_book', methods=['POST'])
@require_role('admin', 'librarian', 'reader')
def return_book(user_id, role):
    data = request.get_json()

    if not data or "user_id" not in data or "ISBN" not in data:
        return make_response(400, errors="Campos obrigatórios em falta: user_id, ISBN")

    borrower_id = data["user_id"]
    isbn = data["ISBN"]

    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            "SELECT loan_id FROM loans WHERE users_user_id = %s AND books_isbn = %s AND return_date IS NULL",
            (borrower_id, isbn)
        )
        loan_row = cur.fetchone()
        if not loan_row:
            return make_response(400, errors="Empréstimo activo não encontrado para este utilizador e livro")

        cur.execute(
            "UPDATE loans SET return_date = CURRENT_DATE WHERE loan_id = %s",
            (loan_row[0],)
        )
        conn.commit()
        return make_response(200, results=borrower_id)
    except Exception as e:
        conn.rollback()
        return make_response(500, errors=str(e))
    finally:
        cur.close()
        conn.close()
