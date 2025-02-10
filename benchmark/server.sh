trap 'exit 0' INT

sleep 2

# Initial Parameter Setup
crypto=$1
fanout=$2
pipedepth=$3
pipelatency=$4
latency=$5
bandwidth=$6
blocksize=$7

# Get Service-name
service="server-$NARWAHL_UUID"

cd narwhal && git pull && git fetch -f && git checkout -f main
export PATH="/root/.cargo/bin:${PATH}"
source "/root/.cargo/env"
rustup default stable
export RUST_BACKTRACE=1

cd node && cargo build --quiet --release --features benchmark

node="./target/release/node"
client="./target/release/benchmark_client"
cd ..
#ln -s ${node} . ; ln -s ${client} .

echo "syncing time"
sleep 30

id=0
i=0

# Go through the list of servers of the given services to identify the number of servers and the id of this server.
themyip=0
for ip in $(dig A $service +short | sort -u | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n)
do
  for myip in $(ifconfig -a | awk '$1 == "inet" {print $2}')
  do
    if [ ${ip} == ${myip} ]
    then
      id=${i}
      themyip=${myip}
      echo "This is: ${ip} ${id}"
    fi
  done
  ((i++))
done

echo "collected ips"

sleep 20

# Store all services in the list of IPs
dig A $service +short | sort -u | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | sed -e 's/$/ 1/' > ips

cat ips

# Add ips to array
ourips=()
input="ips"
while IFS= read -r line
do
  # Extract the first word using parameter expansion
  first_word=${line%% *}
  ourips+=("$first_word")
done < "$input"

echo "${ourips[@]}"

sleep 5

cd benchmark
cp global_parameters.json .parameters.json
mkdir logs

count=$i
for index in $(seq 0 $((count - 1)));
do
  ./../target/release/node generate_keys --filename ".node-${index}.json"
done

echo "{" > ".committee.json"
echo " \"authorities\": {" >> ".committee.json"

ports=()

counter=0
ipstart=5000
myport=0
for ((i=0; i<count; i++));
do
  localip=${ourips[$counter]}
  thename=$(grep -m 1 '"name"' ".node-${i}.json" | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"(.*?)".*/\1/')
  echo "\"${thename}\": {
            \"stake\": 1,
            \"primary\": {
               \"primary_to_primary\": \"${localip}:${ipstart}\",
               \"worker_to_primary\": \"${localip}:$((ipstart + 1))\"
            },
            \"workers\": {
               \"0\": {
                   \"primary_to_worker\": \"${localip}:$((ipstart + 2))\",
                   \"worker_to_worker\": \"${localip}:$((ipstart + 3))\",
                   \"transactions\": \"${localip}:$((ipstart + 4))\"
               }
            }
            }" >> ".committee.json"
  if [ "${localip}" = "${themyip}" ]; then
        myport=$((ipstart + 4))
  fi
  ports+=("$localip:$((ipstart + 4))")

  ((counter++))
  ipstart=$((ipstart + 10))
  if [[ $counter -lt $count ]]; then
    echo "," >> ".committee.json"
  fi
done

echo " }
}" >> ".committee.json"

cat ".committee.json"

sleep 5

echo "Starting Application: #${id}"

## Startup Narwahl

# Startup Primaries

tmux new -d -s "primary-${id}" "./../target/release/node -v run --keys .node-${id}.json --committee .committee.json --store .db-${id} --parameters .parameters.json primary |& tee logs/primary-${id}.log"

tmux new -d -s "worker-${id}" "./../target/release/node -v run --keys .node-${id}.json --committee .committee.json --store .db-${id}-0 --parameters .parameters.json worker --id 0 |& tee logs/worker-${id}.log"

sleep 20

#Configure Network restrictions
sudo tc qdisc add dev eth0 root netem delay ${latency}ms limit 400000 rate ${bandwidth}mbit &

sleep 5


echo "--nodes ${ports[*]}"
tmux new -d -s "client-${id}" "./../target/release/benchmark_client ${myip}:${myport} --size 32 --rate ${fanout} --nodes ${ports[*]} |& tee logs/client-${id}-0.log"

sleep 300

tmux kill-server

# Wait for the container to be manually killed
sleep 3000
