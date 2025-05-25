#!/bin/bash

# Run docker-compose build and redirect output to build.log and stdout
mkdir -p logs
docker-compose build 2>&1 | tee logs/build.log

# Check the status of the build
if [ ${PIPESTATUS[0]} -eq 0 ]; then
  echo "Build succeeded. Logs are in build.log"
  
  # Start the containers and log the output to run.log and stdout
  # docker-compose up --remove-orphans 2>&1 | tee logs/run.log # Pondering if I should keep --remove-orphans
  docker-compose up 2>&1 | tee logs/run.log
  docker logs -f docker_nginx_1 2>&1 | tee logs/nginx.log
  docker logs -f docker_flask_1 2>&1 | tee logs/flask.log
else
  echo "Build failed. Check build.log for details."
fi
