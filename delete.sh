#/bin/bash

kubectl delete -f elasticsearch/
kubectl delete -f kibana/
kubectl delete -f logstash/
kubectl delete -f filebeat/
