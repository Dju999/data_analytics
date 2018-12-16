# Взаимодействие Python и Psycorg

Psycorg - быстрая библитека на языке C, которая позволяет подключаться к БД Postgres.

Это очень тонкий клиент, который по сути позвовляет произвести три действия: подключиться к БД, выполнить SQL-запрос и получить результат запроса в виду python-объекта.

Сначала импортируем нужные библиотеки
<pre>
import psycopg2
import os
</pre>

Подключение к БД выглядит стандартным образом - нужно передать в функцию connect хост, порт и имя пользователя, который инициирует подключение:
<pre>
params = {
    "host": os.environ['APP_POSTGRES_HOST'],
    "port": os.environ['APP_POSTGRES_PORT'],
    "user": 'postgres'
}
conn = psycopg2.connect(**params)
</pre>

Поле этого требуется настроить курсор - объект, который занимается выполнением SQL и выборкой данных

<pre>
psycopg2.extensions.register_type(
    psycopg2.extensions.UNICODE,
    conn
)
conn.set_isolation_level(
    psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT
)
cursor = conn.cursor()
</pre>

У объекта cursor есть метод execute, который позволяет передать стандартный SQL на выполнение в Postgres:

<pre>
user_item_query_config = {
    "MIN_USERS_FOR_ITEM": 10,
    "MIN_ITEMS_FOR_USER": 3,
    "MAX_ITEMS_FOR_USER": 50,
    "MAX_ROW_NUMBER": 100000
}
sql_str = (
        """
            SELECT
                ratings.userId as user, ratings.movieId as item, AVG(ratings.rating) as rating
            FROM ratings
            -- фильтруем фильмы, которые редко оценивают
            INNER JOIN (
                SELECT
                    movieId, count(*) as users_per_item
                FROM ratings
                GROUP BY movieId
                HAVING COUNT(*) > %(MIN_USERS_FOR_ITEM)d
            ) as movie_agg
                ON movie_agg.movieId = ratings.movieId
            -- фильтруем пользователей, у которых мало рейтингов
            INNER JOIN (
                SELECT
                    userId, count(*) as items_per_user
                FROM ratings
                GROUP BY userId
                HAVING COUNT(*) BETWEEN %(MIN_ITEMS_FOR_USER)d AND %(MAX_ITEMS_FOR_USER)d
            ) as user_agg
                ON user_agg.userId = ratings.userId
            GROUP BY 1,2
            LIMIT %(MAX_ROW_NUMBER)d
        """ % user_item_query_config
)
</pre>

Мы видим, что SQL-запрос представляет собой строковую переменую. В примере так же видно, как с помощью
стандартных средств форматирования строк в Python можно передавать в запрос какие-то параметры для более гибкой настройки результатов.

Оталось выполнить запрос на стороне Postgres и выгрузить результат обратно в Python
<pre>
cursor.execute(sql_str)
ui_data = [a for a in cursor.fetchall()]
conn.commit()
</pre>

Метод commit() в явном виде завершает транзакцию. Это особенно важно для конструкций типа INSERT.

Для наглядности сохраним данные в текстовый TSV-файл
<pre>
agg_filename = '/home/user_agg.tsv'
# создаём текстовый файл с результатами
with open(agg_filename, 'w') as f:
    for row in ui_data:
        f.write("{}\t{}\t{}\n".format(row[0], row[1], row[2]))
</pre>

Проверим, что данные в файл записаны корректно
<pre>
# head /home/user_agg.tsv
180	2145	3.0
300	593	4.5
80	32	5.0
541	3175	3.0
343	1042	5.0
644	2174	4.0
347	2571	3.0
40	4993	4.5
375	110	3.0
28	1094	4.0
</pre>

Всё ок! Мы выполнили запрос в Postgres с помощью Psycopg2 и сохранили результаты в текстовый файл, который можно использовать для следующих этапов обработки.

# ORM в Python:  SQLAclchemy

SQLAclchemy - фреймворк более высокого уровня, написанный на Python, который использует примитивы из других фреймворков - например, Psycopg2.

Эта библиотека реализует ORM-модель (object-relation mappping) - то есть все действия с БД происходят в виде взаимодействий между python-объектами.

