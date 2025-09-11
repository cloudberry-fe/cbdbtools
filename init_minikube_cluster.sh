#!/bin/bash

minikube start

## Check the K8S status and enable addons
kubectl get po -A
minikube addons enable registry 
minikube addons enable metrics-server
minikube addons enable dashboard

echo "apiVersion: v1
kind: Service
metadata:
  name: kubernetes-dashboard-lb
  namespace: kubernetes-dashboard
spec:
  selector:
    k8s-app: kubernetes-dashboard
  ports:
    - protocol: TCP
      port: 9090
      targetPort: 9090
  type: LoadBalancer" > /home/minikube/kubernetes-dashboard-lb-service.yaml

kubectl apply -f /home/minikube/kubernetes-dashboard-lb-service.yaml

echo "apiVersion: v1
kind: Service
metadata:
  name: registry-lb
  namespace: kube-system
spec:
  selector:
    actual-registry: "true"
    kubernetes.io/minikube-addons: registry
  ports:
  - protocol: TCP
    port: 5000
    targetPort: 5000
  type: LoadBalancer" > /home/minikube/registry-lb-service.yaml
  
kubectl apply -f /home/minikube/registry-lb-service.yaml

echo "apiVersion: v1
kind: Service
metadata:
  name: minio-console-lb
  namespace: minio
spec:
  selector:
    app: minio
  ports:
    - name: console
      protocol: TCP
      port: 32001
      targetPort: 32001
  type: LoadBalancer" > /home/minikube/minio-console-lb-service.yaml

echo "apiVersion: v1
kind: Service
metadata:
  name: dbaas-integration-lb
  namespace: dbaas
spec:
  selector:
    app.kubernetes.io/name: hashdata-dbaas-integration
  ports:
    - protocol: TCP
      port: 8030
      targetPort: 8030
  type: LoadBalancer" > /home/minikube/dbaas-integration-lb-service.yaml


echo "apiVersion: v1
kind: Service
metadata:
  name: fe-team-coord-lb                #Subject to change in your env
  namespace: hashdata-fe-team-07e5674f  #Subject to change in your env
spec:
  selector:
    enterprise.dbaas/component: coordinator
    enterprise.dbaas/instance: fe-team-coord #Subject to change in your env
  ports:
  - name: postgresql
    protocol: TCP
    port: 5432 # Service port to exposed on host server
    targetPort: 5432 # Ports used inside the pods
  type: LoadBalancer" > /home/minikube/fe-coord-lb-service.yaml
