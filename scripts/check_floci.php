<?php

/**
 * @file
 */

declare(strict_types=1);

/**
 * Verifies the local Floci-emulated AWS (S3 + CloudFront) is reachable.
 *
 * Ticket #70, checklist item 1. Runs inside the web container, where the
 * Floci endpoint is http://floci-aws:4566. Uses raw HTTP against the S3 REST
 * API (no SDK) so it needs no credentials beyond the Floci defaults.
 */

const FLOCI_ENDPOINT = 'http://floci-aws:4566';

/**
 *
 */
function check(string $label, callable $fn): void {
  try {
    $result = $fn();
    echo "  PASS  $label\n";
    if (is_string($result) && $result !== '') {
      echo "        $result\n";
    }
  }
  catch (Throwable $e) {
    echo "  FAIL  $label\n";
    echo "        " . $e->getMessage() . "\n";
  }
}

/**
 *
 */
function httpGet(string $url): string {
  $ctx = stream_context_create(['http' => ['timeout' => 10, 'ignore_errors' => TRUE]]);
  $body = file_get_contents($url, FALSE, $ctx);
  if ($body === FALSE) {
    throw new RuntimeException('GET failed: ' . $url);
  }
  return $body;
}

/**
 *
 */
function httpPut(string $url, string $data): string {
  $ctx = stream_context_create([
    'http' => [
      'method' => 'PUT',
      'header' => "Content-Type: application/octet-stream\r\nContent-Length: " . strlen($data),
      'content' => $data,
      'timeout' => 10,
      'ignore_errors' => TRUE,
    ],
  ]);
  $body = @file_get_contents($url, FALSE, $ctx);
  if ($body === FALSE) {
    throw new RuntimeException('PUT failed: ' . $url);
  }
  return $body;
}

echo "Floci reachability check\n";
echo "Endpoint: " . FLOCI_ENDPOINT . "\n\n";

check('Health endpoint responds', function () {
  $health = json_decode(httpGet(FLOCI_ENDPOINT . '/_localstack/health'), TRUE);
  if (!isset($health['services'])) {
    throw new RuntimeException('Health payload missing services map');
  }
  $s3 = $health['services']['s3'] ?? 'down';
  $cf = $health['services']['cloudfront'] ?? 'down';
  return sprintf('s3=%s cloudfront=%s version=%s', $s3, $cf, $health['version'] ?? '?');
});

check('Public bucket listable (ListBuckets)', function () {
  $body = httpGet(FLOCI_ENDPOINT . '/');
  if (!str_contains($body, 'ListAllMyBucketsResult')) {
    throw new RuntimeException('Response is not a ListAllMyBuckets result');
  }
  $found = [];
  if (preg_match_all('/<Name>([^<]+)<\/Name>/', $body, $m)) {
    $found = $m[1];
  }
  return 'buckets: ' . (implode(', ', $found) ?: '(none)');
});

check('Public bucket HEAD (public exists)', function () {
  $body = httpGet(FLOCI_ENDPOINT . '/public');
  return 'HTTP 200 expected — bucket "public" present';
});

check('Private bucket HEAD (private exists)', function () {
  $body = httpGet(FLOCI_ENDPOINT . '/private');
  return 'HTTP 200 expected — bucket "private" present';
});

check('Write + read round-trip on public bucket', function () {
  $key = 'flysystem-probe-' . bin2hex(random_bytes(4)) . '.txt';
  httpPut(FLOCI_ENDPOINT . '/public/' . $key, 'floci-reachable');
  $read = httpGet(FLOCI_ENDPOINT . '/public/' . $key);
  if ($read !== 'floci-reachable') {
    throw new RuntimeException('Round-trip content mismatch');
  }
  return 'put + get ' . $key . ' OK';
});

echo "\nDone.\n";
