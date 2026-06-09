# Phase 0 Runbook — Legacy Baseline Architecture

This deploys PesaLink's current fragile setup so there is a concrete "before"
state to contrast against. Deploy it, confirm it works, and walk through exactly
where it breaks.

```bash
export AWS_REGION=af-south-1
aws cloudformation deploy \
  --template-file phase-0.yaml \
  --stack-name pesalink-legacy-baseline \
  --capabilities CAPABILITY_IAM
```

Confirm the stack is up:
```bash
IP=$(aws cloudformation describe-stacks --stack-name pesalink-legacy-baseline \
  --query "Stacks[0].Outputs[?OutputKey=='AppPublicIp'].OutputValue" --output text)
curl http://$IP:8080/health    # -> OK
```

Reach the instance (no SSH — SSM only):
```bash
aws ssm start-session --target <instance-id>
```

---

## Single points of failure — the baseline failure map

| Layer | Current state | What happens when it fails | Phase 2 fixes it with |
|-------|---------------|----------------------------|-----------------------|
| Compute | 1× EC2, 1 AZ | App gone until manual rebuild | ASG min 2 across 2 AZs (self-heal) |
| Database | RDS single-AZ, **backups off** | Data loss; RPO ~infinite | Aurora Multi-AZ + 35-day PITR + Global DB |
| Storage | 1 EBS volume, 1 AZ | Receipts lost with the AZ | S3 with cross-region replication |
| Ingress | 1 Elastic IP, single A record | No failover path | ALB + Route 53 failover routing |
| Recovery | None | The 6-hour outage | AWS Backup, Vault Lock, FIS-proven |

This table is the spine of the "before" narrative. The right-hand column previews what each subsequent phase delivers.

---

## Demonstrating the failure (optional but powerful)

Stop the instance and watch the entire platform go dark — there is nothing behind it:
```bash
aws ec2 stop-instances --instance-ids <instance-id>
curl --max-time 5 http://$IP:8080/health    # -> hangs / fails
```
One command reproduces, in miniature, the KSh 18M incident: one box down,
zero redundancy, nothing to fail over to. Restart with `start-instances`.

---

## Teardown
```bash
aws cloudformation delete-stack --stack-name pesalink-legacy-baseline
```
Cleanly deletes — no snapshot is kept because, fittingly, this baseline never
had backups to begin with.
