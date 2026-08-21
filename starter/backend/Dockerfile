FROM python:3.10-slim-bookworm

ENV FLASK_RUN_HOST=0.0.0.0

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        gcc \
        libpcre3-dev \
        libssl-dev \
        libffi-dev \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir pipenv

COPY Pipfile* /app/

RUN pipenv install --system --deploy

COPY . /app

RUN useradd --create-home --uid 1000 app && \
    chown -R app:app /app

USER app

EXPOSE 5000

CMD ["uwsgi", "--http", ":5000", "--master", "--enable-threads", "-s", "/tmp/app.sock", "--manage-script-name", "--mount", "/=app:app"]