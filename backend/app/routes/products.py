from flask import Blueprint, jsonify

from app.models import Product

products_bp = Blueprint("products", __name__)


@products_bp.get("/")
def list_products():
    products = Product.query.order_by(Product.created_at.desc()).all()
    return jsonify([product.to_dict() for product in products])


@products_bp.get("/<int:product_id>")
def get_product(product_id):
    product = Product.query.get_or_404(product_id)
    return jsonify(product.to_dict())
