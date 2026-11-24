use std::{
    io::{BufRead, BufReader, Write},
    net::TcpListener as PortReservation,
    path::Path,
    process::{Child, ChildStdin, ChildStdout, Command, Stdio},
    time::Duration,
};

use dirka_engine::engine::{Client, Config, Snapshot, Status};
use serde::Deserialize;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpListener, TcpStream},
    time::{sleep, timeout},
};
use tokio_rustls::rustls::RootCertStore;

// These tests briefly release reserved ports to configure the JS fixture and
// mobile listeners. Serialize them to avoid another fixture claiming that port.
static PORT_FIXTURES: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RelayConfig {
    relay_port: u16,
    route: String,
    key: String,
    ca_path: Option<String>,
}

struct Fixture {
    child: Child,
    input: Option<ChildStdin>,
    output: BufReader<ChildStdout>,
    config: RelayConfig,
}

impl Fixture {
    fn launch(tls: bool) -> Self {
        let mut command = Command::new("node");
        command
            .arg("tool/interop-relay.cjs")
            .current_dir(Path::new(env!("CARGO_MANIFEST_DIR")).join(".."))
            .stdin(Stdio::piped())
            .stdout(Stdio::piped());
        if tls {
            command.arg("--tls");
        }
        let mut child = command
            .spawn()
            .expect("launch pinned JS fixtures with Node");
        let input = child.stdin.take();
        let mut output = BufReader::new(child.stdout.take().unwrap());
        let mut line = String::new();
        output.read_line(&mut line).unwrap();
        let config = serde_json::from_str(&line).expect("relay fixture startup");
        Self {
            child,
            input,
            output,
            config,
        }
    }

