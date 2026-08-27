# Flysystem v4 — Configuration & Upgrade Path

Status: **Draft**. Companion: `architecture.md`, `feature-evaluation-log.md`, `drupal-issue-queue.md`.

## 1. Preservation contract

v4 is a **total rewrite** of flysystem 3.0's code. Only two structures survive, **additive-only** (no restructuring):

1. The `settings.php` configuration array.
2. The config-entity structures for adapters configured through the admin UI.

Goal: 3.0 → 4.0 upgrades with minimal disruption — every *working* 3.0 config keeps working; the only behavioral changes are the deliberate, documented BC breaks in §4.

## 2. The preserved settings.php array (verbatim shape)

### Local File System
```php
$settings['flysystem']['flylocal'] = [
  'driver'          => 'local',
  'public_url_base' => 'https://example.com/sites/default/files',
  'writable'        => TRUE,
  'config'          => [
    'root' => '/var/www/html/web/sites/default/files',
  ],
];
```

### S3/S3-compatible storage (s3 driver)

```php
$settings['flysystem']['media'] = [
  'driver'          => 's3',
  'public_url_base' => 'https://mysite.example.com',
  'writable'        => TRUE,
  'config'          => [
    'bucket'              => 'my-bucket',
    'region'              => 'us-east-1',
    'prefix'              => '',              // Optional key prefix.
    'endpoint'            => 'https://...',  // Required for non-AWS services.
    'path_style_endpoint' => FALSE,          // TRUE required for MinIO.
    'send_chunked_body'   => TRUE,           // FALSE required for MinIO.
    'default_visibility'  => 'public',       // 'public' or 'private'.
    'credentials'         => [               // Omit to use IAM / env vars.
      'key'    => 'AKIAIOSFODNN7EXAMPLE',
      'secret' => 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
    ],
  ],
];
```



### AWS S3 with presigned URLs and Cloudfront (aws_s3 driver)

#### Public bucket with CloudFront

```php
$settings['flysystem']['media'] = [
  'driver'          => 'aws_s3',
  'public_url_base' => 'https://mysite.example.com',
  'config'          => [
    'bucket'     => 'my-public-bucket',
    'region'     => 'us-east-1',
    'visibility' => 'public',
    'cloudfront' => [
      'domain' => 'https://abc123.cloudfront.net',
    ],
    // No credentials — use IAM instance role in production.
  ],
];
```

### Private bucket with presigned URLs

```php
$settings['flysystem']['secure-media'] = [
  'driver'          => 'aws_s3',
  'public_url_base' => 'https://mysite.example.com',
  'config'          => [
    'bucket'           => 'my-private-bucket',
    'region'           => 'us-east-1',
    'visibility'       => 'private',
    'presigned_expiry' => 3600,
  ],
];
```

### All aws_s3 config keys
```php
'config' => [
  'bucket'           => 'my-bucket',      // Required.
  'region'           => 'us-east-1',      // Required.
  'prefix'           => '',               // Optional key prefix.
  'visibility'       => 'public',         // 'public' or 'private'. Default 'public'.
  'presigned_expiry' => 3600,             // Presigned URL lifetime in seconds. Default 3600.
  'cloudfront'       => [                 // Optional. Public files only.
    'domain' => 'https://abc123.cloudfront.net',
  ],
  'credentials'      => [                 // Omit in production; use IAM roles.
    'key'    => 'AKIAIOSFODNN7EXAMPLE',
    'secret' => 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
  ],
],
```

### IAM policy — public bucket (minimum permissions)

```
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
        "s3:ListBucket", "s3:GetObjectAcl", "s3:PutObjectAcl"
      ],
      "Resource": [
        "arn:aws:s3:::my-bucket",
        "arn:aws:s3:::my-bucket/*"
      ]
    }
  ]
}
```

### IAM policy — private bucket (minimum permissions)

```
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-private-bucket",
        "arn:aws:s3:::my-private-bucket/*"
      ]
    }
  ]
}
```

### SFTP storage (sftp ddriver)

