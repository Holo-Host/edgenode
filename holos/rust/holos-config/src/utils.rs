use log::info;
use std::io::Write;
use std::process::{Command, Stdio};
use std::thread;

pub fn cmd_stdin(cmd: &str, args: &Vec<&str>, input: String) -> std::io::Result<()> {
    let mut child = Command::new(cmd)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()?;

    let mut stdin = child
        .stdin
        .take()
        .expect("Failed to take stdin handle for command");

    thread::spawn(move || {
        stdin
            .write_all(input.as_bytes())
            .expect("Failed to open pipe");
    });

    // retrieve stdout in case it's needed
    let output = child
        .wait_with_output()
        .expect("Failed to collect command output");

    info!(
        "Command output was: {}",
        String::from_utf8_lossy(&output.stdout)
    );
    Ok(())
}
