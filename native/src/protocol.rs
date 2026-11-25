use std::{
    ffi::c_void,
    io,
    ptr::NonNull,
    sync::{Arc, Mutex},
};

use ring::rand::{SecureRandom, SystemRandom};
use serde::{Deserialize, Serialize};

unsafe extern "C" {
    fn nt_client_buffer_capacity() -> usize;
    pub fn nt_client_max_frame_bytes() -> usize;
    fn nt_client_create(
        key: *const u8,
        key_length: usize,
        name: *const u8,
        name_length: usize,
        port_count: u32,
        out_client: *mut *mut c_void,
    ) -> i32;
    fn nt_client_step(
        client: *mut c_void,
        operation: u32,
        input: *const u8,
        input_length: usize,
        output: *mut u8,
        output_capacity: usize,
    ) -> i32;
    fn nt_client_destroy(client: *mut c_void) -> i32;
}

#[derive(Clone, Copy)]
pub enum Operation {
    Register = 1,
    Disconnect = 2,
    ControlFrame = 3,
    OpenTunnel = 4,
    Ping = 5,
    DataPreface = 6,
    DataFrame = 7,
    Cancel = 8,
}

#[derive(Deserialize)]
#[serde(
    tag = "type",
    rename_all = "kebab-case",
    rename_all_fields = "camelCase"
)]
pub enum Event {
    Registration { ready: bool },
    Pong,
    Fatal { error: String },
    OpenData { request_id: String, ticket: String },
    TunnelError { request_id: String },
    StartForwarding,
}

pub enum Action {
    None,
    Frame(Vec<u8>),
    Event(Event),
}

#[derive(Clone)]
pub struct Protocol(Arc<Mutex<Core>>);

struct Core {
    handle: NonNull<c_void>,
    output: Vec<u8>,
}

// The opaque upstream handle contains a mutex and can move across threads. Every
// call and destruction here require exclusive ownership of this wrapper.
unsafe impl Send for Core {}

impl Protocol {
    pub fn new(key: &str, route: &str, ports: usize) -> io::Result<Self> {
        let mut handle = std::ptr::null_mut();
        let result = unsafe {
            nt_client_create(
                key.as_ptr(),
                key.len(),
                route.as_ptr(),
                route.len(),
                ports as u32,
                &mut handle,
            )
        };
        if result != 0 {
            return Err(io::Error::other(
                "Upstream rejected the client configuration",
            ));
        }
        Ok(Self(Arc::new(Mutex::new(Core {
            handle: NonNull::new(handle)
                .ok_or_else(|| io::Error::other("Missing protocol handle"))?,
            output: vec![0; unsafe { nt_client_buffer_capacity() }],
        }))))
    }

    pub fn frame(
        &self,
        operation: Operation,
        body: Option<&impl Serialize>,
    ) -> io::Result<Vec<u8>> {
        let mut nonce = [0; 12];
        SystemRandom::new()
            .fill(&mut nonce)
            .map_err(|_| io::Error::other("Secure randomness unavailable"))?;
        let action = match body {
            Some(body) => {
                let mut input = nonce.to_vec();
                serde_json::to_writer(&mut input, body)?;
                self.step(operation, &input)?
            }
            None => self.step(operation, &nonce)?,
        };
        match action {
            Action::Frame(frame) => Ok(frame),
            _ => Err(io::Error::other("Expected an upstream send action")),
        }
    }

    pub fn step(&self, operation: Operation, input: &[u8]) -> io::Result<Action> {
        self.0
            .lock()
            .map_err(|_| io::Error::other("Native protocol lock poisoned"))?
            .step(operation, input)
    }
}

impl Core {
    fn step(&mut self, operation: Operation, input: &[u8]) -> io::Result<Action> {
        let result = unsafe {
            nt_client_step(
                self.handle.as_ptr(),
                operation as u32,
                input.as_ptr(),
                input.len(),
                self.output.as_mut_ptr(),
                self.output.len(),
            )
        };
        if result == 0 {
            return Ok(Action::None);
        }
        let bytes = usize::try_from(result)
            .ok()
            .and_then(|len| self.output.get(..len));
        match bytes.and_then(|bytes| bytes.split_first()) {
            Some((1, frame)) => Ok(Action::Frame(frame.to_vec())),
            Some((2, event)) => Ok(Action::Event(serde_json::from_slice(event)?)),
            _ if result == -3 => Err(io::Error::other(
                "Upstream protocol engine stopped unexpectedly",
            )),
            _ => Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "Upstream rejected the protocol operation",
            )),
        }
    }
}

impl Drop for Core {
    fn drop(&mut self) {
        unsafe { nt_client_destroy(self.handle.as_ptr()) };
    }
}
