#!/bin/bash

# Exit on any error
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="deployment_log.csv"

# Create CSV header
echo "Timestamp,Operation,Status,Details" > $LOG_FILE

# Function to log to CSV
log_operation() {
    local operation=$1
    local status=$2
    local details=$3
    echo "$(date '+%Y-%m-%d %H:%M:%S'),$operation,$status,\"$details\"" >> $LOG_FILE
}

# Function to print status messages
print_status() {
    echo -e "${GREEN}[+] $1${NC}"
    log_operation "${1/:*/}" "INFO" "$1"
}

# Function to print error messages
print_error() {
    echo -e "${RED}[!] $1${NC}"
    log_operation "ERROR" "FAILED" "$1"
}

# Build FastAPI Docker image
print_status "Building FastAPI Docker image"
docker build -t fastapi-user-api:latest . || { 
    print_error "Docker build failed"
    exit 1
}
log_operation "Build" "SUCCESS" "FastAPI image built successfully"

# Determine if we are using minikube
if command -v minikube &> /dev/null && minikube status >/dev/null 2>&1; then
    print_status "Detected minikube environment"
    eval $(minikube docker-env)
    print_status "Building image directly in minikube's Docker"
    docker build -t fastapi-user-api:latest . || {
        print_error "Failed to build image in minikube"
        exit 1
    }
    log_operation "Build" "SUCCESS" "Image built in minikube's Docker"
else
    # Try to use a local registry if available
    if docker ps | grep -q "registry:2"; then
        print_status "Local registry detected, tagging and pushing image"
        docker tag fastapi-user-api:latest localhost:5000/fastapi-user-api:latest
        docker push localhost:5000/fastapi-user-api:latest || {
            print_error "Failed to push to local registry"
            log_operation "Push" "WARNING" "Could not push to local registry"
        }
        # Update the deployment file to use the registry image
        print_status "Updating deployment to use registry image"
        sed -i 's|image: fastapi-user-api:latest|image: localhost:5000/fastapi-user-api:latest|g' my-deployment-eval.yml
    else
        print_status "No local registry detected, will rely on local image"
        # Make sure the deployment uses the local image
        sed -i 's|image: localhost:5000/fastapi-user-api:latest|image: fastapi-user-api:latest|g' my-deployment-eval.yml
    fi
fi

# Clean up any existing resources
print_status "Cleaning up existing resources"
kubectl delete deployment api-mysql-deployment --ignore-not-found=true
kubectl delete service user-api-service --ignore-not-found=true
kubectl delete ingress user-api-ingress --ignore-not-found=true
kubectl delete configmap mysql-init-scripts --ignore-not-found=true
log_operation "Cleanup" "SUCCESS" "Existing resources removed"

# Create ConfigMap for MySQL initialization
print_status "Creating MySQL initialization ConfigMap"
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: mysql-init-scripts
data:
  create_schema.sql: |
    CREATE DATABASE IF NOT EXISTS Main;
    USE Main;
    CREATE TABLE IF NOT EXISTS Users (
      id INT PRIMARY KEY AUTO_INCREMENT,
      username VARCHAR(255) NOT NULL,
      email VARCHAR(255) NOT NULL
    );
  insert_data.sql: |
    USE Main;
    INSERT INTO Users (username, email) VALUES 
      ('daniel', 'daniel@datascientest.com'),
      ('alice', 'alice@example.com'),
      ('bob', 'bob@example.com');
EOF
log_operation "ConfigMap" "SUCCESS" "MySQL initialization ConfigMap created"

# Apply Kubernetes resources
print_status "Creating Kubernetes resources"

print_status "Creating secret"
kubectl apply -f my-secret-eval.yml || {
    print_error "Failed to create secret"
    exit 1
}
log_operation "Secret" "SUCCESS" "Secret created successfully"

print_status "Creating deployment"
kubectl apply -f my-deployment-eval.yml || {
    print_error "Failed to create deployment"
    exit 1
}
log_operation "Deployment" "SUCCESS" "Deployment created successfully"

print_status "Creating service"
kubectl apply -f my-service-eval.yml || {
    print_error "Failed to create service"
    exit 1
}
log_operation "Service" "SUCCESS" "Service created successfully"

print_status "Creating ingress"
kubectl apply -f my-ingress-eval.yml || {
    print_error "Failed to create ingress"
    exit 1
}
log_operation "Ingress" "SUCCESS" "Ingress created successfully"

# Monitor deployment progress
print_status "Monitoring deployment progress"
end=$((SECONDS + 300))  # 5 minutes timeout

while [ $SECONDS -lt $end ]; do
    ready=$(kubectl get deployment api-mysql-deployment -o jsonpath="{.status.readyReplicas}" 2>/dev/null || echo "0")
    total=$(kubectl get deployment api-mysql-deployment -o jsonpath="{.spec.replicas}" 2>/dev/null || echo "0")
    
    echo -e "\nPod Status:"
    kubectl get pods -l app=user-api
    
    if [ "$ready" == "$total" ] && [ "$ready" != "0" ]; then
        print_status "All pods are ready! ($ready/$total)"
        log_operation "Deployment" "SUCCESS" "All pods are ready"
        break
    fi
    
    # Get all pods and show details for the first one
    PODS=$(kubectl get pod -l app=user-api -o name)
    if [ ! -z "$PODS" ]; then
        POD=$(echo "$PODS" | head -1)
        echo -e "\nPod Details for $POD:"
        # Fixed this line - using $POD directly instead of adding "pod" prefix
        kubectl describe $POD | grep -A 5 "Events:"
        
        echo -e "\nMySQL Logs:"
        kubectl logs $POD -c mysql --tail=5 2>/dev/null || echo "No logs available yet"
        
        echo -e "\nFastAPI Logs:"
        kubectl logs $POD -c fastapi --tail=5 2>/dev/null || echo "No logs available yet"
    fi
    
    echo -e "\nWaiting 10 seconds before next check..."
    sleep 10
done

if [ $SECONDS -ge $end ]; then
    print_error "Deployment timed out after 5 minutes"
    echo -e "\nFinal pod status:"
    kubectl get pods -l app=user-api
    echo -e "\nEvents:"
    kubectl get events --sort-by=.metadata.creationTimestamp | tail -n 10
    log_operation "Deployment" "FAILED" "Timeout waiting for pods"
    exit 1
fi

# Get service information
print_status "Getting service endpoint"
echo -e "\nService is ready! Test with:"
echo "kubectl port-forward svc/user-api-service 8000:80"
echo "Then in another terminal:"
echo "curl localhost:8000/status"
echo "curl localhost:8000/users"

print_status "Deployment process completed"
echo "Check $LOG_FILE for detailed deployment logs"