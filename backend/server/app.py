from flask import Flask

from config import Config
from routes.chat import chat_bp
from routes.health import health_bp
from routes.itinerary import itinerary_bp
from routes.poi import poi_bp
from routes.tasks import tasks_bp
from routes.models import models_bp
from routes.auth import auth_bp


def create_app() -> Flask:
    app = Flask(__name__)
    app.register_blueprint(health_bp)
    app.register_blueprint(itinerary_bp)
    app.register_blueprint(chat_bp)
    app.register_blueprint(tasks_bp)
    app.register_blueprint(poi_bp)
    app.register_blueprint(models_bp)
    app.register_blueprint(auth_bp)
    return app


app = create_app()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=Config.PORT, debug=Config.DEBUG)
