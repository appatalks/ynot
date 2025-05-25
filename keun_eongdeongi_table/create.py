import json
import random
import time
import uuid

# Parameters
file_name = 'webhook_deliveries.sql'
num_records = 20000000  # Increase the number of records to insert to reach ~20GB
batch_size = 1000  # Number of records per batch

# Open the file for writing
with open(file_name, 'w') as f:
    # Write the initial database and table creation commands
    f.write("USE github_enterprise;\n\n")
    f.write("""
CREATE TABLE IF NOT EXISTS webhook_deliveries (
    id INT AUTO_INCREMENT PRIMARY KEY,
    guid VARCHAR(255) NOT NULL,
    parent VARCHAR(255),
    hook_id INT,
    repo_id INT,
    installation_id INT,
    url VARCHAR(255),
    content_type VARCHAR(50),
    event VARCHAR(50),
    action VARCHAR(50),
    redelivery INT,
    requested_public_key_signature INT,
    allowed_insecure_ssl INT,
    secret VARCHAR(255),
    status INT,
    message VARCHAR(255),
    duration INT,
    github_request_id VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    request_headers JSON,
    response_headers JSON,
    response_body TEXT
);\n\n
""")

    # Function to generate random JSON headers
    def generate_headers():
        return json.dumps({
            "Accept": ["/"],
            "Content-Type": ["application/json"],
            "User-Agent": ["GitHub-Hookshot/" + str(uuid.uuid4())[:8]],
            "X-GitHub-Delivery": [str(uuid.uuid4())],
            "X-GitHub-Enterprise-Host": ["git.example.com"],
            "X-GitHub-Enterprise-Version": ["3.12.4"],
            "X-GitHub-Event": ["ping"],
            "X-GitHub-Hook-ID": [str(random.randint(1, 100))],
            "X-GitHub-Hook-Installation-Target-ID": [str(random.randint(1, 100))],
            "X-GitHub-Hook-Installation-Target-Type": ["organization"]
        })

    # Function to generate a random payload
    def generate_payload():
        payload = {
            "guid": str(uuid.uuid4()),
            "parent": random.choice(["organization-" + str(random.randint(1, 100)), "repository-" + str(random.randint(1, 100))]),
            "hook_id": random.randint(1, 100),
            "repo_id": random.choice([None, random.randint(1, 100)]),
            "installation_id": random.choice([None, random.randint(1, 100)]),
            "url": "https://example.com/" + str(uuid.uuid4()),
            "content_type": "json",
            "event": "ping",
            "action": None,
            "redelivery": random.randint(0, 1),
            "requested_public_key_signature": random.randint(0, 1),
            "allowed_insecure_ssl": random.randint(0, 1),
            "secret": None,
            "status": 200,
            "message": "OK",
            "duration": random.randint(100, 2000),
            "github_request_id": str(uuid.uuid4()),
            "request_headers": generate_headers(),
            "response_headers": generate_headers(),
            "response_body": None
        }
        return payload

    # Generate and write the insert statements in batches
    for i in range(0, num_records, batch_size):
        f.write("INSERT INTO webhook_deliveries (guid, parent, hook_id, repo_id, installation_id, url, content_type, event, action, redelivery, requested_public_key_signature, allowed_insecure_ssl, secret, status, message, duration, github_request_id, request_headers, response_headers, response_body) VALUES\n")
        values = []
        for j in range(batch_size):
            payload = generate_payload()
            values.append("('{}', '{}', {}, {}, {}, '{}', '{}', '{}', {}, {}, {}, {}, {}, {}, '{}', {}, '{}', '{}', '{}', {})".format(
                payload['guid'], payload['parent'], payload['hook_id'],
                'NULL' if payload['repo_id'] is None else payload['repo_id'],
                'NULL' if payload['installation_id'] is None else payload['installation_id'],
                payload['url'], payload['content_type'], payload['event'],
                'NULL' if payload['action'] is None else payload['action'],
                payload['redelivery'], payload['requested_public_key_signature'],
                payload['allowed_insecure_ssl'], 'NULL' if payload['secret'] is None else payload['secret'],
                payload['status'], payload['message'], payload['duration'],
                payload['github_request_id'], json.dumps(payload['request_headers']).replace("'", "''"),
                json.dumps(payload['response_headers']).replace("'", "''"),
                'NULL' if payload['response_body'] is None else payload['response_body']
            ))
        f.write(",\n".join(values) + ";\n\n")
