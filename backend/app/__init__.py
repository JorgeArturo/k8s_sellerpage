import time

from flask import Flask, jsonify
from flask_cors import CORS
from flask_jwt_extended import JWTManager
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.exc import OperationalError

from app.config import Config

db = SQLAlchemy()
jwt = JWTManager()


def create_app(config_class=Config):
    app = Flask(__name__)
    app.config.from_object(config_class)

    CORS(app, resources={r"/api/*": {"origins": "*"}})
    db.init_app(app)
    jwt.init_app(app)

    from app.routes.auth import auth_bp
    from app.routes.products import products_bp
    from app.routes.admin import admin_bp

    app.register_blueprint(auth_bp, url_prefix="/api/auth")
    app.register_blueprint(products_bp, url_prefix="/api/products")
    app.register_blueprint(admin_bp, url_prefix="/api/admin")

    @app.get("/api/health")
    def health():
        return jsonify({"status": "ok"})

    with app.app_context():
        _wait_for_db(app)
        db.create_all()
        _seed_admin(app)

    return app


def _wait_for_db(app, retries=30, delay=2):
    for attempt in range(retries):
        try:
            db.session.execute(db.text("SELECT 1"))
            db.session.commit()
            return
        except OperationalError:
            db.session.rollback()
            if attempt == retries - 1:
                raise
            time.sleep(delay)


def _seed_admin(app):
    from app.models import User

    admin = User.query.filter_by(email=app.config["ADMIN_EMAIL"]).first()
    if admin:
        return

    admin = User(email=app.config["ADMIN_EMAIL"], is_admin=True)
    admin.set_password(app.config["ADMIN_PASSWORD"])
    db.session.add(admin)
    db.session.commit()
