# Redis Memory Exhaustion Script

This script is designed to exhaust the memory of a Redis server for testing purposes. It continuously inserts random data into Redis until the memory limit is reached, helping you test how Redis behaves under memory pressure and how your application handles such scenarios.

## Prerequisites

- Python 3.x
- `redis` Python library

## Installation

1. Install the `redis` Python library if you haven't already:

    ```sh
    pip install redis
    ```

2. Ensure you have a running Redis server. You can download and run Redis using Docker for quick setup:

    ```sh
    docker run --name redis-test -p 6379:6379 -d redis
    ```

## Configuration

Make sure your Redis server has a memory limit set. You can configure this in your `redis.conf` file, or set it dynamically using `redis-cli`:

```sh
redis-cli CONFIG SET maxmemory 300mb
redis-cli CONFIG SET maxmemory-policy noeviction
```

## Usage

1. Save the script as `redis_exhaustion.py`:

2. Run the script:

    ```sh
    python redis_exhaustion.py
    ```

## How It Works

- The script connects to the Redis server running on `localhost` at port `6379`.
- It generates random strings of 1KB and inserts them into Redis.
- The insertion is done using multiple threads to speed up the process.
- The script prints progress every 1000 keys and stops when the Redis memory limit is reached, indicated by the `OOM command not allowed` error.

## Notes

- This script is intended for testing purposes only. Running it on a production server can lead to unexpected behavior and should be done in a controlled environment.
- Adjust the `num_threads` and `keys_per_thread` variables based on your system's capabilities and requirements. (TBD)

## License

This project is licensed under the MIT License.
