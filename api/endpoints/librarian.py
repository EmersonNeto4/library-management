from flask import Blueprint
from ..auth import require_role

librarian_bp = Blueprint('librarian', __name__)