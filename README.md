# AWS Microservices Deployment: ECS vs. EKS

This project demonstrates the deployment of a microservices application (frontend and backend) on Amazon Web Services (AWS) using two different container orchestration services: Amazon Elastic Container Service (ECS) and Amazon Elastic Kubernetes Service (EKS). The infrastructure is provisioned using Terraform, and application images are built with Docker and stored in Amazon Elastic Container Registry (ECR).

## What the project does

This repository provides a comparative setup for deploying a simple two-tier microservice application. It includes:

- **Backend Service**: A Node.js application (likely an API).
- **Frontend Service**: A React application served by Nginx.
- **Infrastructure as Code**: Terraform configurations for provisioning all necessary AWS resources, including VPC, ECR, ECS clusters/services, EKS clusters/node groups, and supporting resources like databases and load balancers.
- **Deployment Automation**: Scripts and configurations to build Docker images, push them to ECR, and deploy them to either ECS or EKS.

## Why the project is useful

This project is highly useful for:

- **Learning and Comparison**: Understanding the architectural differences and deployment workflows between AWS ECS and EKS.
- **Infrastructure as Code Practice**: Demonstrating best practices for provisioning cloud infrastructure using Terraform.
- **Containerization**: Showcasing Dockerizing applications and managing container images with ECR.
- **Microservices Deployment**: Providing a tangible example of deploying a microservices architecture on AWS.
- **Getting Started with AWS Orchestration**: A practical guide for developers and DevOps engineers looking to deploy containerized applications on AWS.

## How users can get started

This section outlines the steps to get the project up and running on your AWS account.

### Prerequisites

Before you begin, ensure you have the following installed and configured:

- **AWS CLI**: Configured with credentials and a default region (`ap-south-1` is used in the examples).
- **Terraform**: Version 1.0 or higher.
- **Docker**: For building and pushing container images.
- **kubectl**: For interacting with the EKS cluster (only for EKS deployment).
- **Node.js and npm/yarn**: To build frontend/backend applications locally if needed (though Docker builds handle this).

### AWS Account Setup

Ensure your AWS account has appropriate permissions to create VPCs, ECR repositories, ECS clusters/services, EKS clusters, IAM roles, and other related resources.

### Deployment Steps (Choose one: ECS or EKS)

#### Option 1: Deploying with Amazon ECS

1.  **Navigate to the ECS directory**:

    ```bash
    cd Week\ 3/ECS\ vs\ EKS/ECS
    ```

2.  **Initialize Terraform**:

    ```bash
    terraform init
    ```

3.  **Provision ECR repositories**:
    This step creates the necessary ECR repositories for your backend and frontend Docker images.

    ```bash
    terraform apply -target=aws_ecr_repository.backend -target=aws_ecr_repository.frontend -auto-approve
    ```

4.  **Set up environment variables**:
    Replace `your-aws-profile` with your AWS CLI profile name.

    ```bash
    export REGION="ap-south-1"
    export AWS_PROFILE="john" # Replace with your AWS CLI profile
    export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile $AWS_PROFILE)
    export REPO_BASE="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
    ```

5.  **Authenticate Docker to ECR**:

    ```bash
    aws ecr get-login-password --region $REGION --profile $AWS_PROFILE | docker login --username AWS --password-stdin $REPO_BASE
    ```

6.  **Build, Tag, and Push Docker Images**:
    These commands build the Docker images for your backend and frontend services, tag them, and push them to the ECR repositories created earlier.

    ```bash
    docker build -t backend ./backend
    docker tag backend:latest $REPO_BASE/backend:latest
    docker push $REPO_BASE/backend:latest

    docker build -t frontend ./frontend
    docker tag frontend:latest $REPO_BASE/frontend:latest
    docker push $REPO_BASE/frontend:latest
    ```

7.  **Provision remaining ECS resources**:
    This will deploy the VPC, ECS cluster, services, task definitions, load balancers, and RDS database.

    ```bash
    terraform apply -auto-approve
    ```

8.  **Access the Application**:
    Once deployed, retrieve the Load Balancer DNS name from the Terraform output:

    ```bash
    terraform output frontend_load_balancer_dns
    ```

    Open the DNS name in your web browser.

9.  **Force new deployment (if images updated)**:
    If you make changes to your application code and push new images to ECR, you can force ECS to pull the new images:

    ```bash
    aws ecs update-service --cluster microservices-cluster --service backend-service --force-new-deployment --region $REGION --profile $AWS_PROFILE
    aws ecs update-service --cluster microservices-cluster --service frontend-service --force-new-deployment --region $REGION --profile $AWS_PROFILE
    ```

