import redis
import string
import random

# Connect to the Redis server
r = redis.Redis(host='localhost', port=6379, db=0)

def random_string(length=1024):
    """Generate a random string of fixed length."""
    letters = string.ascii_letters + string.digits
    return ''.join(random.choice(letters) for i in range(length))

def exhaust_memory():
    i = 0
    try:
        while True:
            key = f"key:{i}"
            value = random_string()
            r.set(key, value)
            i += 1
            if i % 1000 == 0:
                print(f"Inserted {i} keys")
    except redis.exceptions.ConnectionError as e:
        print(f"Redis crashed or refused connection: {e}")

if __name__ == "__main__":
    exhaust_memory()
