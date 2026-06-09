# Phase 2 Runbook — Pilot Light DR + Route 53 Failover

**Goal:** Extend the af-south-1 stack with a pilot-light DR environment in eu-west-1, an Aurora Global secondary, Route 53 failover, and a validated simulated regional failure.

Prerequisites:
- The Phase 1 stack still running in af-south-1 (replaced in Step 1).
- The S3 app bucket from Phase 1 (`pesalink-app-<your-suffix>`) — a sibling bucket is created in eu-west-1 in Step 2.
- A domain in Route 53 (hosted zone already in place, or created in Step 4).

---

## Step 1 — Replace the Phase 1 stack with the Phase 2 primary stack (in place)

The Phase 2 template wraps the existing regional Aurora cluster in a Global cluster. Updating in place would require replacing the cluster, which is not safe. The cleanest path is to deploy a **new** stack in af-south-1, confirm it serves traffic, then delete the Phase 1 stack.

Since this is a demonstration environment with no real data, this is the fastest path:

```bash
export AWS_REGION=af-south-1

# Re-upload the app bundle if needed (idempotent)
aws s3 cp pesalink-app.tar.gz s3://pesalink-app-<your-suffix>/app/pesalink-app.tar.gz

# Deploy the primary stack
aws cloudformation deploy \
  --template-file phase-2.yaml \
  --stack-name pesalink-primary \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
      DeploymentRole=primary \
      AppBucketName=pesalink-app-<your-suffix>
```
~15 minutes to `CREATE_COMPLETE` (Aurora is the slow part).

Grab the two values the DR stack and Route 53 stack will need:
```bash
aws cloudformation describe-stacks --stack-name pesalink-primary \
  --query "Stacks[0].Outputs" --output table
```
Note the `GlobalClusterId`, `AlbDnsName`, and `AlbHostedZoneId`.

Confirm it serves traffic:
```bash
PRI_ALB=$(aws cloudformation describe-stacks --stack-name pesalink-primary \
  --query "Stacks[0].Outputs[?OutputKey=='AlbDnsName'].OutputValue" --output text)
curl http://$PRI_ALB/health      # -> OK
```

Once confirmed, tear down the Phase 1 stack to avoid duplicate cost:
```bash
aws cloudformation delete-stack --stack-name pesalink-multi-az-foundation
```

---

## Step 2 — Prepare the DR region (eu-west-1)

The DR region needs its own S3 bucket containing the same app bundle (S3 reads are regional, and the instance role only grants access to the bucket in its own stack):

```bash
export AWS_REGION=eu-west-1

aws s3api create-bucket \
  --bucket pesalink-app-dr-<your-suffix> \
  --region eu-west-1 \
  --create-bucket-configuration LocationConstraint=eu-west-1

aws s3 cp pesalink-app.tar.gz s3://pesalink-app-dr-<your-suffix>/app/pesalink-app.tar.gz
aws s3 ls s3://pesalink-app-dr-<your-suffix>/app/
```

---

## Step 3 — Deploy the DR stack

Same template, different parameters. `DeploymentRole=dr` sets ASG desired to 0, removes the master credentials block on Aurora (it joins the global as a read-only secondary), and tags everything with `-dr`.

```bash
# still in eu-west-1
aws cloudformation deploy \
  --template-file phase-2.yaml \
  --stack-name pesalink-dr \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
      DeploymentRole=dr \
      AppBucketName=pesalink-app-dr-<your-suffix> \
      GlobalClusterIdentifier=pesalink-global
```
The DR Aurora cluster takes another ~10 minutes to fully seed from the primary.

Grab the DR ALB details:
```bash
aws cloudformation describe-stacks --stack-name pesalink-dr \
  --query "Stacks[0].Outputs" --output table
```

**Confirm the DR ALB is reachable and returns 503** (no targets — expected, ASG is at desired=0):
```bash
DR_ALB=$(aws cloudformation describe-stacks --stack-name pesalink-dr \
  --query "Stacks[0].Outputs[?OutputKey=='AlbDnsName'].OutputValue" --output text)
curl -i http://$DR_ALB/health    # -> HTTP/1.1 503 (correct — pilot light is cold)
```

**Verify Global DB replication lag** (CloudWatch metric `AuroraGlobalDBReplicationLag` should be <1s):
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name AuroraGlobalDBReplicationLag \
  --dimensions Name=DBClusterIdentifier,Value=<dr-cluster-id> \
  --start-time $(date -u -d '15 minutes ago' +%FT%TZ) \
  --end-time $(date -u +%FT%TZ) \
  --period 60 --statistics Average
```
**Record the observed lag — it gets quoted in the article.**

---

## Step 4 — Route 53 hosted zone (skip if one already exists)

If the domain's hosted zone is already in Route 53, retrieve its ID:
```bash
aws route53 list-hosted-zones --query "HostedZones[?Name=='yourdomain.com.'].Id" --output text
# returns something like /hostedzone/Z2ABCXYZ...
```

To create a new zone and delegate from a registrar:
```bash
aws route53 create-hosted-zone --name yourdomain.com --caller-reference $(date +%s)
# update NS records at the registrar to the four NS values returned
```
**Wait for nameserver propagation before testing failover** (can take minutes to hours depending on the registrar).

---

## Step 5 — Deploy the Route 53 failover records

Route 53 is global but its CloudFormation resources are managed via us-east-1:

```bash
export AWS_REGION=us-east-1

