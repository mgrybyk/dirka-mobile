use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    let manifest = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let upstream = manifest.join("../.upstream/node-tunnel");
    let revision_file = manifest.join("upstream.rev");
    let revision = std::fs::read_to_string(&revision_file).unwrap();
    let checkout = Command::new("git")
        .current_dir(&upstream)
        .args(["rev-parse", "HEAD"])
        .output()
        .ok()
        .filter(|output| output.status.success());
    assert!(
        checkout
            .as_ref()
            .is_some_and(|output| output.stdout == revision.as_bytes()),
        "Run tool/fetch-upstream.sh to check out the pinned node-tunnel source"
    );
    assert!(
        Command::new("git")
            .current_dir(&upstream)
            .args(["diff", "--quiet", "HEAD", "--"])
            .status()
            .unwrap()
            .success(),
        "The pinned node-tunnel checkout contains tracked edits"
    );

    let rust = upstream.join("rust");
    // Upstream currently exposes the protocol version in Rust source only.
    let wire = std::fs::read_to_string(rust.join("src/wire.rs")).unwrap();
    let protocol = wire
        .lines()
        .find_map(|line| line.trim().strip_prefix("pub const PROTOCOL_VERSION: u8 ="))
        .and_then(|value| value.trim().strip_suffix(';'))
        .and_then(|value| value.parse::<u8>().ok())
        .expect("read PROTOCOL_VERSION from the pinned node-tunnel Rust source");
    let license = upstream.join("LICENSE").canonicalize().unwrap();
    println!("cargo:rerun-if-changed={}", license.display());
    println!(
        "cargo:rustc-env=DIRKA_UPSTREAM_LICENSE={}",
        license.display()
    );
    println!("cargo:rustc-env=DIRKA_UPSTREAM_PROTOCOL={protocol}");
    println!(
        "cargo:rustc-env=DIRKA_UPSTREAM_REVISION={}",
        revision.trim()
    );
    println!("cargo:rerun-if-changed={}", revision_file.display());
    println!(
        "cargo:rerun-if-changed={}",
        upstream.join(".git/HEAD").display()
    );
    for path in ["src", "Cargo.toml", "Cargo.lock", "include"] {
        println!("cargo:rerun-if-changed={}", rust.join(path).display());
    }
    let target = env::var("TARGET").unwrap();
    println!("cargo:rerun-if-env-changed=DIRKA_UPSTREAM_TARGET_DIR");
    let output = env::var_os("DIRKA_UPSTREAM_TARGET_DIR").map_or_else(
        || PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("upstream"),
        PathBuf::from,
    );
    let library_directory = output.join(&target).join("release");
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap();
    let link_arg = if target_os == "macos" {
        format!(
            "-Wl,-install_name,{}",
            library_directory
                .join("libnode_tunnel_client.dylib")
                .display()
        )
    } else {
        "-Wl,-soname,libnode_tunnel_client.so".into()
    };
    let status = Command::new(env::var_os("CARGO").unwrap())
        .args([
            "rustc",
            "--lib",
            "--release",
            "--locked",
            "--target",
            &target,
        ])
        .arg("--target-dir")
        .arg(&output)
        .args(["--", "-C", &format!("link-arg={link_arg}")])
        .current_dir(&rust)
        .status()
        .expect("start the upstream Cargo build");
    assert!(status.success(), "pinned upstream Cargo build failed");

    println!(
        "cargo:rustc-link-search=native={}",
        library_directory.display()
    );
    println!("cargo:rustc-link-lib=dylib=node_tunnel_client");
    if target_os == "android" {
        println!("cargo:rustc-link-arg-cdylib=-Wl,-soname,libdirka_engine.so");
    }
    if target_os == "linux" {
        println!(
            "cargo:rustc-link-arg=-Wl,-rpath,{}",
            library_directory.display()
        );
    }
}
