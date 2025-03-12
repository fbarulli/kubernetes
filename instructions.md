# Deployment Instructions

## Prerequisites
- Docker installed
- kubectl configured with your Kubernetes cluster

## File Structure
```
.
├── files/
│   ├── main.py
│   └── requirements.txt
├── Dockerfile
├── deploy.sh
├── my-secret-eval.yml
├── my-deployment-eval.yml
├── my-service-eval.yml
└── my-ingress-eval.yml
```

## Deployment

1. Make the deployment script executable:
```bash
chmod +x deploy.sh
```

2. Run the deployment:
```bash
./deploy.sh
```

The script will:
- Build and publish Docker images
- Deploy all Kubernetes resources
- Monitor deployment progress
- Generate detailed logs

## Monitoring

### Real-time Progress
The script provides real-time status updates in the terminal.

### Deployment Logs
A CSV log file (`deployment_log.csv`) is generated with detailed information:
- Timestamp of each operation
- Operation name
- Status (INFO/SUCCESS/FAILED)
- Detailed messages

The log file helps track:
- Build and push operations
- Resource creation status
- Container states
- Pod logs
- Service endpoints

### Manual Status Checks
You can also check status manually:
```bash
# Check pod status
kubectl get pods -l app=user-api

# Check service
kubectl get svc user-api-service

# Check ingress
kubectl get ingress user-api-ingress

# View deployment logs
cat deployment_log.csv
```

## Troubleshooting

If deployment fails:
1. Check deployment_log.csv for error details
2. Look for FAILED status entries to identify issues
3. Review container logs in the CSV for specific error messages
4. Ensure all prerequisites are met
5. Verify Kubernetes cluster is running