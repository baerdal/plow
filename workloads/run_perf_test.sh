#!/usr/bin/env bash
set -x

_es=search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com
_es_port=80

cloud_name=$1
if [ "$cloud_name" == "" ]; then
  cloud_name="test_cloud"
fi

echo "Starting test for cloud: $cloud_name"

oc create ns my-ripsaw
oc create ns backpack

cat << EOF | oc create -f -
---
apiVersion: operators.coreos.com/v1alpha2
kind: OperatorGroup
metadata:
  name: operatorgroup
  namespace: my-ripsaw
spec:
  targetNamespaces:
  - my-ripsaw
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: my-ripsaw
  namespace: my-ripsaw
spec:
  channel: alpha
  name: ripsaw
  source: community-operators
  sourceNamespace: openshift-marketplace
EOF

oc apply -f https://raw.githubusercontent.com/cloud-bulldozer/ripsaw/0.0.1/resources/crds/ripsaw_v1alpha1_ripsaw_crd.yaml
oc wait --for condition=ready pods -l name=benchmark-operator -n my-ripsaw --timeout=2400s

oc apply -f https://raw.githubusercontent.com/dry923/backpack/always_on/backpack.yaml
oc wait --for condition=ready pods -l name=backpack  -n backpack --timeout=2400s
for node in $(oc get pods -n backpack --selector=name=backpack -o name); do
  pod=$(echo $node | awk -F'/' '{print $2}')
  oc -n backpack exec $pod -- python3 stockpile-wrapper-always.py -s $_es -p $_es_port -u No
done

cat << EOF | oc create -f -
apiVersion: ripsaw.cloudbulldozer.io/v1alpha1
kind: Benchmark
metadata:
  name: fio-benchmark
  namespace: my-ripsaw
spec:
  elasticsearch:
    server: search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com
    port: 80
  clustername: $cloud_name
  test_user: ${cloud_name}-ci
  workload:
    name: "fio_distributed"
    args:
      samples: 3
      servers: 1
      pin_server: ''
      jobs:
        - write
      bs:
        - 2300B
      numjobs:
        - 1
      iodepth: 4
      read_runtime: 60
      read_ramp_time: 5
      filesize: 23MiB
      log_sample_rate: 1000
#######################################
#  EXPERT AREA - MODIFY WITH CAUTION  #
#######################################
  global_overrides:
    - ioengine=sync
    - fdatasync=1
  job_params:
#    - jobname_match: w
#      params:
    - jobname_match: read
      params:
        - time_based=1
        - runtime={{ fiod.read_runtime }}
        - ramp_time={{ fiod.read_ramp_time }}
    - jobname_match: rw
      params:
        - rwmixread=50
        - time_based=1
        - runtime={{ fiod.read_runtime }}
        - ramp_time={{ fiod.read_ramp_time }}
    - jobname_match: readwrite
      params:
        - rwmixread=50
        - time_based=1
        - runtime={{ fiod.read_runtime }}
        - ramp_time={{ fiod.read_ramp_time }}
#    - jobname_match: <search_string>
#      params:
#        - key=value
EOF

fio_state=1
for i in {1..60}; do
  oc get -n my-ripsaw benchmarks | grep "fio-benchmark" | grep Complete
  if [ $? -eq 0 ]; then
	  echo "Workload done"
          oc logs -n my-ripsaw pods/$(oc get pods | grep client|awk '{print $1}')
          fio_state=$?
	  break
  fi
  sleep 60
done

if [ "$fio_state" == "1" ] ; then
  echo "Workload failed"
  exit 1
fi

oc delete benchmark/fio-benchmark
sleep 30

cat << EOF | oc create -f -
apiVersion: ripsaw.cloudbulldozer.io/v1alpha1
kind: Benchmark
metadata:
  name: uperf-benchmark
  namespace: my-ripsaw
spec:
  elasticsearch:
    server: search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com
    port: 80
  clustername: $cloud_name
  test_user: ${cloud_name}-ci
  workload:
    name: uperf
    args:
      hostnetwork: false
      serviceip: false
      pin: false
      pin_server: ""
      pin_client: ""
      multus:
        enabled: false
      samples: 3
      pair: 1
      nthrs:
        - 1
      protos:
        - tcp
        - udp
      test_types:
        - stream
        - rr
      sizes:
        - 64
        - 1024
        - 16384
      runtime: 60
EOF

uperf_state=1
for i in {1..120}; do
  oc get -n my-ripsaw benchmarks | grep "uperf-benchmark" | grep Complete
  if [ $? -eq 0 ]; then
	  echo "Workload done"
          oc logs -n my-ripsaw pods/$(oc get pods | grep client|awk '{print $1}')
          fio_state=$?
	  break
  fi
  sleep 60
done

if [ "$uperf_state" == "1" ] ; then
  echo "Workload failed"
  exit 1
fi


exit 0
