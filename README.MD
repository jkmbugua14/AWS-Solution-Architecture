# AWS Solutions Architect Professional Training Repository

This repository serves as the central documentation and codebase for all architectural implementations, labs, and research conducted during the **AWS Solutions Architect Professional** certification path. The project structure follows a progressive weekly format to align with advanced enterprise cloud architectural patterns.

---

## 🏗 Architectural Governance

All projects in this repository are designed and audited against the **AWS Well-Architected Framework** pillars:

1. **Operational Excellence:** Automated deployments via Infrastructure as Code (IaC) and comprehensive observability.
2. **Security:** Implementation of Least Privilege via IAM, encryption at rest/transit, and VPC security best practices.
3. **Reliability:** Multi-AZ deployments, self-healing systems, and disaster recovery strategies.
4. **Performance Efficiency:** Selection of compute (Lambda, Fargate, EC2) and storage (S3, EBS, EFS) based on workload demand.
5. **Cost Optimization:** Leveraging AWS Cost Explorer, Spot Instances, and rightsizing resources.
6. **Sustainability:** Optimizing resource utilization to reduce the environmental footprint of cloud workloads.

---

## 📂 Repository Structure

```text
.
├── README.md               # Root documentation
└── Week 3/                 # Advanced Compute and Containerization
    └── ECS vs EKS/         # Comparative analysis of AWS container orchestration
        ├── architecture/   # High-Level Design (HLD) diagrams
        ├── terraform/      # IaC for cluster provisioning
        └── README.md       # Project-specific documentation

```

---

## 🗓 Project Log & Roadmap

| Week       | Focus Area           | Core Services            | Key Learning Objective                                                            |
| ---------- | -------------------- | ------------------------ | --------------------------------------------------------------------------------- |
| **Week 3** | **Containerization** | ECS, EKS, Fargate, ECR   | Determining orchestration strategy based on operational overhead vs. flexibility. |
| **Week 4** | **Serverless Arch**  | Lambda, API Gateway, SQS | Building event-driven, decoupled enterprise applications.                         |

---

## 🛠 Technical Standards

To maintain professional software/solutions architect standards, every project must adhere to:

- **Zero Hardcoding:** Use AWS Secrets Manager or Parameter Store for all configurations.
- **Documentation:** Every sub-folder must contain a `README.md` explaining the _why_ (business case) behind the _how_ (technical implementation).
- **Scalability:** Solutions must be designed to handle enterprise-level traffic without manual intervention.

---
