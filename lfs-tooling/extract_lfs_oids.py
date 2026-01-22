# Identify LFS OIDs on GHES for repo.
# Usage:
# $ ghe-repo <ORG>/<REPO> -c 'git rev-list --objects --all | awk '"'"'{print $1}'"'"' | sort -u | git cat-file --batch | python3 /tmp/extract_lfs_oids.py' > /tmp/all_lfs_oids.txt

import sys, re
ver = b"version https://git-lfs.github.com/spec/v1"
oid_re = re.compile(br"^oid sha256:([0-9a-f]{64})$")
oids = set()
s = sys.stdin.buffer

while True:
    hdr = s.readline()
    if not hdr:
        break
    parts = hdr.split()
    if len(parts) < 3:
        continue
    typ = parts[1]
    size = int(parts[2])
    data = s.read(size)
    s.read(1)

    if typ != b"blob" or size > 512 or not data.startswith(ver):
        continue

    for line in data.splitlines():
        m = oid_re.match(line)
        if m:
            oids.add(m.group(1).decode("ascii"))

for oid in sorted(oids):
    print(oid)
