#!/bin/bash

trap "docker stack rm narwahlservice" EXIT

FILENAME=narwahl.yaml
EXPORT_FILENAME=narwahl-temp.yaml

ORIGINAL_STRING=thecmd
QTY1_STRING=theqty1
QTY2_STRING=theqty2

FILENAME2="experiments"
LINES=$(cat $FILENAME2 | grep "^[^#;]")

# Each LINE in the experiment file is one experimental setup
for LINE in $LINES
do

  echo '---------------------------------------------------------------'
  echo $LINE
  IFS=':' read -ra split <<< "$LINE"

  sed  "s/${ORIGINAL_STRING}/${split[0]}/g" $FILENAME > $EXPORT_FILENAME
  sed  -i "s/${QTY1_STRING}/${split[1]}/g" $EXPORT_FILENAME
  sed  -i "s/${QTY2_STRING}/${split[2]}/g" $EXPORT_FILENAME

  total_qty=$((split[1]+split[2]))

  echo '**********************************************'
  echo "*** This setup needs ${split[3]} physical machines and has total of ${total_qty} machines! ***"
  echo '**********************************************'

  for i in {1..5}
  do
        # Deploy experiment
        docker stack deploy -c narwahl-temp.yaml narwahlservice &
        # Docker startup time + 5*60s of experiment runtime
        sleep 450
        
        # Collect and print results.
        for container in $(docker ps -q -f name="server")
        do
            docker exec $container bash -c "mkdir -p /extract; cp -f /narwhal/benchmark/logs/primary* /extract"
            docker cp $container:/extract logs
            cp logs/extract/* logs
        done

        python3 benchmark/process_logs.py
        docker stack rm narwahlservice
        sleep 30

  done
done
