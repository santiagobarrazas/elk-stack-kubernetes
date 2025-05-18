#!/bin/bash

# Salir inmediatamente si un comando falla y mostrar comandos ejecutados
set -ex

NAMESPACE="logging"

# --- 0. Namespace ---
echo "Paso 0: Asegurando el namespace '$NAMESPACE'..."
kubectl get namespace "$NAMESPACE" > /dev/null 2>&1 || kubectl create namespace "$NAMESPACE"
echo "Namespace '$NAMESPACE' listo."
echo "----------------------------------------------------"

# --- 1. Elasticsearch ---
echo "Paso 1: Desplegando Elasticsearch..."
kubectl apply -f ./elasticsearch/00-elasticsearch-credentials.yaml -n "$NAMESPACE"
kubectl apply -f ./elasticsearch/01-elasticsearch-sa.yaml -n "$NAMESPACE"
kubectl apply -f ./elasticsearch/02-elasticsearch-service.yaml -n "$NAMESPACE"
kubectl apply -f ./elasticsearch/03-elasticsearch-statefulset.yaml -n "$NAMESPACE"

echo "Esperando a que Elasticsearch (elasticsearch-0) esté 'Ready'..."
kubectl wait --for=condition=ready pod/elasticsearch-0 -n "$NAMESPACE" --timeout=5m

echo "Verificando la creación del Secret 'elasticsearch-ca' por el initContainer..."
until kubectl get secret elasticsearch-ca -n "$NAMESPACE" &> /dev/null; do
  echo "Esperando que el secret 'elasticsearch-ca' sea creado..."
  sleep 10
done
echo "Secret 'elasticsearch-ca' encontrado."
echo "Elasticsearch listo."
echo "Esperando 10 segundos adicionales para la propagación del Secret CA..."
sleep 10
echo "----------------------------------------------------"

# --- 2. Logstash ---
echo "Paso 2: Desplegando Logstash..."
kubectl apply -f ./logstash/00-logstash-config.yaml -n "$NAMESPACE"
kubectl apply -f ./logstash/01-logstash-deployment.yaml -n "$NAMESPACE"
kubectl apply -f ./logstash/02-logstash-service.yaml -n "$NAMESPACE"

echo "Esperando a que el Deployment de Logstash esté 'Available'..."
kubectl wait --for=condition=available deployment/logstash -n "$NAMESPACE" --timeout=4m
echo "Logstash listo."
echo "----------------------------------------------------"

# --- 3. Filebeat ---
echo "Paso 3: Desplegando Filebeat..."
kubectl apply -f ./filebeat/00-filebeat-config.yaml -n "$NAMESPACE"
kubectl apply -f ./filebeat/01-filebeat-rbac.yaml -n "$NAMESPACE"
kubectl apply -f ./filebeat/02-filebeat-daemonset.yaml -n "$NAMESPACE" # Se conecta a Logstash

echo "DaemonSet de Filebeat aplicado. Esperando un momento para que los pods se inicien..."
sleep 30
echo "Filebeat listo (o en proceso de despliegue en nodos)."
echo "----------------------------------------------------"

# --- 4. Kibana ---
echo "Paso 4: Desplegando Kibana (RBAC, Job y luego Deployment)..."

echo "Aplicando RBAC para el Job de Kibana..."
kubectl apply -f ./kibana/00-kibana-user-rbac.yaml -n "$NAMESPACE"

echo "Aplicando Job 'create-kibana-user'..."
kubectl delete job create-kibana-user -n "$NAMESPACE" --ignore-not-found=true
kubectl apply -f ./kibana/01-kibana-user.yaml -n "$NAMESPACE"

echo "Esperando a que el Job 'create-kibana-user' se complete..."
kubectl wait --for=condition=complete job/create-kibana-user -n "$NAMESPACE" --timeout=3m

echo "Verificando la creación del Secret 'kibana-credentials' por el Job..."
until kubectl get secret kibana-credentials -n "$NAMESPACE" &> /dev/null; do
  echo "Esperando que el secret 'kibana-credentials' sea creado..."
  sleep 10
done
echo "Secret 'kibana-credentials' encontrado."
echo "Job de Kibana completado."
echo "Esperando 10 segundos adicionales para la propagación del Secret de Kibana..."
sleep 10

echo "Aplicando Deployment y Service de Kibana..."
kubectl apply -f ./kibana/02-kibana-deployment.yaml -n "$NAMESPACE"
kubectl apply -f ./kibana/03-kibana-service.yaml -n "$NAMESPACE"

echo "Esperando a que el Deployment de Kibana esté 'Available'..."
kubectl wait --for=condition=available deployment/kibana -n "$NAMESPACE" --timeout=4m
echo "Kibana listo."
echo "----------------------------------------------------"

echo "¡Despliegue del Stack ELK completado exitosamente!"
echo ""
echo "Información de acceso (servicios internos del clúster):"
echo "  Elasticsearch: https://elasticsearch.$NAMESPACE.svc.cluster.local:9200 (Usuario: elastic / Contraseña: password)"
echo "  Logstash (Beats input): logstash.$NAMESPACE.svc.cluster.local:5044"
echo "  Kibana: http://localhost:5601 (después de ejecutar el port-forward)"
echo ""
echo "Para acceder a Kibana desde tu máquina local, ejecuta en otra terminal:"
echo "  kubectl port-forward svc/kibana 5601:5601 -n $NAMESPACE"
echo "Luego abre http://localhost:5601 en tu navegador."
echo "Usuario para Kibana (dentro de Kibana): elastic / password (superuser)"
echo "----------------------------------------------------"