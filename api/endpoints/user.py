from flask import Blueprint
from ..auth import require_role

user_bp = Blueprint('user', __name__)