При таком подходе SQL-код генерирует сама библиотека, а разработчик оперирует только созданными классами.

Создадим кодключение с помощью SQLAlchemy к Postgres:

<pre>
import os

from sqlalchemy import create_engine
from sqlalchemy import Table, Column, Integer, Float, MetaData
from sqlalchemy.orm import mapper
from sqlalchemy.orm import sessionmaker

engine = create_engine('postgresql://postgres:@{}'.format(os.environ['APP_POSTGRES_HOST']))
</pre>

Теперь можно описать таблицу в виде класса python и создать её средствами SQLAlchemy

<pre>
metadata = MetaData()
ui_table = Table(
    'ui_interactions', metadata,
    Column('user', Integer, primary_key=True),
    Column('item', Integer, primary_key=True),
    Column('rating', Float)
)

metadata.create_all(engine)
</pre>

Весь SQL-код вида *CREATE TABLE*  генерируется внутри функции create_all (включая базовую обработку ошибок). Обратите внимание, что первичный ключ состоит из двух столбцов.

Каждая запись в таблице - это объект соответствующего класса. В нашей таблице хранится информация о взаимодействии пользователя с контентом - создадим соответствующий класс.
<pre>
class UITriplet(object):
    """
        Интеракция контента с пользователем

        Содержит триплеты пользователь-контент-рейтинг
    """
    def __init__(self, user, item, rating):
        self.user = user
        self.item = item
        self.rating = rating
    def __repr__(self):
        return "<User('%s','%s', '%s')>" % (self.user, self.item, self.rating)
</pre>

Класс UITriplet и табличку Postgres свяжет объект mapper

<pre>
mapper(UITriplet, ui_table)
</pre>

Если не применить mapper, получим ошибку
<pre>
sqlalchemy.exc.InvalidRequestError: Class <class 'sqlalchemy_example.Link'> does not have a __table__ or __tablename__ specified and does not inherit from an existing table-mapped class.
</pre>

Наконец можно что-то сделать с таблице! Для этого нужно сосздать сессию пользователя (это плата за ACID)
<pre>
Session = sessionmaker(bind=engine)
session = Session()
</pre>

Подготовим данные для добавления в таблицу

<pre>
if session.query(UITriplet).count() == 0:
    agg_filename = '/home/user_agg.tsv'
    ui_data = []
    with open(agg_filename, 'r') as f:
        for line in f.readlines():
            line = line.strip().split('\t')
            ui_data.append(
                UITriplet(line[0], line[1], line[2])
            )
</pre>

У нас получился массив объектов *ui_data* класса *UITriplet* . При помощи SQLAlchemy мы можем добавить эти записи в таблицу
<pre>
if session.query(UITriplet).count() == 0:
    session.add_all(ui_data)
    session.commit()
</pre>

Комит нужно выполнить обязательно - иначе данные не добавится, то есть фнукция *connection.commit()* должна выполнятся после каждого измения данных - например, UPDATE или INSERT.
Результат работы скрипта psycopg_example.py:

<pre>
psql --host $APP_POSTGRES_HOST -U postgres -c "DROP TABLE IF EXISTS ui_interactions"; python /home/psycopg_example.py; python /home/sqlalchemy_example.py

2018-08-05 20:06:35,051 : INFO : Создаём подключёние к Postgres
2018-08-05 20:06:35,118 : INFO : Данные по оценкам загружены из Postgres
2018-08-05 20:06:35,124 : INFO : Данные сохранены в /home/user_agg.tsv

2018-08-05 20:06:45,377 : INFO : Формируем подключение к Postgres через SQLAlchemy
2018-08-05 20:06:46,208 : INFO : 7261 записей загружены в Postgres
</pre>

Проверяем, что таблица существует и туда попали всё нужные данные
<pre>
psql --host $APP_POSTGRES_HOST -U postgres
</pre>

Выполним несколько запросов

<pre>
SELECT table_schema,table_name FROM information_schema.tables WHERE table_name='ui_interactions';

 table_schema |   table_name
--------------+-----------------
 public       | ui_interactions
(1 row)

SELECT COUNT(*) FROM public.ui_interactions;

 count
-------
  7261
(1 row)
</pre>

