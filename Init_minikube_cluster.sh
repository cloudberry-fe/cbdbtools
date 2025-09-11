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
