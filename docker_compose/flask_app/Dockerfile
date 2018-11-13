# как запускать контейнер
# sudo docker-compose --project-name data-cli -f docker-compose.yml run --rm flask-app
# docker-compose --project-name data-cli -f docker-compose.yml up --build -d flask-app

FROM continuumio/miniconda3:4.5.11
RUN conda update -n base conda

COPY ./src/* /home/

COPY ./templates/* /home/templates/
RUN while read requirement; do /opt/conda/bin/conda install --yes $requirement; done < /home/requirements.txt
