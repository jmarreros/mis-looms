#!/bin/bash
# Crea un certificado de firma de código autofirmado ("Mis Looms Dev") en el llavero.
# Con una firma estable macOS recuerda los permisos de Grabación de pantalla y Micrófono
# entre compilaciones (con firma ad-hoc se pierden cada vez). Solo hace falta una vez.
set -euo pipefail

NOMBRE="Mis Looms Dev"
LLAVERO="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "$LLAVERO" | grep -q "$NOMBRE"; then
    echo "El certificado '$NOMBRE' ya existe."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CLAVE="mislooms-temporal"

cat > "$TMP/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NOMBRE
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/clave.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf"
/usr/bin/openssl pkcs12 -export -inkey "$TMP/clave.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -passout "pass:$CLAVE"

security import "$TMP/cert.p12" -k "$LLAVERO" -P "$CLAVE" -T /usr/bin/codesign
# Evita que codesign pida la contraseña del llavero en cada firma.
security add-trusted-cert -p codeSign -k "$LLAVERO" "$TMP/cert.pem" || true

echo "Certificado '$NOMBRE' creado."
security find-identity -p codesigning "$LLAVERO"