#### Password authentication

```php
$settings['flysystem']['sftp_media'] = [
  'driver'          => 'sftp',
  'public_url_base' => 'https://mysite.example.com/media',  // Optional.
  'config'          => [
    'host'     => 'sftp.example.com',
    'username' => 'deploy',
    'password' => 'secret',
    'root'     => '/var/www/uploads',
  ],
];
```

#### Private key authentication

```php
$settings['flysystem']['sftp_media'] = [
  'driver'          => 'sftp',
  'public_url_base' => 'https://mysite.example.com/media',  // Optional.
  'config'          => [
    'host'        => 'sftp.example.com',
    'username'    => 'deploy',
    'private_key' => "-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----",
    'passphrase'  => 'my-key-passphrase',  // Omit if key has no passphrase.
    'root'        => '/var/www/uploads',
  ],
];
```

#### All sftp config keys

```php
'config' => [
  'host'             => 'sftp.example.com',  // Required.
  'username'         => 'deploy',            // Required.
  'root'             => '/var/www/uploads',  // Required. Absolute path on remote server.
  'password'         => 'secret',            // Exactly one of password or private_key.
  'private_key'      => '...',               // Inline PEM string.
  'passphrase'       => null,                // Passphrase for private key, if any.
  'port'             => 22,                  // Default 22.
  'timeout'          => 10,                  // Default 10 seconds.
  'max_tries'        => 4,                   // Default 4 attempts.
  'use_agent'        => false,               // SSH agent forwarding. Default FALSE.
  'host_fingerprint' => 'SHA256:abc123...',  // Recommended in production.
  'visibility'       => 'public',            // 'public' (0644/0755) or 'private' (0600/0700).
],
```

**Rules (preserved from 3.0, load-bearing):**
- `public_url_base` MUST be at the **top level** of the scheme array, never inside `config`.
- `config` holds only driver-specific keys (bucket, region, root, prefix, etc.).
- Scheme names: lowercase letters, numbers, hyphens only. **Underscores not permitted.**
- Top-level keys: `driver` (required), `config` (array, default `[]`), `writable` (bool, default TRUE), `public_url_base` (string, default NULL).
- Derived from `config` (not top-level): `visibility` (from `config['visibility'] ?? config['default_visibility'] ?? 'public'`), `cloudfrontDomain` (from `config['cloudfront']['domain']`), `presignedExpiry` (from `config['presigned_expiry'] ?? 3600`).

**Preserved visibility asymmetry**: `s3` uses `default_visibility`; `aws_s3` uses `visibility`. Both normalize through `AdapterDefinition` (`visibility ?? default_visibility ?? 'public'`).

## 3. The preserved config-entity structure

- Entity id: `flysystem_filesystem`, config prefix `filesystem` → config objects `flysystem.filesystem.<scheme>`.
- `config_export`: `id, label, driver, public_url_base, writable, config, connection_status, connection_status_message`.
- Base fields: `id` (scheme), `label`, `driver`, `public_url_base` (nullable), `writable` (bool), `config` (array), `connection_status` (default `'untested'`), `connection_status_message`.
- **Schema**: `flysystem.filesystem.*` maps `config: type: flysystem.adapter_config.[%parent.driver]` — the dynamic per-driver schema.
- **Key-module secret resolution** (preserved): the sensitive-field map resolves `*_key_id` references:
  - `s3`/`aws_s3`: `credentials.secret` → `credentials.secret_key_id`
  - `sftp`: `password` → `password_key_id`, `private_key` → `private_key_key_id`, `passphrase` → `passphrase_key_id`
- **Precedence (preserved)**: settings.php wins over config entities per scheme; the admin form warns when a settings.php definition shadows an entity.

