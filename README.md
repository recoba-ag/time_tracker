time_tracker
============

Erlang microservice for employee work-time accounting via NFC cards.  
The service exposes an RPC interface over **RabbitMQ** (request/reply) and stores data in **PostgreSQL**.

## Tech stack

- Erlang/OTP (application, supervisors, `gen_server` workers)
- RabbitMQ (RPC queue, JSON over AMQP)
- PostgreSQL (via `epgsql`)
- JSON encode/decode (`jsx`), request validation (`liver`)
- EUnit tests
- Docker Compose for local run

## Reliability and production behavior

- Separate OTP workers for the DB and RabbitMQ connections.
- Reconnect with backoff if PostgreSQL or RabbitMQ drops.
- Schema: SQL is loaded at startup from `priv/db/schema.sql`, with fallback to `include/db/schema.sql` if the release `priv` dir is unavailable.
- RPC handling is protected with `try/catch` so a bad request does not crash the consumer; errors are returned as JSON.
- Liver validates required fields and types for each method.

## RPC contract

Request (JSON body, `Content-Type: application/json` on the queue consumer):

```json
{
  "method": "/card/touch",
  "params": {
    "card_uid": "A1B2C3"
  }
}
```

Success response: `data` is the payload for that method (object, array, or nested structure — see below). Errors always use `status: "error"` and an `error` object with `code` and `message`.

```json
{
  "status": "ok",
  "data": {}
}
```

```json
{
  "status": "error",
  "error": {
    "code": "validation_error",
    "message": "…"
  }
}
```

- **Queue**: `time_tracker_rpc` (override with `RPC_QUEUE`).

## Implemented methods

| Method | Purpose |
|--------|--------|
| `/card/touch` | Register next in/out for a card |
| `/card/assign` | Assign card to user |
| `/card/delete` | Remove card |
| `/card/list_by_user` | List cards for user |
| `/card/delete_all_by_user` | Remove all user cards |
| `/work_time/set` | Set work schedule (requires IANA `schedule_timezone`, validated against PostgreSQL `pg_timezone_names`) |
| `/work_time/get` | Get work schedule (`schedule_timezone` included) |
| `/work_time/add_exclusion` | Add exclusion (come later / leave earlier / full day) |
| `/work_time/get_exclusion` | List exclusions for user (`start_datetime` / `end_datetime` as local wall time in `schedule_timezone`; see below) |
| `/work_time/history_by_user` | Touch history for one user (`touched_at` in user’s `schedule_timezone`; see below) |
| `/work_time/history` | Touch history, grouped by user (see below) |
| `/work_time/statistics_by_user` | Attendance-style stats for one user and period |
| `/work_time/statistics` | Stats for all users that appear in the last `limit` global history rows |

### History response shape

- **`/work_time/history_by_user`**: `data` is a single object:
  - `user_id` — user id
  - `events` — array of touch events, each with `user_id`, `card_uid`, `touched_at`, `event_type` (`"in"` / `"out"`)
  - **`touched_at`** — wall clock in that user’s **`work_schedules.schedule_timezone`**, formatted `YYYY-MM-DDTHH:MM:SS` (no `Z` suffix; not UTC). If the user has no schedule row, **UTC** is used for display.
- **`/work_time/history`**: `data` is a **list** of objects (no extra `history` wrapper):
  - `user_id` — user id
  - `events` — same event objects as above (each `touched_at` uses **that** user’s schedule timezone from the join).

### Exclusions list (`/work_time/get_exclusion`)

- **`schedule_timezone`** — echo of the user’s IANA zone from `work_schedules` (or **`UTC`** if no row).
- **`exclusions[].start_datetime` / `end_datetime`** — same local-wall `YYYY-MM-DDTHH:MM:SS` convention as `touched_at` above (the instant stored in the DB, shown in the schedule zone).

## Statistics: time window (`statistics_by_user`)

`WindowStart`, `Now`, `week`/`month`/`year` clipping, and the **\[WindowStart, Now\]** window use **Erlang universal time** (**UTC**) on the absolute timeline.

How touches and shifts are folded into scored **days** additionally depends on `schedule_timezone` when it is not UTC‑equivalent (see **Work schedule timezone** above).

The evaluated interval is **\[WindowStart, Now\]** (inclusive in implementation via touch range and per-day steps).

| `period` | `WindowStart` |
|----------|----------------|
| `week` | Start of the **current ISO week** (Monday 00:00:00) |
| `month` | First day of the **current calendar month** 00:00:00 |
| `year` | January 1 of the **current year** 00:00:00 |
| `all` | First known touch of the user, or `Now` if there are no touches |

For `week`, `month`, and `year`, the real **WindowStart** is the **later** of the calendar boundary in the table and the user’s **first** `touch_events` row (`MIN(touched_at)`). Days before the user had any touch are not included in the stats (same idea as `all`, but still bounded by the chosen calendar period on the right).

`Now` is the current time when the request is processed.

## Statistics: batch window (`/work_time/statistics`)

The service reads the last `limit` rows from the global history table. A **baseline** interval is from the **earliest** to the **latest** `touched_at` among those rows (converted to the same internal “Gregorian seconds” time base as the rest of the app). Touches and exclusions are loaded from the database for that full interval.

For **each user**, attendance is evaluated from **max(baseline start, first touch)** to the baseline end, where **first touch** is `MIN(touched_at)` over all `touch_events` for that user (not only rows inside the batch sample). Same idea as clipping by first touch on `statistics_by_user`.

## Work schedule timezone (`schedule_timezone`)

`work_schedules.schedule_timezone` is an **IANA** name (`Europe/Kyiv`, `UTC`, …). Shift `start_time` / `end_time` are interpreted on each **local calendar date** in that zone, then converted internally to absolute instants for overlaps with exclusions and touches.

