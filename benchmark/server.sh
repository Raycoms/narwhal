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
service1="server1-$NARWAHL_UUID"

cd narwhal && git pull && git fetch -f && git checkout -f main
export PATH="/root/.cargo/bin:${PATH}"
source "/root/.cargo/env"
rustup default stable

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

for ip in $(dig A $service1 +short | sort -u)
do
  for myip in $(ifconfig -a | awk '$1 == "inet" {print $2}')
  do
    if [ ${ip} == ${myip} ]
    then
      id=${i}
      echo "This is: ${ip}"
    fi
  done
  ((i++))
done
for ip in $(dig A $service +short | sort -u)
do
  for myip in $(ifconfig -a | awk '$1 == "inet" {print $2}')
  do
    if [ ${ip} == ${myip} ]
    then
      id=${i}
      echo "This is: ${ip}"
    fi
  done
  ((i++))
done

echo "collected ips"

sleep 20

# Store all services in the list of IPs (first internal nodes then the leaf nodes)
dig A $service1 +short | sort -u | sed -e 's/$/ 1/' > ips
dig A $service +short | sort -u | sed -e 's/$/ 1/' >> ips

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

counter=0
for file in .node-*.json;
do
  ip=${ourips[counter]}
  thename=$(grep -m 1 '"name"' "${file}" | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"(.*?)".*/\1/')
  echo "\"${thename}\": {
            \"stake\": 1,
            \"primary\": {
               \"primary_to_primary\": \"${ip}:4000\",
               \"worker_to_primary\": \"${ip}:4001\"
            },
            \"workers\": {
               \"0\": {
                   \"primary_to_worker\": \"${ip}:4002\",
                   \"worker_to_worker\": \"${ip}:4003\",
                   \"transactions\": \"${ip}:4004\"
               }
            }
            }" >> ".committee.json"
  ((counter++))
  if [[ $counter -lt $count ]]; then
    echo "," >> ".committee.json"
  fi
done

echo " }
}" >> ".committee.json"

cat ".committee.json"

sleep 20

echo "Starting Application: #${i}"

## Startup Narwahl

# Startup Primaries
./../target/release/node -vv run --keys ".node-${id}.json" --committee ".committee.json" --store ".db-${id}" --parameters ".parameters.json" primary |& tee "logs/primary-${id}.log" &

# Startup Workers
./../target/release/node -vv run --keys ".node-${id}.json" --committee ".committee.json" --store ".db-${id}-0" --parameters ".parameters.json" worker --id 0 |& tee "logs/worker-${id}.log" &

sleep 40

#Configure Network restrictions
sudo tc qdisc add dev eth0 root netem delay ${latency}ms limit 400000 rate ${bandwidth}mbit &

sleep 25

# Start Clients on Host Machine
./../target/release/benchmark_client ${ip}:4004 --size 32 --rate ${fanout} |& tee "logs/client-${id}-0.log" &

sleep 300

tmux kill-server


# Wait for the container to be manually killed
sleep 3000
