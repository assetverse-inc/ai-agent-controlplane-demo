FROM python:3.12-slim

WORKDIR /app

RUN pip install --no-cache-dir "a2a-sdk[http-server]==1.1.0" uvicorn httpx

COPY . .

EXPOSE 9001

CMD ["python", "__main__.py"]
