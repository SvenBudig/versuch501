# Vulnerable Dockerfile with 2 key security issues
#FROM python:3.12-slim
FROM python:3.8
COPY app/ /app/
WORKDIR /app
RUN pip install flask requests
EXPOSE 5000
CMD ["python", "main.py"]

#RUN useradd -m -u 1000 appuser && \
#    chown -R appuser:appuser /app
#USER appuser
