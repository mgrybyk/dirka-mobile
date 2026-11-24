use std::{io, sync::Arc, time::Duration};

use tokio::{
    io::{AsyncBufReadExt, AsyncRead, AsyncWrite, AsyncWriteExt, BufReader},
    net::TcpStream,
    time::timeout,
};
use tokio_rustls::{
    TlsConnector,
    rustls::{ClientConfig, RootCertStore, pki_types::ServerName},
};

use crate::protocol::nt_client_max_frame_bytes;

pub trait Socket: AsyncRead + AsyncWrite + Unpin + Send {}
impl<T: AsyncRead + AsyncWrite + Unpin + Send> Socket for T {}
pub type Stream = Box<dyn Socket>;

pub fn public_roots() -> RootCertStore {
    RootCertStore::from_iter(webpki_roots::TLS_SERVER_ROOTS.iter().cloned())
}

#[derive(Clone)]
pub struct Relay {
    host: String,
    port: u16,
    tls: Option<(TlsConnector, ServerName<'static>)>,
}

impl Relay {
    pub fn new(host: String, port: u16, roots: Option<RootCertStore>) -> io::Result<Self> {
        let tls = roots
            .map(|roots| {
                let name = ServerName::try_from(host.clone())
                    .map_err(|_| io::Error::other("Invalid TLS relay hostname"))?;
                let config = ClientConfig::builder_with_provider(Arc::new(
                    tokio_rustls::rustls::crypto::ring::default_provider(),
                ))
                .with_safe_default_protocol_versions()
                .map_err(io::Error::other)?
                .with_root_certificates(roots)
                .with_no_client_auth();
                Ok::<_, io::Error>((TlsConnector::from(Arc::new(config)), name))
            })
            .transpose()?;
        Ok(Self { host, port, tls })
    }

    pub async fn connect(&self) -> io::Result<Stream> {
        let tcp = TcpStream::connect((self.host.as_str(), self.port)).await?;
        tcp.set_nodelay(true)?;
        match &self.tls {
            Some((connector, name)) => Ok(Box::new(connector.connect(name.clone(), tcp).await?)),
            None => Ok(Box::new(tcp)),
        }
    }
}

/// Bounded LF framing. The partial frame lives in this reader across cancelled
/// reads, and handing the BufReader to forwarding preserves prefetched payload.
pub struct Frames<R> {
    pub reader: BufReader<R>,
    partial: Vec<u8>,
    limit: usize,
}

impl<R: AsyncRead + Unpin> Frames<R> {
    pub fn new(reader: R) -> Self {
        Self {
            reader: BufReader::new(reader),
            partial: Vec::new(),
            limit: unsafe { nt_client_max_frame_bytes() },
        }
    }

    pub async fn frame(&mut self) -> io::Result<Vec<u8>> {
        loop {
            let bytes = self.reader.fill_buf().await?;
            if bytes.is_empty() {
                return Err(io::ErrorKind::UnexpectedEof.into());
            }
            let newline = bytes.iter().position(|&byte| byte == b'\n');
            let count = newline.unwrap_or(bytes.len());
            if self.partial.len() + count > self.limit {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "Relay frame exceeded its limit",
                ));
            }
            self.partial.extend_from_slice(&bytes[..count]);
            self.reader.consume(count + usize::from(newline.is_some()));
            if newline.is_some() {
                return Ok(std::mem::take(&mut self.partial));
            }
        }
    }
}

pub async fn send(
    writer: &mut (impl AsyncWrite + Unpin),
    frame: &[u8],
    deadline: Duration,
) -> io::Result<()> {
    timeout(deadline, writer.write_all(frame)).await?
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{AsyncReadExt, duplex};

    #[tokio::test]
    async fn frame_reader_keeps_partial_frames_and_coalesced_binary_payload() {
        let (mut relay, client) = duplex(32);
        let mut frames = Frames::new(client);

        relay.write_all(b"rea").await.unwrap();
        assert!(
            timeout(Duration::from_millis(20), frames.frame())
                .await
                .is_err()
        );
        relay.write_all(b"dy\n\0\xff\n").await.unwrap();
        assert_eq!(frames.frame().await.unwrap(), b"ready");

        let mut payload = [0; 3];
        frames.reader.read_exact(&mut payload).await.unwrap();
        assert_eq!(payload, [0, 255, 10]);
    }
}
