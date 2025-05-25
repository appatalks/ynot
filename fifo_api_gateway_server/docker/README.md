> [!WARNING]
> WORK IN PROGRESS; В РОБОТІ

- [x] SSL
- [ ] Tuning

#### Install

1. Create a ```MySQL``` **User** and **Database** on external ```MySQL 8``` or better.
   ```mysql
   CREATE DATABASE IF NOT EXISTS api_gateway_fifo;
   CREATE USER IF NOT EXISTS 'api_gateway'@'%' IDENTIFIED BY 'your_mysql_password';
   GRANT ALL PRIVILEGES ON api_gateway_fifo.* TO 'api_gateway'@'%';
   FLUSH PRIVILEGES;
   ```

2. Clone Repository
   ```bash
   git clone https://github.com/appatalks/fifo_api_gateway_server.git
   cd api_fifo_limiter/docker
   ```

3. Adjust ```.env``` to set environment variables

#### Usage:

1. Start Server
   ```bash
   bash run.sh
   ```

2. Direct API to Server Endpoint
   ```bash
   curl -k -X POST https://<FIFO_API_SERVER>/api/save -H "Content-Type: application/json" -d '{"data": "example data"}'
   {"message":"Message enqueued: x_id=39-20240713141928","status":"success"}
   ```

3. Retrieve from FIFO Queue and Delete Data
   ```bash
   curl -k -X GET https://<FIFO_API_SERVER>/api/deliver
   {"data":"example data"}
   ```
   
4. Optional Target by Message ID to bypass queue:
   ```bash
   curl -k -X GET https://<FIFO_API_SERVER>/api/deliver?x_id=39-20240713141928
   {"data":"example data"}
   ```
