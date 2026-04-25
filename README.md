time_tracker
=====

Erlang microservice for employee work-time accounting via NFC cards.
It works as an RPC server over RabbitMQ with PostgreSQL persistence.

## Tech stack

- Erlang/OTP (OTP app + supervisors + worker processes)
- RabbitMQ RPC server (`application/json` request/response)
- PostgreSQL
- Unit tests (`eunit`)
- Docker Compose for local run

## Reliability and production behavior

- Dedicated OTP workers for DB and RabbitMQ connections.
- Automatic reconnect with backoff for PostgreSQL and RabbitMQ.
- Startup schema creation from `include/db/schema.sql` with safe retries after reconnect.
- Request handling wrapped with crash protection (`try/catch`) and structured error JSON.
- Validation for required fields in every endpoint.
- Unexpected errors are logged; service keeps running.

## RPC contract

Request JSON format:

```json
{
  "method": "/card/touch",
  "params": {
    "card_uid": "A1B2C3"
  }
}
```

Response format:

```json
{
  "status": "ok",
  "data": {}
}
```

Or error:

```json
{
  "status": "error",
  "error": {
    "code": "validation_error",
    "message": "Missing required fields"
  }
}
```

Queue: `time_tracker_rpc` (configurable via `RPC_QUEUE`).

## Implemented methods

- `/card/touch`
- `/card/assign`
- `/card/delete`
- `/card/list_by_user`
- `/card/delete_all_by_user`
- `/work_time/set`
- `/work_time/get`
- `/work_time/add_exclusion`
- `/work_time/get_exclusion`
- `/work_time/history_by_user`
- `/work_time/history`
- `/work_time/statistics_by_user`
- `/work_time/statistics`

## Environment variables

- `PG_HOST`, `PG_PORT`, `PG_USER`, `PG_PASSWORD`, `PG_DATABASE`
- `RABBIT_HOST`, `RABBIT_PORT`, `RABBIT_USER`, `RABBIT_PASSWORD`, `RABBIT_VHOST`
- `RPC_QUEUE`
- `RECONNECT_BACKOFF_MS`

Base defaults are also stored in `config/sys.config`.

## Local run

Build and run:

```bash
make compile
make test
```

Run infra + service:

```bash
docker compose up --build
```

Run tests in compose:

```bash
docker compose run --rm unit-tests
```
