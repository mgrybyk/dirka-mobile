use std::{
    ffi::c_char,
    panic::{AssertUnwindSafe, catch_unwind},
    ptr, slice,
    sync::OnceLock,
};

use tokio::runtime::{Builder, Runtime};

use crate::engine::{Client, Config, Snapshot};

static RUNTIME: OnceLock<Option<Runtime>> = OnceLock::new();
const MAX_CONFIG_BYTES: usize = 4096;

#[unsafe(no_mangle)]
extern "C" fn dirka_engine_metadata() -> *const c_char {
    concat!(
        "{\"engineVersion\":\"",
        env!("CARGO_PKG_VERSION"),
        "\",\"upstreamRevision\":\"",
        env!("DIRKA_UPSTREAM_REVISION"),
        "\",\"protocolVersion\":",
        env!("DIRKA_UPSTREAM_PROTOCOL"),
        "}\0"
    )
    .as_ptr()
    .cast()
}

#[unsafe(no_mangle)]
extern "C" fn dirka_engine_upstream_license() -> *const c_char {
    concat!(include_str!(env!("DIRKA_UPSTREAM_LICENSE")), "\0")
        .as_ptr()
        .cast()
}

#[unsafe(no_mangle)]
extern "C" fn dirka_engine_dependency_licenses() -> *const c_char {
    concat!(include_str!("../third_party_licenses.json"), "\0")
        .as_ptr()
        .cast()
}

#[unsafe(no_mangle)]
unsafe extern "C" fn dirka_client_start(input: *const u8, length: usize) -> *mut Client {
    catch_unwind(|| {
        if input.is_null() || length == 0 || length > MAX_CONFIG_BYTES {
            return ptr::null_mut();
        }
        let input = unsafe { slice::from_raw_parts(input, length) };
        let Ok(config) = serde_json::from_slice::<Config>(input) else {
            return ptr::null_mut();
        };
        let Some(runtime) = RUNTIME.get_or_init(|| {
            Builder::new_multi_thread()
                .worker_threads(2)
                .enable_all()
                .build()
                .ok()
        }) else {
            return ptr::null_mut();
        };
        let _entered = runtime.enter();
        Box::into_raw(Box::new(Client::spawn(config, None)))
    })
    .unwrap_or(ptr::null_mut())
}

#[unsafe(no_mangle)]
unsafe extern "C" fn dirka_client_snapshot(
    client: *const Client,
    output: *mut u8,
    capacity: usize,
) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        let Some(client) = (unsafe { client.as_ref() }) else {
            return -1;
        };
        unsafe { write_snapshot(&client.snapshot(), output, capacity) }
    }))
    .unwrap_or(-1)
}

#[unsafe(no_mangle)]
unsafe extern "C" fn dirka_client_poll_snapshot(
    client: *mut Client,
    output: *mut u8,
    capacity: usize,
) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        let Some(client) = (unsafe { client.as_mut() }) else {
            return -1;
        };
        let Some(snapshot) = client.updated_snapshot() else {
            return 0;
        };
        unsafe { write_snapshot(&snapshot, output, capacity) }
    }))
    .unwrap_or(-1)
}

unsafe fn write_snapshot(snapshot: &Snapshot, output: *mut u8, capacity: usize) -> i32 {
    let Ok(json) = serde_json::to_vec(snapshot) else {
        return -1;
    };
    if output.is_null() || capacity < json.len() {
        return -1;
    }
    unsafe { ptr::copy_nonoverlapping(json.as_ptr(), output, json.len()) };
    json.len() as i32
}

#[unsafe(no_mangle)]
unsafe extern "C" fn dirka_client_stop(client: *mut Client) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if let Some(client) = unsafe { client.as_mut() } {
            client.stop();
        }
    }));
}

#[unsafe(no_mangle)]
unsafe extern "C" fn dirka_client_network_available(client: *const Client) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if let Some(client) = unsafe { client.as_ref() } {
            client.network_available();
        }
    }));
}

#[unsafe(no_mangle)]
unsafe extern "C" fn dirka_client_destroy(client: *mut Client) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if !client.is_null() {
            // Dropping the cancellation sender also requests shutdown.
            drop(unsafe { Box::from_raw(client) });
        }
    }));
}
