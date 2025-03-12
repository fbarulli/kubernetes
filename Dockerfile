FROM ubuntu:20.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Set work directory
WORKDIR /app

# Install Python and dependencies
RUN apt-get update && apt-get install -y \
    python3.9 \
    python3-pip \
    python3.9-dev \
    default-libmysqlclient-dev \
    build-essential \
    && ln -s /usr/bin/python3.9 /usr/bin/python \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY files/requirements.txt .

# Install Python packages
RUN pip3 install --no-cache-dir -r requirements.txt

# Copy application code
COPY files/main.py .

EXPOSE 8000

CMD ["python3", "-m", "uvicorn", "main:server", "--host", "0.0.0.0"]