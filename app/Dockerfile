FROM python:3.12-slim
ARG APP_VERSION=dev
ENV PYTHONUNBUFFERED=1 APP_VERSION=${APP_VERSION}
RUN useradd --create-home appuser
WORKDIR /app
COPY app.py .
USER appuser
EXPOSE 8080
CMD ["python", "app.py"]
