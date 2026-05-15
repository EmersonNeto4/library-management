from flask import Flask
from dotenv import load_dotenv

load_dotenv() #carrega as variáveis de ambiente do .env

app = Flask(__name__)

#importar blueprints (cada ficheiro de endpoints é um blueprint)
from endpoints.admin import admin_bp
from endpoints.librarian import librarian_bp
from endpoints.user import user_bp

#registar blueprints
app.register_blueprint(admin_bp, url_prefix='/sgdproj')
app.register_blueprint(librarian_bp, url_prefix='/sgdproj')
app.register_blueprint(user_bp, url_prefix='/sgdproj')

if __name__ == '__main__':
    app.run(debug=True, port=8080)