10. **Clean up ECS resources**:
    To destroy all provisioned AWS resources:
    ```bash
    terraform destroy -auto-approve
    ```
    And clean up local Terraform state:
    ```bash
    rm terraform.tfstate terraform.tfstate.backup
    rm -rf .terraform .terraform.lock.hcl
    ```

#### Option 2: Deploying with Amazon EKS

1.  **Navigate to the EKS directory**:

    ```bash
    cd Week\ 3/ECS\ vs\ EKS/EKS
    ```

2.  **Initialize Terraform**:

    ```bash
    terraform init
    ```

3.  **Provision VPC and EKS Cluster**:
    This step sets up the networking and the EKS control plane.

    ```bash
    terraform apply -target=module.vpc -target=module.eks -auto-approve
    ```

4.  **Provision remaining EKS resources**:
    This will deploy node groups, ECR repositories, and other supporting resources.

    ```bash
    terraform apply -auto-approve
    ```

5.  **Set up environment variables**:
    Replace `your-aws-profile` with your AWS CLI profile name.

    ```bash
    export REGION="ap-south-1"
    export CLUSTER_NAME="eks-cluster"
    export AWS_PROFILE="john" # Replace with your AWS CLI profile
    export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile $AWS_PROFILE)
    export REPO_BASE="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
    ```

6.  **Update Kubeconfig**:
    This command configures `kubectl` to connect to your newly created EKS cluster.

    ```bash
    aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME --profile $AWS_PROFILE
    ```

7.  **Authenticate Docker to ECR**:

    ```bash
    aws ecr get-login-password --region $REGION --profile $AWS_PROFILE | docker login --username AWS --password-stdin $REPO_BASE
    ```

8.  **Build, Tag, and Push Docker Images**:
    These commands build the Docker images for your backend and frontend services, tag them, and push them to the ECR repositories created earlier.

    ```bash
    docker build -t backend ./backend
    docker tag backend:latest $REPO_BASE/backend:latest
    docker push $REPO_BASE/backend:latest

    docker build -t frontend ./frontend
    docker tag frontend:latest $REPO_BASE/frontend:latest
    docker push $REPO_BASE/frontend:latest
    ```

9.  **Deploy Logic Tier (Backend) and Ingress Tier (Frontend) to EKS**:
    These commands apply the Kubernetes manifests to deploy your services.

    ```bash
    kubectl apply -f backend.yaml
    kubectl apply -f frontend.yaml
    ```

10. **Access the Application**:
    Retrieve the Load Balancer DNS name (might take a few minutes for the AWS Load Balancer Controller to provision it):

    ```bash
    kubectl get services -n default frontend-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
    ```

    Open the DNS name in your web browser.

11. **Clean up EKS resources**:
    To remove the Kubernetes deployments:
    ```bash
    kubectl delete -f frontend.yaml
    kubectl delete -f backend.yaml
    ```
    To destroy all provisioned AWS resources (VPC, EKS cluster, etc.):
    ```bash
    terraform destroy -auto-approve
    ```
    And clean up local Terraform state:
    ```bash
    rm terraform.tfstate terraform.tfstate.backup
    rm -rf .terraform .terraform.lock.hcl
    ```

## Where users can get help

For issues, questions, or further assistance:

- **GitHub Issues**: If you encounter a bug or have a feature request, please open an issue on this repository's [Issues page](https://github.com/YOUR_GITHUB_USER/YOUR_REPO_NAME/issues).
- **AWS Documentation**: Refer to the official [AWS ECS Documentation](https://aws.amazon.com/ecs/documentation/) and [AWS EKS Documentation](https://aws.amazon.com/eks/documentation/) for detailed information on the services.
- **Terraform Documentation**: For Terraform-related queries, consult the [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs).

## Who maintains and contributes

**Maintainer**:

- [Your Name/Organization Name] - [Link to GitHub Profile/Organization Page]

**Contributing**:
Contributions are welcome! If you'd like to contribute, please refer to the [CONTRIBUTING.md](CONTRIBUTING.md) guide (if available) for details on our code of conduct, and the process for submitting pull requests.

---

**Note**: Replace `YOUR_GITHUB_USER/YOUR_REPO_NAME` and `Your Name/Organization Name` and `Link to GitHub Profile/Organization Page` with your actual GitHub details. Create a `CONTRIBUTING.md` file if you wish to provide more detailed guidelines for contributions.
