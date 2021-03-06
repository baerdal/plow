#!/usr/bin/env bash
datasource="elasticsearch"
tool="uperf"
function="compare"
_es=search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com
_es_port=80
_es_baseline=search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com
_es_baseline_port=80


if [[ ${ES_SERVER} ]] && [[ ${ES_PORT} ]] && [[ ${ES_USER} ]] && [[ ${ES_PASSWORD} ]]; then
  _es=${ES_USER}:${ES_PASSWORD}@${ES_SERVER}
  _es_port=${ES_PORT}
elif [[ ${ES_SERVER} ]] && [[ ${ES_PORT} ]]; then
  _es=${ES_SERVER}
  _es_port=${ES_PORT}
fi

if [[ ${ES_SERVER_BASELINE} ]] && [[ ${ES_PORT_BASELINE} ]] && [[ ${ES_USER_BASELINE} ]] && [[ ${ES_PASSWORD_BASELINE} ]]; then
  _es_baseline=${ES_USER_BASELINE}:${ES_PASSWORD_BASELINE}@${ES_SERVER_BASELINE}
  _es_baseline_port=${ES_PORT_BASELINE}
elif [[ ${ES_SERVER_BASELINE} ]] && [[ ${ES_PORT_BASELINE} ]]; then
  _es=${ES_SERVER_BASELINE}
  _es_port=${ES_PORT_BASELINE}
fi

if [[ ${COMPARE} != "true" ]]; then
  compare_uuid=$1
else
  base_uuid=$1
  compare_uuid=$2
fi

git clone https://github.com/cloud-bulldozer/touchstone
cd touchstone
python3 -m venv ./compare
source ./compare/bin/activate
pip3 install -r requirements.txt
python3 setup.py develop
if [[ $? -ne 0 ]] ; then
  echo "Unable to execute compare - Failed to install touchstone"
  exit 1
fi
set -x
touchstone_compare $tool $datasource ripsaw -url $_es_baseline:$_es_baseline_port $_es:$_es_port -u $base_uuid $compare_uuid -o yaml | tee ../compare_output_${!#}p.yaml
if [[ $? -ne 0 ]] ; then
  echo "Unable to execute compare - Failed to run touchstone"
  exit 1
fi
