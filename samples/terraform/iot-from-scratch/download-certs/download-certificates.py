#!/usr/bin/env python3
"""
download-certificates.py.

Download certificates and their private keys from OCI Certificate Service.

Usage:
  python download-certificates.py certificates.json output_dir [--key-password PASSWORD] [--pfx-password PASSWORD]

Arguments:
  certificates.json     Path to JSON file mapping CN to certificate OCIDs.
  output_dir            Directory to save extracted certificates.

Options:
  --key-password        Optional. Password to encrypt private keys.
  --pfx-password        Optional. If provided, generate PFX bundles for certificates.

The script will, for each CN/OCID pair in certificates.json:
  - Download certificate, private key, and certificate chain from OCI.
  - Save them as <CN>.cert.pem, <CN>.key.pem, <CN>.chain.pem in output_dir.
  - Optionally encrypt private key if password is set.
  - Optionally generate <CN>.pfx (PFX bundle) if pfx-password is set.

OCI authentication relies on environment or ~/.oci/config.
"""

import argparse
import json
import os
import sys
from typing import Any, Dict, Optional

from cryptography import x509
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization.pkcs12 import (
    serialize_key_and_certificates,
)
from oci import (
    certificates as oci_certificates,
    config as oci_config,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download certificates and private keys from OCI."
    )
    parser.add_argument(
        "cert_json", help="Path to JSON file containing CN: OCID mapping"
    )
    parser.add_argument("output_dir", help="Directory to save certificate files")
    parser.add_argument("--key-password", help="Password for encrypting private keys")
    parser.add_argument("--pfx-password", help="Password for the PFX bundles")
    return parser.parse_args()


def fetch_certificate_bundle(
    cert_client: oci_certificates.CertificatesClient, ocid: str
) -> Optional[Any]:
    """Fetch the certificate bundle with private key from OCI."""
    try:
        response = cert_client.get_certificate_bundle(
            certificate_id=ocid,
            stage="CURRENT",
            certificate_bundle_type="CERTIFICATE_CONTENT_WITH_PRIVATE_KEY",
        )
        if not response or not hasattr(response, "data"):
            print(
                f"Failed to retrieve bundle for OCID={ocid}: response is None or lacks 'data'",
                file=sys.stderr,
            )
            return None
        return response.data
    except Exception as ex:
        print(f"Failed to retrieve bundle for OCID={ocid}: {ex}", file=sys.stderr)
        return None


def write_pem_file(path: str, content: str) -> None:
    """Write string content (PEM) to specified path."""
    with open(path, "w") as f:
        f.write(content)


def encrypt_private_key(key_pem: str, password: str) -> Optional[str]:
    """Encrypt private key PEM using a password and return as PEM string."""
    try:
        private_key = serialization.load_pem_private_key(
            key_pem.encode(),
            password=None,
        )
        encrypted_pem = private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.TraditionalOpenSSL,
            encryption_algorithm=serialization.BestAvailableEncryption(
                password.encode()
            ),
        ).decode()
        return encrypted_pem
    except Exception as ex:
        print(f"Failed to encrypt private key: {ex}", file=sys.stderr)
        return None


def export_pfx(
    cn: str, cert_pem: str, key_pem: str, chain_pem: Optional[str], password: str
) -> Optional[bytes]:
    """
    Produce PKCS#12/PFX bundle including cert, key, and (optionally) chain.

    Only RSA keys are supported in this version.
    """
    try:
        private_key = serialization.load_pem_private_key(
            key_pem.encode(), password=None
        )
        if not isinstance(private_key, rsa.RSAPrivateKey):
            print(f"Unexpected private key type for CN={cn}", file=sys.stderr)
            return None
        cert = x509.load_pem_x509_certificate(cert_pem.encode())
        # Parse chain PEM into cert objects (if any)
        cas = None
        if chain_pem:
            cas = []
            for cert_block in chain_pem.split("-----END CERTIFICATE-----"):
                cert_block = cert_block.strip()
                if cert_block:
                    cert_block += "\n-----END CERTIFICATE-----\n"
                    try:
                        ca_cert = x509.load_pem_x509_certificate(cert_block.encode())
                        cas.append(ca_cert)
                    except Exception:
                        pass
            if not cas:
                cas = None
        pfx = serialize_key_and_certificates(
            name=cn.encode(),
            key=private_key,
            cert=cert,
            cas=cas,
            encryption_algorithm=serialization.BestAvailableEncryption(
                password.encode()
            ),
        )
        return pfx
    except Exception as ex:
        print(f"Failed to generate PFX for CN={cn}: {ex}", file=sys.stderr)
        return None


def process_single_certificate(
    cert_client: oci_certificates.CertificatesClient,
    cn: str,
    ocid: str,
    output_dir: str,
    key_password: Optional[str],
    pfx_password: Optional[str],
) -> None:
    """Download a certificate/key/chain for CN from OCI, write files, encrypt if needed, make PFX if requested."""
    print(f"Processing {cn}")
    bundle = fetch_certificate_bundle(cert_client, ocid)
    if not bundle:
        print(f"Skipping {cn}: could not fetch bundle")
        return

    # v1.0 compatibility: Handle cert_chain_pem/certificate_pem for chain
    cert_pem = getattr(bundle, "certificate_pem", None)
    chain_pem = getattr(bundle, "cert_chain_pem", None)
    key_pem = getattr(bundle, "private_key_pem", None)

    if not (cert_pem and chain_pem and key_pem):
        print(f"API response missing required PEM fields for CN={cn}", file=sys.stderr)
        return

    cert_path = os.path.join(output_dir, f"{cn}.cert.pem")
    chain_path = os.path.join(output_dir, f"{cn}.chain.pem")
    key_path = os.path.join(output_dir, f"{cn}.key.pem")

    write_pem_file(cert_path, cert_pem)
    write_pem_file(chain_path, chain_pem)

    final_key_pem = key_pem
    if key_password:
        encrypted_pem = encrypt_private_key(key_pem, key_password)
        if encrypted_pem is not None:
            final_key_pem = encrypted_pem
        else:
            print(f"Private key for {cn} NOT encrypted due to error.")
    write_pem_file(key_path, final_key_pem)

    if pfx_password:
        pfx_bytes = export_pfx(cn, cert_pem, key_pem, chain_pem, pfx_password)
        if pfx_bytes:
            pfx_path = os.path.join(output_dir, f"{cn}.pfx")
            with open(pfx_path, "wb") as f:
                f.write(pfx_bytes)


def main():
    args = parse_args()
    if not os.path.isfile(args.cert_json):
        print(f"Error: File {args.cert_json} does not exist.", file=sys.stderr)
        sys.exit(1)
    os.makedirs(args.output_dir, exist_ok=True)
    with open(args.cert_json, "r") as f:
        cert_map: Dict[str, str] = json.load(f)
    if not isinstance(cert_map, dict):
        print("Input file must be a JSON object mapping CN to OCID.", file=sys.stderr)
        sys.exit(1)

    config = oci_config.from_file(
        profile_name=os.getenv("OCI_CLI_PROFILE", "DEFAULT")
    )  # Uses ~/.oci/config or OCI_CONFIG_FILE env var
    cert_client = oci_certificates.CertificatesClient(config)

    for cn, ocid in cert_map.items():
        process_single_certificate(
            cert_client, cn, ocid, args.output_dir, args.key_password, args.pfx_password
        )
    print("All available certificates processed.")


if __name__ == "__main__":
    main()
