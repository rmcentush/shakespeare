FROM python:3.14.6-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app

RUN addgroup --system shakespeare && adduser --system --ingroup shakespeare shakespeare

COPY requirements.txt ./requirements.txt
RUN pip install --no-cache-dir --requirement requirements.txt

COPY shakespeare_service ./shakespeare_service
COPY database ./database

USER shakespeare
EXPOSE 8080

CMD ["uvicorn", "shakespeare_service.app:create_app", "--factory", "--host", "0.0.0.0", "--port", "8080"]
