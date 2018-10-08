# как запускать контейнер
# sudo docker-compose --project-name data-cli -f docker-compose.yml run --rm flask-app
# docker-compose --project-name data-cli -f docker-compose.yml up --build -d flask-app

FROM continuumio/miniconda3

COPY ./src/* /home/
COPY ./templates/* /home/templates/
RUN while read requirement; do conda install --yes $requirement; done < /home/requirements.txt

CMD ["python", "/home/app.py" ]
