FROM python:3.12

WORKDIR /app

COPY . .

RUN pip install -r requirements.txt

ENV PYTHONPATH=/app/src

CMD ["python", "-m", "conciliacion"]