Готово! SQLAlchemy очень полезная штука в веб-приложениях, которая позволяет по классам Python генерировать таблицы в БД.

Можно выполнять запросы к таблицам с помощую полезной [функции query](http://docs.sqlalchemy.org/en/latest/orm/query.html)

query позволяет обращаться к таблице через свойства класса Python, с которым эта таблица ассоциирована.

<pre>
sqla_query = session.query(UITriplet).filter(UITriplet.rating>3.5).order_by(UITriplet.rating.desc()).limit(10)

print([i for i in sqla_query])
</pre>

SQLAlchemy обладает стандартными для SQL возможностями - напиример, можно делать группировки
<pre>
sqla_grouped_query = session.query(UITriplet.user, label('count', func.count(UITriplet.item))).group_by(UITriplet.user).limit(10)

logger.info("Пример группировки по полю user таблицы ratings {}".format([i for i in sqla_grouped_query]))
</pre>

Можно джойнить таблички с помощью соответствующей функции - join либо outer join. Например, отфильтруем контент из таблички Links, у которого нет оценок:

<pre>
join_query = session.query(Link.imdbid).outerjoin(UITriplet, UITriplet.item == Link.movieid).filter(UITriplet.item is None).limit(5)
logger.info("Результат LEFT JOIN: id контента, которому не ставили оценки {}".format([i[0] for i in join_query]))
</pre>

Мы познакомились с основным функционалом SQLAlchemy: выборки и фильтрация данных, джойны и группировки.

# Из Python в Mongodb

Для выгрузки данных из MongoDB (или их загрузки) Существует библиотека PyMongo. Библиотека представляет собой python-обёртку над API MongoDB.

Создадим класс клиента для доступа к БД и инициируем подключение
<pre>
import os

from pymongo import MongoClient
mongo = MongoClient(**{
    'host': os.environ['APP_MONGO_HOST'],
    'port': int(os.environ['APP_MONGO_PORT'])
})
db = mongo.get_database(name="movie")

collection = db['tags']
</pre>

Функция get_database() возвращает доступ к БД, с которой мы будем работать. Collection - это доступ к соответствующей коллекции
Заметим, что самой БД не существует - она будет создана в момент первого запроса

Для примера загрузки данных мы будем работать с файлом keyword.tsv, который выглядит следующим образом:
<pre>
# head -n3 '/data/keywords.tsv'
862	[{'id': 931, 'name': 'jealousy'}, {'id': 4290, 'name': 'toy'}, {'id': 5202, 'name': 'boy'}, {'id': 6054, 'name': 'friendship'}, {'id': 9713, 'name': 'friends'}, {'id': 9823, 'name': 'rivalry'}, {'id': 165503, 'name': 'boy next door'}, {'id': 170722, 'name': 'new toy'}, {'id': 187065, 'name': 'toy comes to life'}]
8844	[{'id': 10090, 'name': 'board game'}, {'id': 10941, 'name': 'disappearance'}, {'id': 15101, 'name': "based on children's book"}, {'id': 33467, 'name': 'new home'}, {'id': 158086, 'name': 'recluse'}, {'id': 158091, 'name': 'giant insect'}]
15602	[{'id': 1495, 'name': 'fishing'}, {'id': 12392, 'name': 'best friend'}, {'id': 179431, 'name': 'duringcreditsstinger'}, {'id': 208510, 'name': 'old men'}]
</pre>

То есть это пары <movieID, movieTags>, разделённые символом '\t'. В монго можно записать объекты типа dict из python, то есть файл нужно преобразовать.

Разобъем каждую строку на пачку dict вида {'id': 931, 'name': 'jealousy', 'movieId': '862'}, где id - идентификатор тега а movieId - идентификатор фильма, котором принадлежит тег.
Для преобразования будем использовать python:
<pre>
agg_filename = '/data/keywords.tsv'
tag_data = []
if db.tags.count() == 0:
    with open(agg_filename, 'r') as f:
        for line in f.readlines():
            movieId, tags = line.strip().split('\t')
            tags = eval(tags)
            for tag in tags:
                tag.update({'movieId': movieId})
                tag_data.append(
                    tag
                )
    collection.insert_many(tag_data)
</pre>

Таким образом мы сформировали массив tag_data, который состоит из триплетов по тегам.
Запись в MongoDB была произведена с помощью функции  *insert_many*.

Запускаем заливку данных (скрипт python /home/pymongo_example.py)
<pre>
python /home/pymongo_example.py
</pre>

Вывод

<pre>
2018-08-06 04:06:20,529 : INFO : Создадаём подключение к Mongo
2018-08-06 04:06:23,207 : INFO : sample tags: [
    {'id': 931, 'name': 'jealousy', 'movieId': '862', '_id': ObjectId('5b67c93dde1440000bf352b3')},
    {'id': 4290, 'name': 'toy', 'movieId': '862', '_id': ObjectId('5b67c93dde1440000bf352b4')},
    {'id': 5202, 'name': 'boy', 'movieId': '862', '_id': ObjectId('5b67c93dde1440000bf352b5')}
 ]
2018-08-06 04:06:23,208 : INFO : Общее количество документов к коллекции: 317361
</pre>

Давайте подключимся к Mongo и проверим, что число данных совпадает
<pre>
mongo $APP_MONGO_HOST:$APP_MONGO_PORT/movie
</pre>

Проверка: запускаем счётчик
<pre>
db.tags.count()

317361
</pre>

Количество тегов совпадает. Посмотрим на конкретные документы:

<pre>
> db.tags.find().limit(5)
{ "_id" : ObjectId("5b67c14dce5c4300130cfc85"), "1" : 2 }
{ "_id" : ObjectId("5b67c1b596e8a6000b7f71cf"), "id" : 931, "name" : "jealousy", "movieId" : "862" }
{ "_id" : ObjectId("5b67c1b596e8a6000b7f71d0"), "id" : 4290, "name" : "toy", "movieId" : "862" }
{ "_id" : ObjectId("5b67c1b596e8a6000b7f71d1"), "id" : 5202, "name" : "boy", "movieId" : "862" }
{ "_id" : ObjectId("5b67c1b596e8a6000b7f71d2"), "id" : 6054, "name" : "friendship", "movieId" : "862" }
</pre>

Для выгрузки данных из Mongo у объекта MongoClient тоже существует много разных ручек.
Для демонстрации напишем код, который подсчитывает самые популярные теги

Сформируем пайплан для агрегации
<pre>
pipline = [
    {"$group":
        {"_id": "$name",
         "tag_count":
            {"$sum": 1}
         }
     },
    {"$sort":
        {"tag_count": -1}
     },
    {"$limit": 5}
]
</pre>

Выполним пайплан - получим курсор, по результатам которого можно итерироваться:
<pre>
print([i for i in collection.aggregate(pipline)])
</pre>

Результат выдачи:
<pre>
2018-08-06 09:00:00,941 : INFO : Пример аггрегации данных: top-5 самых популярных тегов
[{'_id': 'woman director', 'tag_count': 9345}, {'_id': 'independent film', 'tag_count': 5790}, {'_id': 'murder', 'tag_count': 3924}, {'_id': 'based on novel', 'tag_count': 2505}, {'_id': 'musical', 'tag_count': 2202}]
</pre>

Готово! теперь мы умеем загружать данные в Mongo и строить сложные запросы к данным.

# Работа с Pandas

Pаndas - библиотека для работы с табличными данными. Основной объект в Pandas - DataFrame, представляет собой абстракцию таблицы.

Каждый столбец в DataFrame имеет тип Series - это аналог одномерного массива. Каждый Series может содержать объекты только одного типа.

Библиотека позволяет гибко загружать данные из текстовых файлов, а так же из реляционных баз данных

Пример - подгружаем в DataFrame файл с рейтингами (все команды выполняются в python консоли)

Импортируем нужные библиотеки
<pre>
import pandas as pd
import numpy as np
</pre>

<pre>
df = pd.read_csv('/data/links.csv', sep=',', header='infer')
</pre>

Функция .head() выводит шапку таблицы
<pre>
df.head()
</pre

Результат

<pre>
   movieId  imdbId   tmdbId
0        1  114709    862.0
1        2  113497   8844.0
2        3  113228  15602.0
3        4  114885  31357.0
4        5  113041  11862.0
</pre>

Проверим типизацию столбцов
<pre>
df.dtypes
</pre

Результат

<pre>
movieId      int64
imdbId       int64
tmdbId     float64
dtype: object
</pre>

Автоматически читаем заголовок в первой строке и неявно приводим колонку к правильному типу данных
Аналог
Тип данных можно поменять на лету:
<pre>
links[['tmdbId']] = df.tmdbId.astype(np.int64)
</pre>

Возникнет ошибка про незаполненные поля
<pre>
ValueError: Cannot convert non-finite values (NA or inf) to integer
</pre>

 конструкции UPDATE + WHERE - заполняем пустае поля какими-то значениями (например, нулями)
<pre>
links.loc[df.tmdbId.isnull()] = 0
</pre

После этого ещё раз запустим процессинг - ошибка больше не возникнет.

## Загрузка из Postgres

<pre>
ratings = pd.read_sql('SELECT * FROM ratings', engine)
ratings.head()
</pre>

Результат

<pre>
   userid  movieid  rating   timestamp
0       1       31     2.5  1260759144
1       1     1029     3.0  1260759179
2       1     1061     3.0  1260759182
3       1     1129     2.0  1260759185
4       1     1172     4.0  1260759205
</pre>

Типы данных в df

<pre>
ratings.dtypes
</pre

Результат

<pre>
userid         int64
movieid        int64
rating       float64
timestamp      int64
dtype: object
</pre>

Можно заметить, что Pandas воспользовался информацией о типах данных из метаинформации о таблице в БД.

## Pandas - конструкции из SQL.

Pandas позволяет строить конструкции, аналогичные операторам SQL - where, join и т.д.

DataFrame.merge - аналог JOIN
<pre>
links.merge(ratings, how='inner', left_on='movieId', right_on='movieid').head()
</pre>

Результат

<pre>
   movieId  imdbId  tmdbId  userid  movieid  rating   timestamp
0        1  114709   862.0       7        1     3.0   851866703
1        1  114709   862.0       9        1     4.0   938629179
2        1  114709   862.0      13        1     5.0  1331380058
3        1  114709   862.0      15        1     2.0   997938310
4        1  114709   862.0      19        1     3.0   855190091
</pre>

how - тип джойна, кроме INNER бывает ещё LEFT  (или OUTER)

Агрегация данных происходит в операторе GroupBy:

<pre>
ratings[ratings.timestamp > datetime.datetime.strptime('2015-01-01', '%Y-%m-%d').timestamp()].groupby(by=['userid'])['movieid'].count().sort_values(ascending=False).head()
</pre>

Результат

<pre>
userid
213    910
457    713
262    676
475    655
56     522
</pre>

COUNT - встроенная функция, кастомные функции можно передавать в .agg и считать несколько различных метрик

<pre>
ratings[ratings.timestamp > datetime.datetime.strptime('2015-01-01', '%Y-%m-%d').timestamp()].groupby(by=['userid'])['rating'].agg([np.ma.count, np.mean, np.std]).head()
</pre>

Результат

<pre>
        count      mean       std
userid
15      266.0  2.274436  1.232372
38        4.0  4.125000  0.478714
40       43.0  4.511628  0.369819
42       70.0  4.014286  0.756477
48       17.0  3.000000  0.612372
</pre>

В Pandas реализовано несколько оконных функций - например rank. Само окно задаётся с помощью GROUP BY:
<pre>
ratings.assign(rnk=ratings.groupby(['userid'])[['timestamp']].rank(method='first', ascending=True)).query('rnk<5').sort_values(['userid','timestamp']).head(10)
</pre>

Результат

<pre>
     userid  movieid  rating   timestamp  rnk
16        1     2294     2.0  1260759108  1.0
17        1     2455     2.5  1260759113  2.0
19        1     3671     3.0  1260759117  3.0
8         1     1339     3.5  1260759125  4.0
29        2      150     5.0   835355395  1.0
49        2      296     4.0   835355395  2.0
90        2      590     5.0   835355395  3.0
91        2      592     5.0   835355395  4.0
102       3      355     2.5  1298861589  1.0
116       3     1271     3.0  1298861605  2.0
</pre>
