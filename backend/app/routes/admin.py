from decimal import Decimal, InvalidOperation

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity, jwt_required

from app import db
from app.models import Product, User

admin_bp = Blueprint("admin", __name__)


def _require_admin():
    user_id = int(get_jwt_identity())
    user = db.session.get(User, user_id)
    if not user or not user.is_admin:
        return None, (jsonify({"error": "Admin access required."}), 403)
    return user, None


@admin_bp.get("/products")
@jwt_required()
def admin_list_products():
    _, error = _require_admin()
    if error:
        return error

    products = Product.query.order_by(Product.created_at.desc()).all()
    return jsonify([product.to_dict() for product in products])


@admin_bp.post("/products")
@jwt_required()
def create_product():
    _, error = _require_admin()
    if error:
        return error

    data = request.get_json(silent=True) or {}
    name = (data.get("name") or "").strip()
    description = (data.get("description") or "").strip()
    image_url = (data.get("image_url") or "").strip() or None

    try:
        price = Decimal(str(data.get("price", "0")))
        stock = int(data.get("stock", 0))
    except (InvalidOperation, ValueError, TypeError):
        return jsonify({"error": "Invalid price or stock value."}), 400

    if not name:
        return jsonify({"error": "Product name is required."}), 400
    if price < 0 or stock < 0:
        return jsonify({"error": "Price and stock must be non-negative."}), 400

    product = Product(
        name=name,
        description=description,
        price=price,
        stock=stock,
        image_url=image_url,
    )
    db.session.add(product)
    db.session.commit()

    return jsonify(product.to_dict()), 201


@admin_bp.put("/products/<int:product_id>")
@jwt_required()
def update_product(product_id):
    _, error = _require_admin()
    if error:
        return error

    product = Product.query.get_or_404(product_id)
    data = request.get_json(silent=True) or {}

    if "name" in data:
        name = (data.get("name") or "").strip()
        if not name:
            return jsonify({"error": "Product name cannot be empty."}), 400
        product.name = name

    if "description" in data:
        product.description = (data.get("description") or "").strip()

    if "price" in data:
        try:
            price = Decimal(str(data["price"]))
            if price < 0:
                raise ValueError
            product.price = price
        except (InvalidOperation, ValueError, TypeError):
            return jsonify({"error": "Invalid price value."}), 400

    if "stock" in data:
        try:
            stock = int(data["stock"])
            if stock < 0:
                raise ValueError
            product.stock = stock
        except (ValueError, TypeError):
            return jsonify({"error": "Invalid stock value."}), 400

    if "image_url" in data:
        product.image_url = (data.get("image_url") or "").strip() or None

    db.session.commit()
    return jsonify(product.to_dict())


@admin_bp.delete("/products/<int:product_id>")
@jwt_required()
def delete_product(product_id):
    _, error = _require_admin()
    if error:
        return error

    product = Product.query.get_or_404(product_id)
    db.session.delete(product)
    db.session.commit()
    return jsonify({"message": "Product deleted."})
