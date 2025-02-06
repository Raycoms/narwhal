#!/bin/bash

trap "docker stack rm narwhalservice" EXIT

FILENAME=narwahl.yaml
EXPORT_FILENAME=narwahl-temp.yaml

ORIGINAL_STRING=thecmd
QTY1_STRING=theqty1
QTY2_STRING=theqty2

FILENAME2="experiments"
LINES=$(cat $FILENAME2 | grep "^[^#;]")
LOG_DIR="logs"

# Each LINE in the experiment file is one experimental setup
for LINE in $LINES
do

  echo '---------------------------------------------------------------'
  echo $LINE
  IFS=':' read -ra split <<< "$LINE"

  sed  "s/${ORIGINAL_STRING}/${split[0]}/g" $FILENAME > $EXPORT_FILENAME
  sed  -i "s/${QTY1_STRING}/${split[1]}/g" $EXPORT_FILENAME
  #sed  -i "s/${QTY2_STRING}/${split[2]}/g" $EXPORT_FILENAME

  total_qty=$((split[1]))

  echo '**********************************************'
  echo "*** This setup needs ${split[3]} physical machines and has total of ${total_qty} processes! ***"
  echo '**********************************************'

  for i in {1..5}
  do
        # Deploy experiment
        docker stack deploy -c narwahl-temp.yaml narwhalservice &
        # Docker startup time + 5*60s of experiment runtime
        sleep 500

        # Cleanup old logs
        rm $LOG_DIR/*

        # Get the list of nodes
        nodes=$(docker node ls --format '{{.Hostname}}')

        # Loop through each node
        for node in $nodes; do
            echo "Processing node: $node"

            # Get the container IDs for this node
            containers=$(ssh -o StrictHostKeyChecking=no -i ~root/.ssh/interid $node "docker ps -q -f name='server'")

            for container in $containers; do
                # "Fetching logs from container: $container on node: $node"

                ssh -o StrictHostKeyChecking=no -i ~root/.ssh/interid $node "docker exec $container bash -c 'mkdir -p /extract; cp -f /narwhal/benchmark/logs/* /extract'"
                ssh -o StrictHostKeyChecking=no -i ~root/.ssh/interid $node "docker cp $container:/extract /tmp/logs_container"
                scp -o StrictHostKeyChecking=no -i ~root/.ssh/interid -r $node:/tmp/logs_container/* $LOG_DIR/
                ssh -o StrictHostKeyChecking=no -i ~root/.ssh/interid $node "rm -rf /tmp/logs_container"
            done
        done

        echo "Logs collected in $LOG_DIR"

        python3 benchmark/process_logs.py
        docker stack rm narwhalservice
        docker container prune -f
        sleep 30
  done
done
