# Database Migration (Oracle to DynamoDB & Aurora PostgreSQL)

This repository contains declarative SQL schemas and configuration files to execute a modernized database migration. It routes data from a source Amazon RDS for Oracle instance to target Amazon Aurora PostgreSQL and Amazon DynamoDB databases utilizing AWS Database Migration Service (AWS DMS).

## Architecture Overview

![Architecture Diagram](<AWS DMS/lab1-arch.png>)

## Repository Contents

- `cfn.yaml`: AWS CloudFormation template provisioning the foundational infrastructure (VPCs, Subnets, RDS instances, DynamoDB tables).
- `Oracle-Source.sql`: DDL and DML scripts to initialize the source Oracle database, establish the `TAXI` schema, and inject seed data.
- `Aurora_Target.sql`: DDL script to initialize the target Aurora PostgreSQL database, create the `trips` table, and configure sequence generation.
- `ora2ddb.json`: AWS DMS table mapping rules transforming relational Oracle records to the DynamoDB NoSQL structure.
- `ora2aurora.json`: AWS DMS table mapping rules transforming the Oracle schema to align with standard PostgreSQL conventions.

---

## Step 1: Infrastructure Provisioning

Provision the core networking, security, and database resources.

1. Navigate to the **AWS CloudFormation** console.
2. Select **Create stack** and upload the `cfn.yaml` template.
3. Provide the required parameters for the database configurations.
4. Acknowledge IAM resource creation and click **Submit**.
5. Wait for the stack status to reach `CREATE_COMPLETE`.
6. Select the **Outputs** tab of the deployed stack. Extract and record all generated database endpoints, usernames, and passwords. These values are required for all subsequent client connections and DMS endpoint configurations.

## Step 2: Database Initialization

Establish direct client connections (e.g., via DBeaver, pgAdmin, or SQL Developer) to the provisioned database instances to execute schema initialization.

### 2.1 Source Oracle RDS Initialization

1. Connect to the Oracle RDS instance using the endpoint and master credentials retrieved from the CloudFormation **Outputs**.
2. Execute the `Oracle-Source.sql` script.

- Provisions the `TAXI` user and schema.
- Allocates tablespaces and constructs the `TRIPS` table.
- Inserts initial seed transaction records.

### 2.2 Target Aurora PostgreSQL Initialization

1. Connect to the Aurora PostgreSQL instance using the endpoint and master credentials retrieved from the CloudFormation **Outputs**.
2. Execute the `Aurora_Target.sql` script.

- Creates the `trips` table within the default `public` schema.
- Defines numeric and timestamp data types.
- Configures the `trips_id_seq` sequence.

## Step 3: AWS DMS Endpoints Configuration

Define the connection boundaries for the DMS replication instance.

1. Navigate to the **AWS DMS** console and select **Endpoints**.
2. **Source Endpoint**: Select **Create endpoint**, choose Oracle, and input the RDS endpoint address, port (1521), and master credentials sourced from the CloudFormation **Outputs**.
3. **Target Endpoints**:

- Create a PostgreSQL target endpoint pointing to the Aurora cluster using the respective credentials from the **Outputs**.
- Create a DynamoDB target endpoint pointing to the provisioned NoSQL table.

4. Execute connection tests for all endpoints using the provisioned replication instance to validate network reachability and authentication.

## Step 4: DMS Migration Tasks Configuration

Establish migration tasks to process schema transformations and execute data replication.

### Task 1: Oracle to DynamoDB

1. In the DMS console, navigate to **Database migration tasks** -> **Create task**.
2. Select the Oracle source endpoint and the DynamoDB target endpoint.
3. Choose **Migrate existing data**.
4. Under **Table mappings**, switch to the JSON editor and input the contents of `ora2ddb.json`.

- _Transformation logic: Maps `TAXI.TRIPS` records to the NoSQL target, defining `riderid` as the partition key and `tripinfo` as the sort key._

### Task 2: Oracle to Aurora PostgreSQL

1. Create a secondary migration task.
2. Select the Oracle source endpoint and the Aurora PostgreSQL target endpoint.
3. Choose **Migrate existing data**.
4. Under **Table mappings**, switch to the JSON editor and input the contents of `ora2aurora.json`.

- _Transformation logic: Renames the legacy `TAXI` schema to `public` and converts all schema and table names to lowercase._

## Step 5: Validation

Monitor the DMS tasks. Upon reaching the **Load complete** status, verify data integrity across the target environments.

### Relational Target Validation (Aurora)

1. Connect to the Aurora PostgreSQL database.
2. Execute `SELECT COUNT(*) FROM trips;` and confirm the return value matches the source Oracle record count.

### NoSQL Target Validation (DynamoDB)

1. Navigate to the **Amazon DynamoDB** console.
2. Select the target table (`aws-db-workshop-trips`) and choose **Explore table items**.
3. Execute a scan to confirm the item count and validate the composite primary key structure (`riderid` and `tripinfo`).
