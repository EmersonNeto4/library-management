from flask import Blueprint, jsonify
from api.auth import require_role

admin_bp = Blueprint('admin', __name__, url_prefix='/admin')

@admin_bp.route('/user', methods=['POST'])
@require_role('admin')
def register_user(user_id, role):
    # Implementation for creating a user
    return jsonify({'message': 'OK'}), 200