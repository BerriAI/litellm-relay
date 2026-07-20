use std::{
    fs,
    path::{Path, PathBuf},
};

use anyhow::{anyhow, Result};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use rcgen::{
    BasicConstraints, CertificateParams, DnType, ExtendedKeyUsagePurpose, IsCa, Issuer, KeyPair,
    KeyUsagePurpose, SanType,
};
use rustls::{
    pki_types::{
        CertificateDer, PrivateKeyDer, PrivatePkcs1KeyDer, PrivatePkcs8KeyDer, PrivateSec1KeyDer,
    },
    ClientConfig, RootCertStore, ServerConfig,
};
use time::{Duration, OffsetDateTime};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AlpnProtocol {
    Http11,
}

impl AlpnProtocol {
    fn wire_name(self) -> Vec<u8> {
        match self {
            Self::Http11 => b"http/1.1".to_vec(),
        }
    }
}

#[derive(Debug)]
pub struct CertificateAuthority {
    pub cert_path: PathBuf,
    key_path: PathBuf,
}

#[cfg(not(test))]
pub fn install_default_crypto_provider() {
    let _ = rustls::crypto::ring::default_provider().install_default();
}

pub fn ensure_ca(ca_dir: &Path) -> Result<CertificateAuthority> {
    fs::create_dir_all(ca_dir)?;
    let cert_path = ca_dir.join("litellm-relay-ca.pem");
    let key_path = ca_dir.join("litellm-relay-ca-key.pem");
    if cert_path.exists() && key_path.exists() {
        return Ok(CertificateAuthority {
            cert_path,
            key_path,
        });
    }
    let signing_key = KeyPair::generate()?;
    let mut params = CertificateParams::default();
    params.not_before = OffsetDateTime::now_utc();
    params.not_after = params.not_before + Duration::days(825);
    params
        .distinguished_name
        .push(DnType::CommonName, "LiteLLM Relay Local Root CA");
    params.is_ca = IsCa::Ca(BasicConstraints::Constrained(0));
    params.key_usages = vec![KeyUsagePurpose::KeyCertSign, KeyUsagePurpose::CrlSign];
    let certificate = params.self_signed(&signing_key)?;
    fs::write(&cert_path, certificate.pem())?;
    fs::write(&key_path, signing_key.serialize_pem())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&key_path, fs::Permissions::from_mode(0o600))?;
    }
    Ok(CertificateAuthority {
        cert_path,
        key_path,
    })
}

pub fn server_tls_config(host: &str, ca_dir: &Path) -> Result<ServerConfig> {
    let (cert_path, key_path) = ensure_leaf_cert(host, ca_dir)?;
    let cert_file = fs::read(&cert_path)?;
    let key_file = fs::read(&key_path)?;
    let certs = load_cert_chain(&cert_file)?;
    let key = load_private_key(&key_file)?;
    let mut config = ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(certs, key)?;
    config.alpn_protocols = vec![AlpnProtocol::Http11.wire_name()];
    Ok(config)
}

pub fn client_tls_config() -> ClientConfig {
    let mut roots = RootCertStore::empty();
    roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    let mut config = ClientConfig::builder()
        .with_root_certificates(roots)
        .with_no_client_auth();
    config.alpn_protocols = vec![AlpnProtocol::Http11.wire_name()];
    config
}

fn ensure_leaf_cert(host: &str, ca_dir: &Path) -> Result<(PathBuf, PathBuf)> {
    let ca = ensure_ca(ca_dir)?;
    let certs_dir = ca_dir.join("certs");
    fs::create_dir_all(&certs_dir)?;
    let safe_host = safe_cert_name(host);
    let cert_path = certs_dir.join(format!("{safe_host}.pem"));
    let key_path = certs_dir.join(format!("{safe_host}-key.pem"));
    if cert_path.exists() && key_path.exists() {
        return Ok((cert_path, key_path));
    }
    let ca_cert_pem = fs::read_to_string(&ca.cert_path)?;
    let ca_key_pem = fs::read_to_string(&ca.key_path)?;
    let ca_key = KeyPair::from_pem(&ca_key_pem)?;
    let issuer = Issuer::from_ca_cert_pem(&ca_cert_pem, ca_key)?;
    let signing_key = KeyPair::generate()?;
    let mut params = CertificateParams::default();
    params.subject_alt_names = vec![SanType::DnsName(host.try_into()?)];
    params.not_before = OffsetDateTime::now_utc();
    params.not_after = params.not_before + Duration::days(90);
    params.distinguished_name.push(DnType::CommonName, host);
    params.is_ca = IsCa::NoCa;
    params.key_usages = vec![
        KeyUsagePurpose::DigitalSignature,
        KeyUsagePurpose::KeyEncipherment,
    ];
    params.extended_key_usages = vec![ExtendedKeyUsagePurpose::ServerAuth];
    let certificate = params.signed_by(&signing_key, &issuer)?;
    fs::write(&cert_path, certificate.pem())?;
    fs::write(&key_path, signing_key.serialize_pem())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&key_path, fs::Permissions::from_mode(0o600))?;
    }
    Ok((cert_path, key_path))
}

