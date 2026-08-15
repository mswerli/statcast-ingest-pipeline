# Snowflake storage integration setup

`snowflake.tf` creates the AWS-side IAM role/policy for a Snowflake
[storage integration](https://docs.snowflake.com/en/user-guide/data-load-s3-config-storage-integration)
against the `data_lake` bucket, scoped read-only to the `raw/`, `processed/`,
and `play-by-play/` prefixes.

IAM roles and the Snowflake integration object each need a value the other
side produces, so this is a one-time two-phase apply:

## 1. Create the IAM role (placeholder trust policy)

```
terraform apply
```

This creates `<project>-snowflake-storage-integration-role` trusting this
account's own root ARN as a placeholder principal (IAM rejects made-up
account IDs, and Snowflake's real IAM user doesn't exist to trust yet on the
first pass — trusting your own account grants no third party anything).
Note the role ARN from:

```
terraform output snowflake_storage_integration_role_arn
```

## 2. Create the storage integration in Snowflake

Run in a Snowflake worksheet, using the role ARN from step 1 and your bucket
name/prefixes:

```sql
CREATE STORAGE INTEGRATION statcast_s3_integration
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = '<snowflake_storage_integration_role_arn output>'
  STORAGE_ALLOWED_LOCATIONS = (
    's3://<bucket_name>/raw/',
    's3://<bucket_name>/processed/',
    's3://<bucket_name>/play-by-play/'
  );

DESC STORAGE INTEGRATION statcast_s3_integration;
```

From the `DESC` output, note:

- `STORAGE_AWS_IAM_USER_ARN`
- `STORAGE_AWS_EXTERNAL_ID`

## 3. Tighten the IAM trust policy

Re-apply with the real values from step 2, e.g. via a `*.tfvars` file
(don't commit it — it's account-specific, not a secret, but still noise):

```
terraform apply \
  -var="snowflake_storage_aws_iam_user_arn=<STORAGE_AWS_IAM_USER_ARN>" \
  -var="snowflake_storage_aws_external_id=<STORAGE_AWS_EXTERNAL_ID>"
```

This updates the role's trust policy from the placeholder principal to the
actual Snowflake IAM user, scoped to Snowflake's external ID — completing
the trust relationship in both directions.

## 4. Create the stage and verify

```sql
CREATE STAGE statcast_raw_stage
  URL = 's3://<bucket_name>/raw/'
  STORAGE_INTEGRATION = statcast_s3_integration;

LIST @statcast_raw_stage;
```

If `LIST` returns objects, the integration is working end-to-end.

## Widening access later

The integration is read-only (`GetObject`, `GetObjectVersion`, `ListBucket`,
`GetBucketLocation`) and scoped to the three prefixes the pipeline writes.
To add prefixes, extend `snowflake_storage_prefixes` in `variables.tf`. To
allow Snowflake to unload data back into the bucket, add `s3:PutObject`,
`s3:DeleteObject`, and `s3:DeleteObjectVersion` to the policy in
`snowflake.tf`.
