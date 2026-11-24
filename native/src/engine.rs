use std::{collections::HashMap, io, time::Duration};

use ring::rand::{SecureRandom, SystemRandom};
use serde::{Deserialize, Serialize};
use serde_json::json;
use tokio::{
    io::copy_bidirectional,
    net::{TcpListener, TcpStream},
    sync::{mpsc, oneshot, watch},
    task::JoinSet,
    time::{Instant, interval_at, sleep, sleep_until, timeout},
};
use tokio_rustls::rustls::{Error as TlsError, RootCertStore};

use crate::{
    protocol::{Action, Event, Operation, Protocol},
    transport::{Frames, Relay, send},
};

const MAX_STREAMS: usize = 128;

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Config {
    pub relay_host: String,
    pub relay_port: u16,
    pub route: String,
    pub key: String,
    pub bind_host: String,
    pub ports: Vec<u16>,
    pub tls: bool,
    #[serde(default)]
    pub timing: TimingOptions,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum Status {
    Connecting,
    WaitingForAgent,
    Connected,
    Stopped,
}

#[derive(Clone, Debug, Serialize)]
pub struct Snapshot {
    pub status: Status,
    pub error: Option<String>,
}

pub struct Client {
    stop: Option<oneshot::Sender<()>>,
    state: watch::Receiver<Snapshot>,
}

impl Client {
    pub fn spawn(config: Config, roots: Option<RootCertStore>) -> Self {
        let (stop, mut cancel) = oneshot::channel();
        let (state, receiver) = watch::channel(Snapshot {
            status: Status::Connecting,
            error: None,
        });
        tokio::spawn(async move {
            let observer = state.clone();
            let worker = tokio::spawn(async move {
                let mut runtime = tokio::select! {
                    result = Engine::bind(config, roots, &observer) => match result {
                        Ok(engine) => engine,
                        Err(error) => return Some(error.to_string()),
                    },
                    _ = &mut cancel => return None,
                };
                let error = tokio::select! {
                    error = runtime.run() => Some(error),
                    _ = &mut cancel => None,
                };
                runtime.listeners.shutdown().await;
                runtime.data.shutdown().await;
                error
            });
            let error = worker
                .await
                .unwrap_or_else(|_| Some("Native engine stopped unexpectedly".into()));
            state.send_replace(Snapshot {
                status: Status::Stopped,
                error,
            });
        });
        Self {
            stop: Some(stop),
            state: receiver,
        }
    }

    pub fn stop(&mut self) {
        if let Some(stop) = self.stop.take() {
            let _ = stop.send(());
        }
    }

    pub fn snapshot(&self) -> Snapshot {
        self.state.borrow().clone()
    }
}

struct Engine<'a> {
    relay: Relay,
    protocol: Protocol,
    local: mpsc::Receiver<(usize, TcpStream)>,
    listeners: JoinSet<()>,
    data: JoinSet<Option<String>>,
    state: &'a watch::Sender<Snapshot>,
    timing: Timing,
    random: SystemRandom,
    next_id: u64,
}

#[derive(Deserialize)]
#[serde(default, deny_unknown_fields, rename_all = "camelCase")]
pub struct TimingOptions {
    pub handshake_ms: u64,
    pub heartbeat_ms: u64,
    pub pong_ms: u64,
    pub reconnect_ms: u64,
    pub max_reconnect_ms: u64,
    pub jitter_percent: u8,
}

struct Timing {
    handshake: Duration,
    heartbeat: Duration,
    pong: Duration,
    reconnect: Duration,
    max_reconnect: Duration,
    jitter: f64,
}

impl Default for TimingOptions {
    fn default() -> Self {
        Self {
            handshake_ms: 5_000,
            heartbeat_ms: 2_000,
            pong_ms: 7_000,
            reconnect_ms: 4_000,
            max_reconnect_ms: 30_000,
            jitter_percent: 10,
        }
    }
}

impl TimingOptions {
    fn validate(self) -> io::Result<Timing> {
        if !(100..=300_000).contains(&self.handshake_ms)
            || !(100..=300_000).contains(&self.heartbeat_ms)
            || !(100..=3_600_000).contains(&self.pong_ms)
            || !(100..=300_000).contains(&self.reconnect_ms)
            || !(self.reconnect_ms..=3_600_000).contains(&self.max_reconnect_ms)
            || self.jitter_percent > 100
        {
            return Err(io::Error::other("Invalid relay timing settings"));
        }
        Ok(Timing {
            handshake: Duration::from_millis(self.handshake_ms),
            heartbeat: Duration::from_millis(self.heartbeat_ms),
            pong: Duration::from_millis(self.pong_ms),
            reconnect: Duration::from_millis(self.reconnect_ms),
            max_reconnect: Duration::from_millis(self.max_reconnect_ms),
            jitter: f64::from(self.jitter_percent) / 100.0,
        })
    }
}

