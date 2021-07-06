![Backfill machine](https://railsware.github.io/backfiller/assets/backfill_machine.jpg)

# Backfiller [![Build Status](https://travis-ci.com/railsware/backfiller.svg?branch=master)](https://travis-ci.com/railsware/backfiller)

The backfill machine for null database columns.
This gem maybe handly for `no-downtime` deployment especially when you need to fill columns for table with huge amount for records without locking the table.

## Typical no-downtime and non-locking cycle

* add migration that adds new column (null: true)
* deploy and run migration task
* deploy code that starts filling new column in corresponding flows
* add backfill task
* deploy and run backfill task
* [optional] add migration that invokes backfill task asn so keep all environments consistent (except production environment because we already backfilled data)
* add migration that disallow null values (null: false)
* deploy code that starts using new column

## Concept

The idea is to prepare all data in selection method on database server and fetch it data using CURSOR feature and then build simple UPDATE queries.
With this way we minimize db server resources usage and we lock only one record (atomic update).
We use two connections to database:
* master - to creates cursor in transaction and fetch data in batches.
* worker - to execute small atomic update queries (no wrapper transaction)

Even if backfill process crashes you may resolve issue and run it again to process remaining amount of data.

## Connection adapters

Curently it support next ActiveRecord connection adapters:
* PostgreSQL

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'backfiller'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install backfiller

## Usage

Assume we want to backfill `profiles.name` column from `users.first_name`, `users.last_name` columns.

Create backfill task into `db/backfill/profile_name.rb` and defined required methods:

#### Single worker execution query

```ruby
class Backfill::ProfileName

  def select_sql
    <<~SQL
      SELECT
        profile.id AS profile_id,
        CONCAT(users.first_name, ' ', users.last_name) AS profile_name
      FROM profiles
      INNER JOIN users ON
        users.id = profiles.user_id
      WHERE
        profiles.name IS NULL
    SQL
  end

  def execute_sql(connection, row)
    <<~SQL
      UPDATE profiles SET
        name = #{connection.quote(row['profile_name'])}
      WHERE
       id = #{connection.quote(row['profile_id'])}
    SQL
  end

end
```

#### Multiple worker execution queries

```ruby
class Backfill::ProfileName

  def select_sql
    <<~SQL
      SELECT
        profile.id AS profile_id,
        CONCAT(users.first_name, ' ', users.last_name) AS profile_name
      FROM profiles
      INNER JOIN users ON
        users.id = profiles.user_id
      WHERE
        profiles.name IS NULL
    SQL
  end

  def execute_sql(connection, row)
    [
      'BEGIN',
      <<~SQL,
        UPDATE profiles SET
          name = #{connection.quote(row['profile_name'])}
        WHERE
         id = #{connection.quote(row['profile_id'])} AND
        (SELECT pg_try_advisory_xact_lock(12345678)') = TRUE
      SQL
      'COMMIT'
    ]
  end

end

```

#### Custom row processing

```ruby
class Backfill::ProfileName

  def select_sql
    <<~SQL
      SELECT
        profile.id AS profile_id,
        CONCAT(users.first_name, ' ', users.last_name) AS profile_name
      FROM profiles
      INNER JOIN users ON
        users.id = profiles.user_id
      WHERE
        profiles.name IS NULL
    SQL
  end

  def process_row(connection, row)
    connection.execute 'BEGIN'
    if connection.select_value 'SELECT pg_try_advisory_xact_lock(12345678)'
      connection.execute <<~SQL
        INSERT INTO contacts(
          full_name
        )
        VALUES(
          #{connection.quote(row['profile_name'])},
        )
      SQL
    end
    connection.execute 'COMMIT'
  end

end

```
And then just run rake task:

```bash
$ rails db:backfill[profile_name]
```

## Configuration

For Rails application backfiller is initialized with next options

* task_directory: `RAILS_ROOT/db/backfill`
* task_namespace: `Backfill`
* batch_size: `1_000`
* cursor_threshold: `nil`
* connection_pool: `ApplicationRecord.connection_pool`
* logger: `ApplicationRecord.logger`

You may change it globally via `config/initializers/backfiller.rb`:

```ruby
Backfiller.configure do |config|
  config.foo = bar
end
```

Or specify some options in certain backfill task

```ruby
class Backfill::Foo
  def batch_size
    100
  end

  def cursor_threshold
    100_000
  end
end
```

## Authors

* [Andriy Yanko](http://ayanko.github.io)
