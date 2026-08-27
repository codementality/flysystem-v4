#!/bin/sh
#ddev-generated
# Creates the project's two default S3 buckets, every time Floci starts.
#
#   public  — objects readable by anyone who can reach the emulator, no
#             credentials. Writing still requires them. For images, uploads and
#             other assets that are meant to be served straight to a browser.
#   private — owner only. Nothing is readable without credentials or a
#             presigned URL. For private uploads and testing presigned links.
#
# Rename either, or set one to an empty string to skip it:
#
#   ddev dotenv set .ddev/.env.floci-aws --floci-aws-public-bucket=assets
#   ddev dotenv set .ddev/.env.floci-aws --floci-aws-private-bucket=""
#   ddev restart
#
# To do more on startup — queues, tables, secrets — add your own script
# alongside this one; see ../README.md.
set -eu

public="${FLOCI_AWS_PUBLIC_BUCKET:-}"
private="${FLOCI_AWS_PRIVATE_BUCKET:-}"
region="${FLOCI_DEFAULT_REGION:-us-east-1}"

# The public/private split is only real when Floci is checking signatures. With
# FLOCI_SERVICES_S3_ENFORCE_AUTH off, every bucket is world-readable AND
# world-writable and the policy applied below is decorative — so say so rather
# than letting the names imply a boundary that is not there.
if [ "${FLOCI_SERVICES_S3_ENFORCE_AUTH:-false}" != "true" ]; then
  echo "floci-aws: WARNING - S3 auth enforcement is off, so every bucket is world-readable" >&2
  echo "floci-aws: AND world-writable, whatever these are named. Re-enable it with:" >&2
  echo "floci-aws:   ddev dotenv set .ddev/.env.floci-aws --floci-aws-s3-enforce-auth=true" >&2
fi

# Hooks run on every container start and the default storage mode keeps state
# across restarts, so an already-existing bucket is the normal case, not an
# error. head-bucket rather than `create-bucket || true` so a real failure — a
# malformed name, S3 disabled — is still reported.
create_bucket() {
  if aws s3api head-bucket --bucket "$1" >/dev/null 2>&1; then
    return 1
  fi
  # us-east-1 is the one region S3 rejects a LocationConstraint for.
  if [ "${region}" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$1" >/dev/null
  else
    aws s3api create-bucket --bucket "$1" \
      --create-bucket-configuration "LocationConstraint=${region}" >/dev/null
  fi
  return 0
}

if [ -n "${public}" ]; then
  if create_bucket "${public}"; then
    echo "floci-aws: created bucket '${public}'"
  else
    echo "floci-aws: bucket '${public}' already exists"
  fi

  # A bucket policy rather than per-object ACLs, so an object is readable the
  # moment it is written and the application does not have to remember to set
  # `public-read` on every upload. This is how a real public asset bucket is
  # configured.
  #
  # s3:GetObject only, by default. Listing the bucket still needs credentials —
  # a publicly listable bucket is a misconfiguration rather than a feature, and
  # nothing needs it to serve an <img src>. Note this does NOT affect an SDK
  # holding the project's credentials: a signed ListObjectsV2, which is what
  # Drupal's Media Library and s3fs issue, works either way.
  #
  # If you find something that really does need anonymous listing:
  #   ddev dotenv set .ddev/.env.floci-aws --floci-aws-public-bucket-list=true
  #
  # Reapplied on every start: it is idempotent, and it repairs the bucket if
  # someone removed the policy by hand.
  list_stmt=""
  if [ "${FLOCI_AWS_PUBLIC_BUCKET_LIST:-false}" = "true" ]; then
    # ListBucket is granted on the bucket ARN itself, not on /* — that is the
    # distinction S3 draws between "list the container" and "read the objects".
    list_stmt=",
    {
      \"Sid\": \"PublicList\",
      \"Effect\": \"Allow\",
      \"Principal\": \"*\",
      \"Action\": \"s3:ListBucket\",
      \"Resource\": \"arn:aws:s3:::${public}\"
    }"
  fi

  cat > /tmp/floci-public-bucket-policy.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${public}/*"
    }${list_stmt}
  ]
}
JSON
  aws s3api put-bucket-policy --bucket "${public}" \
    --policy file:///tmp/floci-public-bucket-policy.json
  rm -f /tmp/floci-public-bucket-policy.json
fi

if [ -n "${private}" ]; then
  # No ACL and no policy: S3's default is owner-only, which is exactly what is
  # wanted here. Presigned URLs are the way in.
  if create_bucket "${private}"; then
    echo "floci-aws: created bucket '${private}'"
  else
    echo "floci-aws: bucket '${private}' already exists"
  fi
fi
