# Подготовка машины к работе

## Описание рабочей среды

Занятия будут проходить в ОС Ubuntu 18.04 LTS. Установка необходимых баз данных (Mongo, Postgres, Redis, etc.)
осуществляется с помощью утилиты виртуализации Docker. Подготовку нужно выполнить всего один раз: установить docker и docker-compose, скачать данные
и произвести сборку контейнера.

Обновим список пакетов - нужно выполнить в консоли команду:

<pre>
sudo apt-get update && sudo apt-get -y upgrade
</pre>

Эта команда обновит пакетный менеджер apt-get. После этого установить менеджер пакетов pip и вспомогательные утилиты (unzip, git):

<pre>
sudo apt-get install python-pip unzip git
</pre>

Пакет pip - это менеджер пакетов python, его помощью можно будет устанавливать python библиотеки. Утилита unzip - программа для распаковки архивов.

С помощью pip установим библиотеку requests:
<pre>
pip install requests tqdm;
</pre>

Теперь zip-архив с данными, который я заранее залил на Google Drive нужно перенести на локальную машину. Для этого  склонируем полезный репозиторий (содержит утилиту для скачивания с Google Cloud).

<pre>
rm -rf download_google_drive; git clone https://github.com/chentinghao/download_google_drive.git
</pre>

Запускаем скачивание файла - zip архива с данными. Архив весит примерно 23Mb
<pre>
python download_google_drive/download_gdrive.py 1D3CcWOSw-MUx6YvJ_4dqOLHZAh-6uTxK data.zip
</pre>

## Установка docker

Установим docker, согласно [Инструкции тут](https://docs.docker.com/install/linux/docker-ce/ubuntu/)

Кроме докера поставим docker-compose

<pre>
sudo apt-get install docker-compose
</pre>

Теперь скачиваем репозиторий курса

<pre>
git clone https://github.com/Dju999/data_analytics.git
</pre>

Подготовка завершена! Один раз проделав этот пункт, можно к нему больше не возвращаться

## Работа c репозиторием

Сначала распаковываем архив с данными.

Создаём в системе рабочую директорию, в которой буду храниться файлы для закачки в БД

<pre>
export NETOLOGY_DATA="/usr/local/share/netology_data"; \
sudo rm -rf "$NETOLOGY_DATA"/*; \
sudo mkdir -m 764 "$NETOLOGY_DATA"; \
sudo mkdir -m 764 "$NETOLOGY_DATA"/raw_data; \
unzip data.zip -d "$NETOLOGY_DATA"/raw_data; \
sudo mkdir -m 764 "$NETOLOGY_DATA"/pg_data;
</pre>

Мы увидим процесс извлечения данных - это csv и json файлы

<pre>
Archive:  data.zip
  inflating: /tmp/data/ratings.csv
  inflating: /tmp/data/ratings_small.csv
  inflating: /tmp/data/links.csv
  inflating: /tmp/data/links_small.csv
  inflating: /tmp/data/keywords.csv
  inflating: /tmp/data/movies_metadata.csv
  inflating: /tmp/data/credits.csv
</pre>

Переходим в директорию с докер-файлами
<pre>
cd data_analytics/docker_compose
</pre>

Экспортируем переменную среды - это директория, куда будем извлекать данные
<pre>
export NETOLOGY_DATA="/usr/local/share/netology_data"
</pre>

Запускаем сборку контейнера. В консоли побежит информация о сборке контейнера. После окончания сборки мы автоматически подключимся к командной строке Debian, т.е. внутрь контейнера:
<pre>
make client
</pre>

Проверим, что директория с данными успешно подключилась:
<pre>
/ # ls /data
credits.csv          links.csv            movies_metadata.csv  ratings_small.csv
keywords.csv         links_small.csv      ratings.csv
</pre>

Как видно csv-файлы присутствуют, контейнер запущен! можно начинать работу.


Запускаем скрипт для загрузки файлов в Postgres
<pre>
bash /home/load_data.sh
</pre>

После того, как всё данные загружены в Postgres - проверим подключение к БД:

Подключение к Postgres
<pre>
psql --host $APP_POSTGRES_HOST -U postgres -c "SELECT COUNT(*) as num_ratings FROM ratings"
</pre>

## Решение проблем с docker

Если контейнер не стартует с ошибкой
<pre>
docker: Error response from daemon: Conflict. The container name "/netology-postgres" is already in use by container "2a99cb6629b78e7b5b6747a9bd453263940127909d91c8517e9ee0b230e60768". You have to remove (or rename) that container to be able to reuse that name.
</pre>

То контейнер уже создан и можно стартовать его
<pre>
sudo docker start 2a99cb6629b78e7b5b6747a9bd453263940127909d91c8517e9ee0b230e60768
</pre>

Если не помогло - надо бы остановить все запущенные докер-образы и удалить их

<pre>
sudo docker stop $(sudo docker ps -a -q)
sudo docker rm $(sudo docker ps -a -q)
</pre>

Удаление всех образов
<pre>
docker rmi $(docker images -q)
</pre>

Параметры docker run, остальные параметры [тут](https://docs.docker.com/v1.11/engine/reference/commandline/run/)

<code>
--name - Assign a name to the container

-d, --detach - Run container in background and print container ID

-e - устанавливаем переменную среды

-it - запустить интеракцивный терминал
</pre>

# Установка Ubuntu 18.04 в Google Cloud

Как установить - по инструкции отсюда: https://cloud.google.com/compute/docs/quickstart-linux

Внимание! В инструкции установка Debian, а нам нужна Ubuntu 18.04. Эта опция выбирается в меню Boot Disk

![выбор ОС](https://habrastorage.org/webt/vl/dt/3m/vldt3mgct8jq3n6n9oa3pmyug_a.png "boot disk")

После установики ваш инстанс можно будет найти на этой странице https://console.cloud.google.com/compute/instances

![страница с инстансами](https://habrastorage.org/webt/cb/fx/qz/cbfxqzxqcdo0atxs9eg_c-t3jby.png "Google cloud instances")
