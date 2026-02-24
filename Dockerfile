FROM python:3.11-slim

WORKDIR /app

COPY pyproject.toml server.py ./

RUN pip install --no-cache-dir .

EXPOSE 8080

ENV MCP_TRANSPORT=sse
ENV PORT=8080

CMD ["python", "server.py"]