fn load_cert_chain(pem: &[u8]) -> Result<Vec<CertificateDer<'static>>> {
    let certs = decode_pem_blocks(pem, "CERTIFICATE")?;
    if certs.is_empty() {
        return Err(anyhow!("leaf certificate not found"));
    }
    Ok(certs.into_iter().map(CertificateDer::from).collect())
}

fn load_private_key(pem: &[u8]) -> Result<PrivateKeyDer<'static>> {
    if let Some(key) = decode_first_pem_block(pem, "PRIVATE KEY")? {
        return Ok(PrivateKeyDer::from(PrivatePkcs8KeyDer::from(key)));
    }
    if let Some(key) = decode_first_pem_block(pem, "RSA PRIVATE KEY")? {
        return Ok(PrivateKeyDer::from(PrivatePkcs1KeyDer::from(key)));
    }
    if let Some(key) = decode_first_pem_block(pem, "EC PRIVATE KEY")? {
        return Ok(PrivateKeyDer::from(PrivateSec1KeyDer::from(key)));
    }
    Err(anyhow!("leaf private key not found"))
}

fn decode_first_pem_block(pem: &[u8], label: &str) -> Result<Option<Vec<u8>>> {
    Ok(decode_pem_blocks(pem, label)?.into_iter().next())
}

fn decode_pem_blocks(pem: &[u8], label: &str) -> Result<Vec<Vec<u8>>> {
    let text = std::str::from_utf8(pem)?;
    let begin = format!("-----BEGIN {label}-----");
    let end = format!("-----END {label}-----");
    let mut rest = text;
    let mut blocks = Vec::new();

    while let Some(begin_index) = rest.find(&begin) {
        let block_start = begin_index + begin.len();
        let after_begin = &rest[block_start..];
        let end_index = after_begin
            .find(&end)
            .ok_or_else(|| anyhow!("unterminated PEM block: {label}"))?;
        let encoded: String = after_begin[..end_index]
            .chars()
            .filter(|ch| !ch.is_whitespace())
            .collect();
        blocks.push(STANDARD.decode(encoded)?);
        rest = &after_begin[end_index + end.len()..];
    }

    Ok(blocks)
}

fn safe_cert_name(host: &str) -> String {
    let cleaned = host
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || matches!(ch, '_' | '.' | '-') {
                ch
            } else {
                '_'
            }
        })
        .collect::<String>()
        .trim_matches(['.', '_'])
        .to_string();
    if cleaned.is_empty() {
        "host".into()
    } else {
        cleaned
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn safe_cert_name_removes_path_characters() {
        assert_eq!(safe_cert_name("www.notion.so:443"), "www.notion.so_443");
    }

    #[test]
    fn ensure_ca_and_leaf_cert_are_reusable() {
        let ca_dir =
            std::env::temp_dir().join(format!("litellm-relay-cert-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&ca_dir);

        let ca = ensure_ca(&ca_dir).expect("CA should be generated");
        let ca_again = ensure_ca(&ca_dir).expect("CA should be reused");
        assert_eq!(ca.cert_path, ca_again.cert_path);
        assert_eq!(ca.key_path, ca_again.key_path);
        load_cert_chain(&fs::read(&ca.cert_path).unwrap()).expect("CA PEM should parse");
        load_private_key(&fs::read(&ca.key_path).unwrap()).expect("CA key PEM should parse");

        let (leaf_path, leaf_key_path) =
            ensure_leaf_cert("example.test", &ca_dir).expect("leaf should be generated");
        load_cert_chain(&fs::read(leaf_path).unwrap()).expect("leaf PEM should parse");
        load_private_key(&fs::read(leaf_key_path).unwrap()).expect("leaf key PEM should parse");

        let _ = fs::remove_dir_all(ca_dir);
    }
}
