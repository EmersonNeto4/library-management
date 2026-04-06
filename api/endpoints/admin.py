from flask import Blueprint, jsonify, request
from ..auth import require_role
from ..db import get_connection
import hashlib

admin_bp = Blueprint('admin', __name__)

@admin_bp.route('/user', methods=['POST'])
@require_role('admin')
def register_user(user_id, role):
    data = request.get_json()

    # Validar campos obrigatórios
    required = ["username", "email", "password", "role"]

    for field in required:
        if field not in data:
            return jsonify({'error': f'Campo obrigatório em falta: {field}'}), 400
        
    new_role = data['role']
    if new_role not in ['admin', 'librarian', 'reader']:
        return jsonify({'error': 'Papél inválido. Use: admin, librarian ou reader'}), 400
    
    # validar campos específicos por role
    if new_role ==  "librarian" and "n_mec" not in data:
        return jsonify({"error": "Campo obrigatório em falta: n_mec"}), 400
    if new_role  == "reader" and "n_estudante" not in data:
        return jsonify({"error": "Campo obrigatório em falta: n_estudante"}), 400
    if new_role == "admin" and "admin_level" not in data:
        return jsonify({"error": "Campo obrigatório em falta: admin_level"}), 400
    
    conn = get_connection()
    cur = conn.cursor()

    try:
        # verificar se username já existe
        cur.execute("SELECT user_id FROM users WHERE username = %s", (data["username"],))
        if cur.fetchone():
            return jsonify({'error': 'Username já existe'}), 409
        
        # verificar se email já existe
        cur.execute("SELECT user_id FROM users WHERE email = %s", (data["email"],))
        if cur.fetchone():
            return jsonify({'error': 'Email já existe'}), 409
        
        password_hash = hashlib.md5(data["password"].encode()).hexdigest()

        # inserir em users
        cur.execute(
            """
            INSERT INTO users (username, email, password, created_at)
            VALUES (%s, %s, %s, NOW())
            RETURNING user_id
            """,
            (data["username"], data["email"], password_hash)
        )
        new_user_id = cur.fetchone()[0]

        # inserir na tabela descendente
        if new_role == "admin":
            cur.execute(
                "INSERT INTO admin (users_user_id, admin_level) VALUES (%s, %s)",
                (new_user_id, data["admin_level"])
            )
        elif new_role == "librarian":
            cur.execute(
                "INSERT INTO librarian (users_user_id, n_mec) VALUES (%s, %s)",
                (new_user_id, data["n_mec"])
            )
        else: # reader
            cur.execute(
                "INSERT INTO reader (users_user_id, n_estudante) VALUES (%s, %s)",
                (new_user_id, data["n_estudante"])
            )

        conn.commit()
        return jsonify({"message": "Usuário criado com sucesso", 
                        "user_id": new_user_id,
                        "role": new_role
                        }), 201
    except Exception as e:
        conn.rollback()
        return jsonify({'error': str(e)}), 500
    finally:
        cur.close()
        conn.close()

@admin_bp.route('/book', methods=['POST'])
@require_role('admin')
def add_book(user_id, role):
    data = request.get_json()

    # Validar campos obrigatórios
    required = ["isbn","title", "author", "description", "pages", "copies", "genres"]

    for field in required:
        if field not in data:
            return jsonify({'error': f'Campo obrigatório em falta: {field}'}), 400
        
    conn = get_connection()
    cur = conn.cursor()

    try:
        # Verificar se o livro já existe
        cur.execute("SELECT isbn FROM books WHERE isbn = %s", (data["isbn"],))
        if cur.fetchone():
            return jsonify({'error': 'Livro com este ISBN já existe'}), 409
        
        # Inserir o livro
        cur.execute(
            """
            INSERT INTO books (isbn, title, description, pages, copies)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (data["isbn"], data["title"], data["description"], data["pages"], data["copies"])
        )

        # Inserir os gêneros do livro
        for genre in data["genres"]:
            cur.execute( 
                "SELECT genre_id FROM genres WHERE genre_name = %s",
                (genre,)
            )
            genre_id = cur.fetchone()
            if not genre_id:
                return jsonify({'error': f'Gênero não encontrado: {genre}'}), 400
            cur.execute(
                "INSERT INTO books_genres (books_isbn, genres_genre_id) VALUES (%s, %s)",
                (data["isbn"], genre_id[0])
            )
        
        # Inserir os autores do livro
        for author in data["author"].split(","):
            author = author.strip()
            cur.execute(
                "SELECT author_id FROM author WHERE name = %s",
                (author,)
            )
            author_id = cur.fetchone()
            if not author_id:
                cur.execute(
                    "INSERT INTO author (name) VALUES (%s) RETURNING author_id",
                    (author,)
                )
                author_id = cur.fetchone()[0]
            else:
                author_id = author_id[0]
            cur.execute(
                "INSERT INTO author_books (author_author_id, books_isbn) VALUES (%s, %s)",
                (author_id, data["isbn"])
            )
        
        conn.commit()
        return jsonify({"message": "Livro adicionado com sucesso", "isbn": data["isbn"]}), 201
    except Exception as e:
        conn.rollback()
        return jsonify({'error': str(e)}), 500
    finally:
        cur.close()
        conn.close()