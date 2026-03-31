from flask import request, jsonify
from .db import get_db_connection
import hashlib
import functools

def check_auth(username, password):
    conn = get_db_connection()
    cur = conn.cursor()

    #password guardada com hash MD5 (ajustar ao que o Gonçalo definir)
    password_hash = hashlib.md5(password.encode()).hexdigest()

    # verificar se as credenciais são válidas
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

    #descobrir o role verificando as tabelas descendentes
    cur.execute("SELECT users_user_id FROM admin WHERE users_user_id = %s",(user_id,))
    if cur.fetchone():
        role = 'admin'
    else:
        cur.execute("SELECT users_user_id FROM librarian WHERE users_user_id = %s",(user_id,))
        if cur.fetchone():
            role = 'librarian'
        else:
            role = 'reader'
    
    cur.close()
    conn.close()
    return (user_id, role)

def require_role(*roles):
    """Decorator que verifica autenticação e role."""
    def decorator(f):
        @functools.wraps(f)
        def wrapper(*args, **kwargs):
            auth = request.authorization
            if not auth:
                return jsonify({'error': 'Autenticação necessária'}), 401
            
            user = check_auth(auth.username, auth.password)
            if not user:
                return jsonify({'error': 'Credenciais inválidas'}), 401
            
            user_id, role = user
            if roles and role not in roles:
                return jsonify({'error': 'Sem permissão'}), 403
            # passa user_id e role para o endpoint
            return f(*args, user_id=user_id, role=role, **kwargs)
        return wrapper
    return decorator