import os
import psycopg  
from flask import Flask, request

app = Flask(__name__)
app.json.ensure_ascii = False  # Настройка для корректного отображения русских символов в JSON
def get_connection():
    return psycopg.connect(
        host=os.environ["DB_HOST"],
        port=os.environ["DB_PORT"],
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        connect_timeout=3  # Устанавливаем таймаут подключения в 3 секунды
    )

@app.get("/")
def index():
    return "Приложение работает в Docker-контейнере. Используйте /notes для работы с заметками и /health для проверки состояния базы данных."

@app.get("/notes")
def get_notes():
    with get_connection() as connection:
        rows = connection.execute("SELECT id, text FROM notes").fetchall()

    return [{"id": row[0], "text": row[1]} for row in rows]

@app.post("/notes")
def create_note():
    data = request.get_json()
    text = data["text"]

    if not text.strip():
        return {"error": "Текст заметки не может быть пустым"}, 400

    with get_connection() as connection:
        row = connection.execute(
            "INSERT INTO notes (text) VALUES (%s) RETURNING id, text",
            (text,),
        ).fetchone()

    return {"id": row[0], "text": row[1]}, 201

@app.get("/health")
def health():
    try:
        with get_connection() as connection:
            connection.execute("SELECT 1")
        return {"status": "ok"}, 200
    except psycopg.Error as error:
        app.logger.warning("Ошибка проверки БД: %s", type(error).__name__)
        return {"status": "database unavailable"}, 503