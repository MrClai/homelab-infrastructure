FROM python:3.14-slim
WORKDIR /app
RUN useradd -m notes_user
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py ./
USER notes_user
CMD ["python", "-m", "flask", "--app", "app", "run", "--host=0.0.0.0"]
