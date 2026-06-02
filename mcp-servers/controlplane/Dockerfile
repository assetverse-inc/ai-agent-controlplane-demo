FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir fastmcp==3.3.1 httpx
COPY server.py .
EXPOSE 8000
CMD ["python", "server.py"]
