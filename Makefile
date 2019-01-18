PROJECT_NAME = data-client
PROJECT_FLASK_NAME = flask-app
DOCKER_COMPOSE = docker-compose --project-name $(PROJECT_NAME) -f docker_compose/docker-compose.yml
DOCKER_COMPOSE_FLASK = docker-compose --project-name $(PROJECT_FLASK_NAME) -f docker_compose/docker-compose.yml

build:
	$(DOCKER_COMPOSE) build $(PROJECT_NAME)

build_flask:
	$(DOCKER_COMPOSE_FLASK) build $(PROJECT_FLASK_NAME)

# Принудительно пересобрать контейнер
rebuild:
	$(DOCKER_COMPOSE) build $(PROJECT_NAME)

clean:
	$(DOCKER_COMPOSE) down -v --remove-orphans

clean_flask:
	$(DOCKER_COMPOSE_FLASK) down -v --remove-orphans

client: clean_flask clean build
	$(DOCKER_COMPOSE) run --rm --name $(PROJECT_NAME) $(PROJECT_NAME)

flask: clean clean_flask build_flask
	$(DOCKER_COMPOSE_FLASK) run -p 5001:5001 --rm --name $(PROJECT_FLASK_NAME) $(PROJECT_FLASK_NAME)