**Driver config keys (preserved contract):**
- `local`: `root` (required).
- `s3` (AsyncAws): `bucket`, `region`, `prefix` (default `''`), `endpoint`, `path_style_endpoint`, `send_chunked_body`, `default_visibility`, `credentials.key`/`credentials.secret`/`credentials.secret_key_id`.
- `aws_s3` (AWS SDK v3): `bucket`, `region`, `prefix` (default `''`), `visibility`, `presigned_expiry` (default 3600), `cloudfront.domain`, `credentials.key`/`secret`/`secret_key_id`.
- `sftp`: `host`, `username`, `root` (required), `password` XOR `private_key`, `passphrase`, `port` (22), `timeout` (10), `max_tries` (4), `use_agent`, `host_fingerprint`, `visibility`, + `*_key_id` secret refs.

## 4. Additive changes and deliberate BC breaks

### Additive (new optional keys — existing configs upgrade untouched)

| Change | Where | Default | Notes |
|---|---|---|---|
| `use_acl` (driver-scoped) | `config` sub-array, `s3`/`aws_s3` drivers only | **FALSE** | Off = subclassed adapter omits ACLs (modern BucketOwnerEnforced buckets work); on = legacy ACL behavior. **Documented + expressly described in the config-entity form field.** |
| Prefix URL correctness | `getExternalUrl()` | — | URLs include the S3 `prefix` (fixes 3.0-ref 404 on prefixed public URLs). No config change; behavioral fix. |

### Deliberate BC breaks (documented in the upgrade guide)

| Change | 3.0 behavior | 4.0 behavior | Upgrade guidance |
|---|---|---|---|
| `aws_s3` default-presigned URLs | Implicit presigned (3600s expiry) when no `public_url_base` | **Loud validation error** if neither `public_url_base` nor explicit `presigned_expiry` is set | Add `public_url_base` or explicitly set `presigned_expiry` |
| `writable: FALSE` | Informational only — never enforced | **Enforced** via `ReadOnlyFilesystemAdapter` (writes fail) | Sites that set `writable: false` gain real read-only enforcement on upgrade |
| URL masking (2.2-era `/_flysystem/...`) | Removed in 3.0; not revived | Not in v4 | Private content uses the access-checked route; public uses `public_url_base` |

### Explicit presigned policy

- `public_url_base` is the recommended, cache-safe URL source.
- Explicit `presigned_expiry` preserves presigned behavior (documented cache-unsafe: signatures expire inside cached pages — never presign content that lands in cached output).
- Neither → validation error (§4 above).

## 5. Documentation obligations (non-negotiable)

1. **`public_url_base` for remote public schemes** — per-driver "URL configuration for remote public schemes" section with concrete examples (`local`, `s3`, `aws_s3`, `sftp`), showing `public_url_base` top-level + `config` sub-array.
2. **`use_acl`** — called out in scheme-config docs and the upgrade guide, with its FALSE default explained; **the config-entity form field description must expressly describe it and its default** (not just a label).
3. **Security note — no `.htaccess` on remote private schemes**: remote private access control is Drupal's `file_download` route + permissions, not filesystem-level protection. Explicitly warn Apache/`.htaccess` sites and sites that ported those rules into Nginx configs that the defense does not exist on remote schemes.
4. **Presigned cache-unsafety** (see §4).
5. **S3 `prefix` semantics** — "set before filling the bucket, not a migration tool" (enabling a prefix hides existing unprefixed objects; disabling orphans prefixed ones).
6. **Stat-cache staleness edge** — writes outside Drupal (direct to S3 by another app) may lag up to the TTL.
7. **Read-only schemes** — externally-managed files (third-party generation) pattern: objects never written by Drupal; `unlink()` removes the `file_managed` record, not the object.

## 6. Upgrade path 3.0 → 4.0

1. Config carries over **unchanged** — the settings.php array and config-entity structures are additive-only.
2. Files stay in place (no migration required for the upgrade itself; see `migration.md` for adapter-switch migration as an optional submodule).
3. Review the deliberate BC breaks (§4): `aws_s3` schemes without `public_url_base`/`presigned_expiry` will fail validation loudly — the upgrade guide walks through adding them.
4. `writable: false` schemes become genuinely read-only — verify no workflows depend on writing to them.
5. The developer README and upgrade guide document all of the above before the first release.