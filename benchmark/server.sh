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

cd narwhal && git fetch -f && git checkout -f main
export PATH="/root/.cargo/bin:${PATH}"
source "/root/.cargo/env"
rustup default stable
cd node && cargo build --quiet --release --features benchmark

node="./master/target/release/node"
client="./master/target/release/benchmark_client"
cd ..
rm ${node} ; rm benchmark_client ; ln -s ${node} . ; ln -s ${client} .

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

sleep 20

# Store all services in the list of IPs (first internal nodes then the leaf nodes)
dig A $service1 +short | sort -u | sed -e 's/$/ 1/' > ips
dig A $service +short | sort -u | sed -e 's/$/ 1/' >> ips

# Add ips to array
ourips=()
input="ips"
while IFS= read -r line
do
  ourips+=line
done < "$input"

sleep 5

# Cleanup past results.
rm -r .db-* ; rm .*.json ; mkdir -p results

cd benchmark
echo global_paramters.json > .parameters.json
mkdir logs

count=i
for index in ${count}:
  ./node generate_keys --filename ".node-${index}.json"

echo "{ \n authorities: {" > ".committee.json"

counter = 0
for file in ".node-*.json"
do
  ip=${ourips[counter]}
  thename=$(grep -m 1 '"name"' "${file}" | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"(.*?)".*/\1/')
  echo "'${thename}': {
           \n 'stake': 1,
           \n 'primary': {
           \n    'primary_to_primary': ${ip}:4000,
           \n    'worker_to_primary': ${ip}:4001,
           \n },
           \n 'workers': {
           \n    '0': {
           \n        'primary_to_worker': ${ip}:4002,
           \n        'worker_to_worker': ${ip}:4003,
           \n        'transactions': ${ip}:4004
           \n    },
           \n }
           \n }" >> ".committee.json"
  ((counter++))
  if $counter < count
    echo "," >> ".committee.json"
done

echo "} \n }" >> ".committee.json"

sleep 20

echo "Starting Application: #${i}"

## Startup Narwahl

# Startup Primaries
./node -vv run --keys ".node-${id}.json" --committee ".committee.json" --store ".db-${id}" --parameters ".parameters.json" primary > "logs/primary-${id}.log" &

# Startup Workers
./node -vv run --keys ".node-${id}.json" --committee ".committee.json" --store ".db-${id}-0" --parameters ".parameters.json" worker --id 0 &

sleep 40

#Configure Network restrictions
sudo tc qdisc add dev eth0 root netem delay ${latency}ms limit 400000 rate ${bandwidth}mbit &

sleep 25

# Start Clients on Host Machine
if [ ${id} == 0 ]; then
  rate_share = ceil(rate / committee.workers())
  for ip in ourips
  do
    ./benchmark_client ${ip}:4004 --size 32 --rate 50_000
fi

sleep 300

tmux kill-server


# Wait for the container to be manually killed
sleep 3000
