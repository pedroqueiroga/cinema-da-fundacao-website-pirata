#!/bin/bash

DB_USER=${DATABASE_USER:-postgres}

while ! pg_isready -h $DATABASE_HOST -p $DATABASE_PORT -U $DB_USER
do
  echo "$(date) - pg_isready -q -h $DATABASE_HOST -p $DATABASE_PORT -U $DB_USER"
  sleep 2
done



echo "attempting to create db..."

createdb -h $DATABASE_HOST -p $DATABASE_PORT -U $DATABASE_USER cinema_da_fundacao_website_pirata_stg || true

echo "running migrations..."

/app/bin/migrate

echo "migrated!"

# start the elixir application
exec "/app/bin/cinema_da_fundacao_website_pirata" "start"
