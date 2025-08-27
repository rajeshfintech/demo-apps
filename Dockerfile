FROM python:3.11-slim

WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1     PYTHONUNBUFFERED=1     PORT=8080

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY gunicorn.conf.py ./

# Capture Git commit hash and build info during build
ARG GIT_COMMIT_HASH=unknown
ARG BUILD_TIME
ARG GIT_BRANCH=unknown

# Set environment variables for runtime access
ENV GIT_COMMIT_HASH=${GIT_COMMIT_HASH}
ENV BUILD_TIME=${BUILD_TIME}
ENV GIT_BRANCH=${GIT_BRANCH}

# Also create a commit file as backup
RUN echo "${GIT_COMMIT_HASH}" > /app/commit.txt

# non-root
RUN useradd -u 10001 -m appuser
USER 10001

EXPOSE 8080
CMD ["gunicorn", "-c", "gunicorn.conf.py", "app.app:create_app()"]

