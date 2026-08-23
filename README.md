# statcast-ingest-pipeline

Polls MLB Stats API for completed games and ingests play-by-play data (raw JSON + flattened parquet) into S3, via SNS/SQS-triggered Lambdas.

## Prerequisites

- Python 3.12, Docker, [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html), Terraform
- AWS CLI profiles: `localstack` (local dev) and `baseball-lake` (prod)

## Run locally

```bash
make install        # create venv, install deps
make localstack-up  # start LocalStack (docker compose)
```

First time only — bootstrap the Terraform state backend and deploy infra into LocalStack:

```bash
infra/scripts/tf_resources.sh mswerli localstack   # creates tfstate bucket + lock table
make tf-local-apply                                 # creates SNS topic, S3 bucket, SQS queues, IAM roles
```

Invoke a Lambda locally against a fixture event:

```bash
make invoke-poller-daily      # PollerFunction, daily-poll event
make invoke-poller-backfill   # PollerFunction, backfill event
make invoke-play-by-play      # PlayByPlayFunction, fake SQS event
```

Note: locally these run in isolation — the poller publishing to SNS does **not** trigger `PlayByPlayFunction` (that SQS→Lambda wiring only exists once deployed). Run `invoke-play-by-play` separately to test that function.

```bash
make test            # run pytest
make localstack-down # stop LocalStack
make clean            # remove build artifacts/caches
```

## Deploy

Packaging + Terraform apply against real AWS, using the `baseball-lake` profile:

```bash
make tf-prod-plan   # build Lambda zips + terraform plan
make tf-prod-apply   # build Lambda zips + terraform apply
```

`make tf-prod-destroy` tears the stack down. See `infra/terraform/` for resource definitions and `prod.tfvars`/`backends/prod.hcl` for config.