enum SessionError {
    Retry(&'static str),
    Fatal(&'static str),
}

impl From<io::Error> for SessionError {
    fn from(error: io::Error) -> Self {
        match error
            .get_ref()
            .and_then(|cause| cause.downcast_ref::<TlsError>())
        {
            Some(TlsError::InvalidCertificate(_)) => {
                Self::Fatal("Relay TLS certificate could not be verified")
            }
            _ => Self::Retry("Relay connection interrupted. Retrying."),
        }
    }
}

impl SessionError {
    fn protocol(error: io::Error) -> Self {
        if error.kind() == io::ErrorKind::Other {
            Self::Fatal("Native protocol operation failed")
        } else {
            Self::Retry("Relay sent an invalid protocol frame. Retrying.")
        }
    }
}

struct Pending {
    local: TcpStream,
    deadline: Instant,
}

impl<'a> Engine<'a> {
    async fn bind(
        config: Config,
        roots: Option<RootCertStore>,
        state: &'a watch::Sender<Snapshot>,
    ) -> io::Result<Self> {
        if config.relay_host.trim().is_empty()
            || config.relay_port == 0
            || config.bind_host.trim().is_empty()
            || config.route.trim().is_empty()
            || config.ports.contains(&0)
            || config
                .ports
                .iter()
                .enumerate()
                .any(|(index, port)| config.ports[..index].contains(port))
        {
            return Err(io::Error::other(
                "Invalid relay, route, or bind configuration",
            ));
        }
        let timing = config.timing.validate()?;
        let protocol = Protocol::new(&config.key, &config.route, config.ports.len())?;
        let relay = Relay::new(
            config.relay_host,
            config.relay_port,
            config
                .tls
                .then(|| roots.unwrap_or_else(crate::transport::public_roots)),
        )?;
        let mut bound = Vec::new();
        for port in config.ports {
            let listener = TcpListener::bind((config.bind_host.as_str(), port))
                .await
                .map_err(|error| {
                    io::Error::other(format!(
                        "Could not bind {}:{port} ({})",
                        config.bind_host,
                        error.kind()
                    ))
                })?;
            bound.push(listener);
        }
        let mut listeners = JoinSet::new();
        let (accepted, local) = mpsc::channel(MAX_STREAMS);
        for (index, listener) in bound.into_iter().enumerate() {
            let accepted = accepted.clone();
            listeners.spawn(async move {
                loop {
                    match listener.accept().await {
                        Ok((socket, _)) => {
                            if accepted.send((index, socket)).await.is_err() {
                                break;
                            }
                        }
                        Err(_) => sleep(Duration::from_secs(1)).await,
                    }
                }
            });
        }
        Ok(Self {
            relay,
            protocol,
            local,
            listeners,
            data: JoinSet::new(),
            state,
            timing,
            random: SystemRandom::new(),
            next_id: 0,
        })
    }

    fn publish(&self, status: Status, error: Option<String>) {
        self.state.send_replace(Snapshot { status, error });
    }

    async fn run(&mut self) -> String {
        let mut delay = self.timing.reconnect;
        loop {
            let retry = match self.session(&mut delay).await {
                Err(SessionError::Retry(error)) => error,
                Err(SessionError::Fatal(error)) => return error.into(),
                Ok(()) => unreachable!("control sessions only end on error or cancellation"),
            };
            if self.protocol.step(Operation::Disconnect, &[]).is_err() {
                return "Native protocol reset failed".into();
            }
            self.publish(Status::Connecting, Some(retry.into()));
            let mut sample = [0; 2];
            let _ = self.random.fill(&mut sample);
            let fraction = f64::from(u16::from_ne_bytes(sample)) / f64::from(u16::MAX);
            let jitter = 1.0 + self.timing.jitter * (2.0 * fraction - 1.0);
            let retry_at = Instant::now() + delay.mul_f64(jitter).min(self.timing.max_reconnect);
            loop {
                tokio::select! {
                    _ = sleep_until(retry_at) => break,
                    Some(_) = self.local.recv() => {},
                    Some(_) = self.data.join_next() => {},
                }
            }
            delay = (delay * 2).min(self.timing.max_reconnect);
        }
    }

    async fn session(&mut self, delay: &mut Duration) -> Result<(), SessionError> {
        let handshake = self.timing.handshake;
        let relay = self.relay.clone();
        let registration = self
            .protocol
            .frame(Operation::Register, None::<&()>)
            .map_err(SessionError::protocol)?;
        let establish = timeout(handshake, async {
            let mut stream = relay.connect().await?;
            send(&mut stream, &registration, handshake).await?;
            let mut wire = Frames::new(stream);
            let frame = wire.frame().await?;
            Ok::<_, io::Error>((wire, frame))
        });
        tokio::pin!(establish);
        let (mut wire, first) = loop {
            tokio::select! {
                established = &mut establish => break established.map_err(io::Error::from)??,
                Some(_) = self.local.recv() => {},
                Some(_) = self.data.join_next() => {},
            }
        };
        let mut ready = match self
            .protocol
            .step(Operation::ControlFrame, &first)
            .map_err(SessionError::protocol)?
        {
            Action::Event(Event::Registration { ready }) => ready,
            Action::Event(Event::Fatal { error }) => return Err(fatal(&error)),
            _ => {
                return Err(SessionError::Retry(
                    "Relay did not register the client. Retrying.",
                ));
            }
        };
        self.publish(presence(ready), None);
        *delay = self.timing.reconnect;
        let mut heartbeat = interval_at(
            Instant::now() + self.timing.heartbeat,
            self.timing.heartbeat,
        );
        heartbeat.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        let mut pong_deadline = None;
        let mut pending = HashMap::<String, Pending>::new();

        loop {
            let expiry = pending.values().map(|item| item.deadline).min();
            tokio::select! {
                frame = wire.frame() => {
                    match self.protocol.step(Operation::ControlFrame, &frame?).map_err(SessionError::protocol)? {
                        Action::Event(Event::Registration { ready: update }) => {
                            ready = update;
                            self.publish(presence(ready), None);
                            if !ready {
                                pending.clear();
                            }
                        }
                        Action::Event(Event::Pong) => pong_deadline = None,
                        Action::Event(Event::Fatal { error }) => return Err(fatal(&error)),
                        Action::Event(Event::OpenData { request_id, ticket }) => {
                            if let Some(item) = pending.remove(&request_id).filter(|item| item.deadline > Instant::now()) {
                                let preface = self.protocol.frame(Operation::DataPreface, Some(&ticket)).map_err(SessionError::protocol)?;
                                self.open_data(item.local, ticket, preface);
                            } else {
                                let frame = self.protocol.frame(Operation::Cancel, Some(&ticket)).map_err(SessionError::protocol)?;
                                send(wire.reader.get_mut(), &frame, handshake).await?;
                            }
                        }
                        Action::Event(Event::TunnelError { request_id }) => { pending.remove(&request_id); }
                        _ => {}
                    }
                }
                Some((index, local)) = self.local.recv() => {
                    if ready && pending.len() + self.data.len() < MAX_STREAMS {
                        self.next_id = self.next_id.wrapping_add(1);
                        let id = self.next_id.to_string();
                        let frame = self.protocol.frame(Operation::OpenTunnel, Some(&json!({"requestId": id, "portIndex": index}))).map_err(SessionError::protocol)?;
                        let deadline = Instant::now() + handshake;
                        pending.insert(id, Pending { local, deadline });
                        send(wire.reader.get_mut(), &frame, handshake).await?;
                    }
                }
                Some(result) = self.data.join_next() => {
                    if let Ok(Some(ticket)) = result {
                        let frame = self.protocol.frame(Operation::Cancel, Some(&ticket)).map_err(SessionError::protocol)?;
                        send(wire.reader.get_mut(), &frame, handshake).await?;
                    }
                }
                _ = heartbeat.tick(), if pong_deadline.is_none() => {
                    let frame = self.protocol.frame(Operation::Ping, None::<&()>).map_err(SessionError::protocol)?;
                    pong_deadline = Some(Instant::now() + self.timing.pong);
                    send(wire.reader.get_mut(), &frame, handshake.min(self.timing.pong)).await?;
                }
                _ = deadline(pong_deadline) => return Err(SessionError::Retry("Relay heartbeat timed out. Retrying.")),
                _ = deadline(expiry) => pending.retain(|_, item| item.deadline > Instant::now()),
            }
        }
    }

    fn open_data(&mut self, mut local: TcpStream, ticket: String, preface: Vec<u8>) {
        let relay = self.relay.clone();
        let handshake = self.timing.handshake;
        // Readiness only authenticates a setup frame. No payload enters the core.
        let decoder = self.protocol.clone();
        self.data.spawn(async move {
            let setup = timeout(handshake, async {
                let mut data = relay.connect().await?;
                send(&mut data, &preface, handshake).await?;
                let mut wire = Frames::new(data);
                let frame = wire.frame().await?;
                if !matches!(
                    decoder.step(Operation::DataFrame, &frame)?,
                    Action::Event(Event::StartForwarding)
                ) {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "Expected relay readiness",
                    ));
                }
                Ok(wire.reader)
            })
            .await;
            let Ok(Ok(mut data)) = setup else {
                return Some(ticket);
            };
            drop(decoder);
            let _ = copy_bidirectional(&mut local, &mut data).await;
            None
        });
    }
}

fn fatal(error: &str) -> SessionError {
    // The authenticated relay can still send arbitrary strings. Show only known errors.
    let message = match error {
        "client requests more ports than the agent provides" => {
            "The client exposes more ports than the agent"
        }
        "protocol version mismatch" => "The relay uses a different protocol version",
        _ if error.starts_with("protocol version mismatch:") => {
            "The relay uses a different protocol version"
        }
        _ => "The relay rejected the client registration",
    };
    SessionError::Fatal(message)
}

fn presence(ready: bool) -> Status {
    if ready {
        Status::Connected
    } else {
        Status::WaitingForAgent
    }
}

async fn deadline(when: Option<Instant>) {
    match when {
        Some(when) => sleep_until(when).await,
        None => std::future::pending().await,
    }
}
