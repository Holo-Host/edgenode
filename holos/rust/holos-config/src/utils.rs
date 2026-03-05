use log::info;
use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::{Command, Stdio};
use std::thread;
use tempfile::NamedTempFile;

/// Atomically writes content to a file with specific permissions.
///
/// This function uses a tempfile + rename pattern for atomicity. The content is first
/// written to a temporary file in the same directory as the target, and then renamed
/// to the target path. This ensures that the target file is never in a partial state.
///
/// # Arguments
/// * `path` - The target path for the file
/// * `content` - The content to write
/// * `mode` - Unix permissions mode (e.g., 0o600)
///
/// # Returns
/// * `Ok(())` on success
/// * `Err` on failure (IO error, permission error, etc.)
pub fn atomic_write_with_permissions(
    path: &Path,
    content: &[u8],
    mode: u32,
) -> std::io::Result<()> {
    // Get the parent directory for the temp file (must be on same filesystem for atomic rename)
    let parent = path.parent().unwrap_or(Path::new("."));

    // Ensure parent directory exists
    fs::create_dir_all(parent)?;

    // Create temp file in the same directory as target
    let mut temp_file = NamedTempFile::new_in(parent)?;

    // Write content to temp file
    temp_file.write_all(content)?;

    // Set permissions on temp file before moving
    let metadata = temp_file.as_file().metadata()?;
    let mut permissions = metadata.permissions();
    permissions.set_mode(mode);
    temp_file.as_file().set_permissions(permissions)?;

    // Atomically rename temp file to target path
    temp_file.persist(path)?;

    Ok(())
}

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
