from flask_sqlalchemy import SQLAlchemy
import os
from sqlalchemy import Enum, inspect
import enum

db = SQLAlchemy()


class SenderType(enum.Enum):
    USER = "user"
    MODEL = "model"


class StoryTheme(enum.Enum):
    DRAGONS = "dragons"
    SPACE = "space"
    ANIMALS = "animals"
    MAGIC = "magic"
    PIRATES = "pirates"
    DINOSAURS = "dinosaurs"
    FAIRY_TALE = "fairy_tale"
    ADVENTURE = "adventure"


class Conversation(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    created_at = db.Column(db.DateTime, default=db.func.current_timestamp())
    user_id = db.Column(db.String(255), nullable=False)


class Message(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    conversation_id = db.Column(db.Integer, db.ForeignKey(
        'conversation.id'), nullable=False)
    sender_type = db.Column(Enum(SenderType), nullable=False)
    code = db.Column(db.Integer, nullable=False)
    content = db.Column(db.String(5000), nullable=False)
    created_at = db.Column(db.DateTime, default=db.func.current_timestamp())

    conversation = db.relationship(
        'Conversation', backref=db.backref('messages', lazy=True))


class ChildAccount(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(255), unique=True, nullable=False)
    pin = db.Column(db.String(255), nullable=False)
    display_name = db.Column(db.String(255), nullable=False)
    age = db.Column(db.Integer, nullable=False)
    parent_uid = db.Column(db.String(255), nullable=False)
    created_at = db.Column(db.DateTime, default=db.func.current_timestamp())


class StoryAssignment(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    conversation_id = db.Column(db.Integer, db.ForeignKey(
        'conversation.id'), nullable=False)
    child_username = db.Column(db.String(255), db.ForeignKey(
        'child_account.username'), nullable=False)
    title = db.Column(db.String(255), nullable=False)
    assigned_at = db.Column(db.DateTime, default=db.func.current_timestamp())
    conversation = db.relationship(
        'Conversation', backref=db.backref('story_assignments', lazy=True))
    child_account = db.relationship(
        'ChildAccount', backref=db.backref('assigned_stories', lazy=True))


def init_db(app):
    db_user = os.getenv("DB_USER")
    db_password = os.getenv("DB_PASSWORD")
    db_host = os.getenv("DB_HOST")
    db_name = os.getenv("DB_NAME")

    print(f"Connecting to database at {db_host} with user {db_user}")
    print(f"Using database {db_name}")

    app.config['SQLALCHEMY_DATABASE_URI'] = (
        f"mysql+mysqlconnector://{db_user}:{db_password}@{db_host}/{db_name}"
    )
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
    db.init_app(app)
    with app.app_context():
        inspector=inspect(db.engine)
        for table_name in db.metadata.tables.keys():
            if not inspector.has_table(table_name):
                print(f"Creating table: {table_name}")
                db.create_all()
        print("Database setup completed!")