If `schedule_timezone` is **`UTC`** (or other names treated as UTC in code, such as **`GMT`** / **`Etc/UTC`**), grouping by calendar day matches the legacy **UTC‑midnight day** semantics.

If it is non‑UTC, **per‑day grouping** (“which touches belong to which workday”), shift bounds, and the meaning of **“today”** for deciding whether today is scored follow the **`schedule_timezone` calendar**.

Period boundaries for **`statistics_by_user`** (`week` / `month` / `year` / clipping by first touch) still use Erlang universal time (**UTC**) as before; shift alignment and grouping use the timezone above when it is not UTC‑equivalent.

## Statistics: metric rules (`late_*`, `early_*`, `worked_days`)

Metrics are computed only on **scheduled workdays** (weekday in the user’s `work_schedules.days`), and only for days where the **scheduled shift** `[shift_start, shift_end]` overlaps the statistics time window.  
If a **`full day`** exclusion fully covers the whole shift window for that day, the day is **skipped** (no counters).

A day is **included in scoring** if:

- it is a **calendar day before “today”** in the user’s **schedule_timezone** calendar, or
- it is **that calendar “today”** and the current time is **on or after the scheduled shift start** on the absolute timeline (so “today before shift” is not scored at all).

**Touch semantics for the day** (in order):

- **`first` `in`**: minimum timestamp among `in` events on that calendar day (in **`schedule_timezone`**, unless it is UTC‑equivalent — then UTC).
- **last `out`**: maximum timestamp among `out` events on that calendar day.
- If **today** is still **before the scheduled end of the shift** and there is **no** `out` yet, only **late**-related fields are updated for that day; **early** and **worked** stay **0** (in-progress day).

**`/work_time/add_exclusion`**: `start_datetime` and `end_datetime` must be ISO‑8601 with `Z` or `±HH:MM` suffix. Only the **numeric date and time digits** matter: they are interpreted as **local wall‑clock in `schedule_timezone`** (the user’s stored schedule zone). Offset suffixes are **not** used to define the stored instant — this prevents mismatches when clients send inconsistent offsets.

**Exclusions (intervals as absolute timestamps after conversion above):**

- **`come later`**: intervals that **overlap the scheduled shift window** that day extend the **latest allowed first `in`** up to each row’s **`end` time** (`max` of shift start and those ends). First `in` **after** nominal `shift_start` but **on or before** that deadline counts as **late with reason** (`late_with_reason`). First `in` **after** the deadline counts as **late without reason** (`late_without_reason`).
- **`leave earlier`**: if the last `out` lies inside a `leave earlier` row’s `[start, end]`, leaving before shift end is **with reason** (not “early without”).
- Arriving **on or before** `shift_start` is never “late” for reason counting (including “on time by definition”).

**Counters (per scored day, summed over the period):**

| Field | Rule |
|--------|------|
| `late_without_reason` | First `in` is **strictly after** the **deadline** (see `come later` above: at least `shift_start`, or the **end** of overlapping `come later` rows if greater). If there is **no** `in` on that day, it counts as **1** in the no-show sense (no entry). |
| `late_with_reason` | First `in` is **after** nominal `shift_start` but **not after** the deadline (allowed “come later” arrival). |
| `early_without_reason` | After a finished evaluation: last `out` is **strictly before** `shift_end`, and the `out` is **not** in a `leave earlier` window; *or* (closed day) `in` exists but `out` is missing — treated as early leave without an approved reason. |
| `early_with_reason` | Last `out` is before `shift_end`, and the `out` falls inside a `leave earlier` exclusion. |
| `worked_days` | The day has both `in` and `out`, `late_without_reason` and `early_without_reason` for that day are both **0**, and `last_out >= first_in`. Free schedule / “no fixed hours” path uses a simpler pairing count (see code: `free_count`). |

If there is **no** work schedule row for the user, stats are **all zeros** (with the usual `user_id` / `period` echo fields on `statistics_by_user`).

**Free schedule** (`free_schedule: true`): the four late/early counters are **0**; `worked_days` is the **minimum** of the number of `in` and `out` events in the window (pairing-style count, not per calendar day).

## Environment variables

- **PostgreSQL**: `PG_HOST`, `PG_PORT`, `PG_USER`, `PG_PASSWORD`, `PG_DATABASE`
- **RabbitMQ**: `RABBIT_HOST`, `RABBIT_PORT`, `RABBIT_USER`, `RABBIT_PASSWORD`, `RABBIT_VHOST`
- **RPC**: `RPC_QUEUE`
- **Backoffs**: `RECONNECT_BACKOFF_MS`

Defaults are also in `config/sys.config`. Under Docker Compose, `PG_HOST=postgres` and `RABBIT_HOST=rabbitmq` match the service names.

## Local run

```bash
rebar3 compile
rebar3 eunit
# optional static analysis
rebar3 dialyzer
```

**Unit tests** (`test/time_tracker_time_tests.erl`, `test/time_tracker_attendance_tests.erl`): periods and time helpers; core attendance rules — schedule vs free day, late/early with and without reasons, full-day and come/leave exclusions, weekend ignored, absence, in without out, first-in/last-out over multiple events, and DB-row decoding for touches/exclusions. Scenarios use a fixed past date so “today” logic does not make tests flaky.

With Docker (Postgres, RabbitMQ, app):

```bash
docker compose up --build
```

EUnit in a one-off container:

```bash
docker compose run --rm unit-tests
```

`Makefile` targets `compile`, `test`, `shell`, and `release` wrap the same `rebar3` commands.
