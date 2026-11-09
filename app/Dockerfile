FROM python:3.12-slim
ARG APP_VERSION=dev
ENV PYTHONUNBUFFERED=1 APP_VERSION=${APP_VERSION}
RUN useradd --create-home appuser
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py worker.py ./
USER appuser
EXPOSE 8080
# The API runs by default; the worker service overrides the command.
CMD ["python", "app.py"]