# Pull the values needed for the stack
PRI_ALB=$(aws cloudformation describe-stacks --region af-south-1 --stack-name pesalink-primary \
  --query "Stacks[0].Outputs[?OutputKey=='AlbDnsName'].OutputValue" --output text)
PRI_ZONE=$(aws cloudformation describe-stacks --region af-south-1 --stack-name pesalink-primary \
  --query "Stacks[0].Outputs[?OutputKey=='AlbHostedZoneId'].OutputValue" --output text)
DR_ALB=$(aws cloudformation describe-stacks --region eu-west-1 --stack-name pesalink-dr \
  --query "Stacks[0].Outputs[?OutputKey=='AlbDnsName'].OutputValue" --output text)
DR_ZONE=$(aws cloudformation describe-stacks --region eu-west-1 --stack-name pesalink-dr \
  --query "Stacks[0].Outputs[?OutputKey=='AlbHostedZoneId'].OutputValue" --output text)

aws cloudformation deploy \
  --template-file phase-2-route53.yaml \
  --stack-name pesalink-dns-failover \
  --parameter-overrides \
      HostedZoneId=<zone-id-without-the-/hostedzone/-prefix> \
      RecordName=pesalink.yourdomain.com \
      PrimaryAlbDnsName=$PRI_ALB \
      PrimaryAlbZoneId=$PRI_ZONE \
      SecondaryAlbDnsName=$DR_ALB \
      SecondaryAlbZoneId=$DR_ZONE
```

Confirm DNS resolves to the primary ALB:
```bash
dig +short pesalink.yourdomain.com
# should return the af-south-1 ALB's IPs
```

**📸 SCREENSHOT 1 (deliverable):** `dig pesalink.yourdomain.com` output showing resolution to af-south-1 IPs (normal operation).

---

## Step 6 — Simulate the regional failure

The method: change the primary health check's path to one that returns non-200, without touching any infrastructure. Route 53 will fail the health check within ~20s, then flip DNS to the secondary.

In the Route 53 console → Health checks → `pesalink-primary-hc` → Edit → change ResourcePath from `/health` to `/intentional-fail` → save.

```bash
date -u                                          # T0 - record this
```

Watch the health check fail:
```bash
PRI_HC=$(aws cloudformation describe-stacks --region us-east-1 --stack-name pesalink-dns-failover \
  --query "Stacks[0].Outputs[?OutputKey=='PrimaryHcId'].OutputValue" --output text)

watch -n 5 "aws route53 get-health-check-status --health-check-id $PRI_HC \
  --query 'HealthCheckObservations[].StatusReport.Status' --output text"
```
The output flips from `Success: HTTP Status Code 200` to `Failure: HTTP Status Code 404`. Once a majority of checkers report failure, the record is considered unhealthy.

Watch DNS flip:
```bash
watch -n 10 "dig +short pesalink.yourdomain.com"
```
**Record T1 when the result changes to the eu-west-1 ALB IPs.**

**Observed regional failover time = T1 − T0 = ______** (typically 60–120s, limited by health-check evaluation + DNS TTL of 60s).

**📸 SCREENSHOT 2 (deliverable):** `dig pesalink.yourdomain.com` output showing resolution to eu-west-1 IPs (after simulated failure).

---

## Step 7 — Bring the DR region live (complete the failover)

DNS is now pointing at eu-west-1, but the ASG is still at 0 instances and the database is still a read-only secondary. Two commands fix that:

```bash
# Scale up the DR ASG
aws autoscaling update-auto-scaling-group --region eu-west-1 \
  --auto-scaling-group-name pesalink-asg-dr \
  --min-size 2 --desired-capacity 2

# Promote the DR cluster — detaches it from the global, makes it read/write
aws rds remove-from-global-cluster --region eu-west-1 \
  --global-cluster-identifier pesalink-global \
  --db-cluster-identifier <dr-cluster-arn>
```
Once the DR ASG instances pass health checks (3–4 minutes), `curl pesalink.yourdomain.com/health` returns `OK` from eu-west-1.

---

## Step 8 — Fail back

Restore the health check path to `/health` in the Route 53 console. Within ~20s the primary health check returns to healthy and DNS flips back to af-south-1.

**📸 OPTIONAL SCREENSHOT:** `dig` output confirming the flip back to af-south-1.

---

## Notes for the article narrative
- The observed Global DB replication lag (Step 3).
- The observed regional failover time T1−T0 (Step 6).
- The contrast: Phase 1 single-instance RTO was **2m 51s** with no user impact (the other instance kept serving). Phase 2 regional failover RTO is bound by DNS — TTL + health-check evaluation — and replaces everything at once.
- One real wrinkle: note what happened when the DR ASG scaled up — did instances start cleanly, or did the DR-region S3 bucket trip-up surface?

---

## Teardown (only when past Phase 3)
```bash
aws cloudformation delete-stack --region us-east-1   --stack-name pesalink-dns-failover
aws cloudformation delete-stack --region eu-west-1   --stack-name pesalink-dr
aws cloudformation delete-stack --region af-south-1  --stack-name pesalink-primary
# Global cluster has DeletionPolicy: Retain — remove it manually for a clean account.
```
