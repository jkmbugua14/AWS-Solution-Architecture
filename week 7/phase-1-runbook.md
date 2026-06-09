# Phase 1 Runbook — Multi-AZ Foundation in af-south-1

**Goal:** Stand up the multi-AZ stack, confirm both instances healthy, terminate one, and record the observed single-instance recovery time (RTO).

Run everything with the CLI region set to af-south-1:

```bash
export AWS_REGION=af-south-1
```

---

## Step 0 — Package and upload the app to S3

The launch template pulls `server.js` from S3 at boot.

```bash
# from the folder containing server.js
tar -czf pesalink-app.tar.gz server.js

# create a private bucket IN af-south-1 (name must be globally unique)
aws s3 mb s3://pesalink-app-<your-suffix> --region af-south-1

# upload to the key the template expects
aws s3 cp pesalink-app.tar.gz s3://pesalink-app-<your-suffix>/app/pesalink-app.tar.gz
```

> Keep the bucket private. The instance role grants `s3:GetObject` on it — no public access needed.

---

## Step 1 — Deploy the stack

```bash
aws cloudformation deploy \
  --template-file phase-1.yaml \
  --stack-name pesalink-multi-az-foundation \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides AppBucketName=pesalink-app-<your-suffix> \
  --region af-south-1
```

Aurora takes the longest — expect roughly 10–15 minutes for `CREATE_COMPLETE`.

Grab the outputs when it finishes:

```bash
aws cloudformation describe-stacks --stack-name pesalink-multi-az-foundation \
  --query "Stacks[0].Outputs" --output table
```

---

## Step 2 — Confirm the app is up

```bash
ALB=$(aws cloudformation describe-stacks --stack-name pesalink-multi-az-foundation \
  --query "Stacks[0].Outputs[?OutputKey=='AlbDnsName'].OutputValue" --output text)

curl http://$ALB/health     # -> OK
curl http://$ALB/           # -> JSON; note "servedBy" changes as the ALB round-robins
```

If `/health` returns 503 for a minute or two right after deploy, that's the health-check grace period — wait it out.

---

## Step 3 — DELIVERABLE 1: both instances healthy

EC2 console → Target Groups → `pesalink-tg` → **Targets** tab.
Wait until **both** targets show **healthy**, each in a different AZ (af-south-1a and 1b).

**Screenshot this.** This is the first deliverable.

---

## Step 4 — Self-healing test

Note the exact time, then terminate one instance:

```bash
date -u                     # record T0
IID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names pesalink-asg \
  --query "AutoScalingGroups[0].Instances[0].InstanceId" --output text)
aws ec2 terminate-instances --instance-ids $IID
```

Watch the target group refresh. The sequence is:

1. The terminated target goes **draining → unused** (ALB pulls it from rotation).
2. The ASG launches a replacement (desired stays at 2).
3. The new instance boots, passes 2× `/health` checks, becomes **healthy**.

Poll for progress:

```bash
TG=$(aws cloudformation describe-stacks --stack-name pesalink-multi-az-foundation \
  --query "Stacks[0].Outputs[?OutputKey=='TargetGroupArn'].OutputValue" --output text)
watch -n 5 'aws elbv2 describe-target-health --target-group-arn '"$TG"' \
  --query "TargetHealthDescriptions[].TargetHealth.State" --output text'
```

When two `healthy` entries appear again, record the time (T1).

---

## Step 5 — DELIVERABLE 2 + recorded RTO

~5 minutes after termination, screenshot the target group showing the **replacement healthy**.

**Record: observed single-instance RTO = T1 − T0 = \_\_\_ (typically 2–4 min with S3-pull user data).**

Keep this number — it gets quoted directly in the article and contrasted against the Phase 2 regional failover time.

---

## Teardown (when done with the full exercise, not before Phase 2)

Phase 2 reuses this stack as the primary region, so **don't delete it yet**. When the time comes:

```bash
aws cloudformation delete-stack --stack-name pesalink-multi-az-foundation --region af-south-1
```

The Aurora cluster has `DeletionPolicy: Snapshot`, so it leaves a final snapshot behind — delete that manually if it's not needed.

---

### Notes for the article narrative

- The observed RTO number from Step 5.
- One thing that stood out (e.g. how long the health-check grace period felt, or the draining behaviour).
- Confirm the two instances landed in different AZs — that is the whole point of the multi-AZ claim.
