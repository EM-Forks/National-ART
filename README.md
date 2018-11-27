# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

## DDE Configurations

In order for the application to communicate with DDE follow the following steps to configure the integration:

### Database migration

Do a rails database migration to add a table which will be used to store dde users for the application:
```
  $ rails db:migrate
```
