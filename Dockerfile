# syntax=docker/dockerfile:1.7.0

ARG PYTHON_VER=3.11.9-slim-bookworm

FROM python:${PYTHON_VER}

ENV DB_URL="db"
ENV DB_NAME=${DB_NAME:-postgres}
ENV DB_USER=${DB_USER:-postgres}
ENV DB_PASSWORD=${DB_PASSWORD:-postgres}
ENV DB_PORT=${DB_PORT:-5432}

WORKDIR /app

COPY requirements.txt .

RUN python3 -m pip install --upgrade pip \
    && python3 -m pip install -r requirements.txt --no-cache-dir --quiet
