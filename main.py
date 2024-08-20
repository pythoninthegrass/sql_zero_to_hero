#!/usr/bin/env python

import os
import psycopg2 as pg2

db_host = os.getenv("DB_URL")
db_name = os.getenv("DB_NAME")
db_user = os.getenv("DB_USER")
db_pass = os.getenv("DB_PASS")
db_port = os.getenv("DB_PORT")

# Create a connection with PostgreSQL
conn = pg2.connect(host=db_host,
                   database=db_name,
                   user=db_user,
                   password=db_pass,
                   port=db_port)


# Establish connection and start cursor to be ready to query
cur = conn.cursor()

# Pass in a PostgreSQL query as a string
cur.execute("SELECT * FROM payment")

# Return a tuple of the first row as Python objects
cur.fetchone()

# Return N number of rows
cur.fetchmany(10)

# Return All rows at once
cur.fetchall()

# To save and index results, assign it to a variable
data = cur.fetchmany(10)

query1 = """
    CREATE TABLE new_table (
        userid integer
        , tmstmp timestamp
        , type varchar(10)
    );
"""

cur.execute(query1)

# commit the changes to the database
cur.commit()

# Don't forget to close the connection!
conn.close()