    fn send(&mut self, action: &str) {
        writeln!(self.input.as_mut().unwrap(), "{action}").unwrap();
        let mut line = String::new();
        self.output.read_line(&mut line).unwrap();
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(&line).unwrap()["done"],
            action
        );
    }

    fn config(&self, host: &str, ports: Vec<u16>, tls: bool) -> Config {
        Config {
            relay_host: host.into(),
            relay_port: self.config.relay_port,
            route: self.config.route.clone(),
            key: self.config.key.clone(),
            bind_host: "127.0.0.1".into(),
            ports,
            tls,
            timing: Default::default(),
        }
    }

    fn roots(&self) -> RootCertStore {
        let mut roots = RootCertStore::empty();
        roots
            .add(
                std::fs::read(self.config.ca_path.as_ref().unwrap())
                    .unwrap()
                    .into(),
            )
            .unwrap();
        roots
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        self.input.take();
        // Closing stdin normally lets the fixture remove its ephemeral TLS keys.
        for _ in 0..50 {
            if self.child.try_wait().ok().flatten().is_some() {
                return;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn reserve() -> PortReservation {
    PortReservation::bind(("127.0.0.1", 0)).unwrap()
}

fn port(reservation: &PortReservation) -> u16 {
    reservation.local_addr().unwrap().port()
}

async fn status(client: &Client, expected: Status) -> Snapshot {
    match timeout(Duration::from_secs(12), async {
        loop {
            let snapshot = client.snapshot();
            if snapshot.status == expected {
                return snapshot;
            }
            assert!(snapshot.status != Status::Stopped, "{snapshot:?}");
            sleep(Duration::from_millis(20)).await;
        }
    })
    .await
    {
        Ok(snapshot) => snapshot,
        Err(_) => panic!("Expected {expected:?}, got {:?}", client.snapshot()),
    }
}

async fn connect(local: u16, marker: u8) -> TcpStream {
    let mut socket = TcpStream::connect(("127.0.0.1", local)).await.unwrap();
    let mut greeting = [0; 4];
    timeout(Duration::from_secs(5), socket.read_exact(&mut greeting))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(greeting, [marker, 255, 10, 128]);
    socket
}

async fn round_trip(local: u16, marker: u8) {
    let socket = connect(local, marker).await;
    let (mut read, mut write) = socket.into_split();
    let payload: Vec<u8> = (0..=255).cycle().take(1024 * 1024).collect();
    let mut received = Vec::new();
    timeout(Duration::from_secs(10), async {
        tokio::try_join!(
            async {
                write.write_all(&payload).await?;
                write.shutdown().await
            },
            read.read_to_end(&mut received),
        )
    })
    .await
    .unwrap()
    .unwrap();
    assert_eq!(received, payload);
}

#[tokio::test]
async fn independent_clients_forward_clean_up_and_reconnect() {
    let _ports = PORT_FIXTURES.lock().await;
    let mut relay = Fixture::launch(false);
    let (one, two, three) = (reserve(), reserve(), reserve());
    let (first, second, third) = (port(&one), port(&two), port(&three));
    drop((one, two, three));
    let mut a = Client::spawn(relay.config("127.0.0.1", vec![first, second], false), None);
    let mut config = relay.config("127.0.0.1", vec![third], false);
    config.timing.reconnect_ms = 100;
    config.timing.max_reconnect_ms = 300;
    config.timing.jitter_percent = 0;
    let mut b = Client::spawn(config, None);

    status(&a, Status::WaitingForAgent).await;
    status(&b, Status::WaitingForAgent).await;
    relay.send("start-agent");
    status(&a, Status::Connected).await;
    status(&b, Status::Connected).await;
    tokio::join!(
        round_trip(first, 0),
        round_trip(second, 1),
        round_trip(third, 0)
    );

    let mut live = connect(first, 0).await;
    a.stop();
    a.stop();
    assert!(status(&a, Status::Stopped).await.error.is_none());
    assert_eq!(
        timeout(Duration::from_secs(2), live.read(&mut [0]))
            .await
            .unwrap()
            .unwrap(),
        0
    );
    let _first_rebound = TcpListener::bind(("127.0.0.1", first)).await.unwrap();
    let _second_rebound = TcpListener::bind(("127.0.0.1", second)).await.unwrap();
    round_trip(third, 0).await;

    relay.send("stop-agent");
    status(&b, Status::WaitingForAgent).await;
    relay.send("start-agent");
    status(&b, Status::Connected).await;
    relay.send("stop-relay");
    status(&b, Status::Connecting).await;
    relay.send("start-relay");
    timeout(Duration::from_secs(3), status(&b, Status::Connected))
        .await
        .expect("the client uses the configured reconnect delay");
    round_trip(third, 0).await;
    b.stop();
    status(&b, Status::Stopped).await;
    let _third_rebound = TcpListener::bind(("127.0.0.1", third)).await.unwrap();
}

#[tokio::test]
async fn verified_tls_rejects_untrusted_roots_and_wrong_hostname() {
    let _ports = PORT_FIXTURES.lock().await;
    let mut relay = Fixture::launch(true);
    relay.send("start-agent");
    let (one, two, three) = (reserve(), reserve(), reserve());
    let (trusted, untrusted, wrong_name) = (port(&one), port(&two), port(&three));
    drop((one, two, three));
    let mut success = Client::spawn(
        relay.config("localhost", vec![trusted], true),
        Some(relay.roots()),
    );
    let bad_ca = Client::spawn(
        relay.config("localhost", vec![untrusted], true),
        Some(RootCertStore::empty()),
    );
    let bad_host = Client::spawn(
        relay.config("127.0.0.1", vec![wrong_name], true),
        Some(relay.roots()),
    );
    status(&success, Status::Connected).await;
    for refused in [&bad_ca, &bad_host] {
        let stopped = status(refused, Status::Stopped).await;
        assert_eq!(
            stopped.error.as_deref(),
            Some("Relay TLS certificate could not be verified")
        );
    }
    round_trip(trusted, 0).await;
    success.stop();
    status(&success, Status::Stopped).await;
}

#[tokio::test]
async fn bind_failure_releases_listeners_opened_earlier() {
    let _ports = PORT_FIXTURES.lock().await;
    let (one, two) = (reserve(), reserve());
    let (available, occupied) = (port(&one), port(&two));
    drop(one);
    let client = Client::spawn(
        Config {
            relay_host: "127.0.0.1".into(),
            relay_port: 1,
            route: "dirka-interop".into(),
            key: "a".repeat(32),
            bind_host: "127.0.0.1".into(),
            ports: vec![available, occupied],
            tls: false,
            timing: Default::default(),
        },
        None,
    );
    let stopped = status(&client, Status::Stopped).await;
    let error = stopped.error.unwrap();
    assert!(error.contains(&format!("127.0.0.1:{occupied}")), "{error}");
    let _available_to_rebind = TcpListener::bind(("127.0.0.1", available)).await.unwrap();
}
