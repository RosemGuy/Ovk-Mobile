#!/bin/bash
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/ovk-trust-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
cat > "$test_dir/root.cnf" <<'CONFIG'
[req]
distinguished_name=dn
x509_extensions=ca
prompt=no
[dn]
CN=OpenVK local test CA
[ca]
basicConstraints=critical,CA:TRUE
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
CONFIG
cat > "$test_dir/leaf.cnf" <<'CONFIG'
[req]
distinguished_name=dn
prompt=no
[dn]
CN=api.example.invalid
CONFIG
cat > "$test_dir/extensions.cnf" <<'CONFIG'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:api.example.invalid
CONFIG
openssl req -new -x509 -newkey rsa:2048 -nodes -sha256 -days 365 \
  -config "$test_dir/root.cnf" -keyout "$test_dir/root.key" -out "$test_dir/root.pem" 2>/dev/null
openssl req -new -newkey rsa:2048 -nodes -sha256 \
  -config "$test_dir/leaf.cnf" -keyout "$test_dir/leaf.key" -out "$test_dir/leaf.csr" 2>/dev/null
openssl x509 -req -in "$test_dir/leaf.csr" -CA "$test_dir/root.pem" -CAkey "$test_dir/root.key" \
  -set_serial 2 -days 1 -sha256 -extfile "$test_dir/extensions.cnf" -out "$test_dir/leaf.pem" 2>/dev/null
openssl x509 -in "$test_dir/root.pem" -outform DER -out "$test_dir/root.der"
openssl x509 -in "$test_dir/leaf.pem" -outform DER -out "$test_dir/leaf.der"
xcrun clang -fobjc-arc -fblocks -framework Foundation -framework Security \
  -I "$project_dir/OpenVK" "$project_dir/OpenVK/OVKTrust.m" \
  "$project_dir/tools/TrustTests.m" -o "$test_dir/trust-tests"
"$test_dir/trust-tests" "$test_dir/leaf.der" "$test_dir/root.der"
