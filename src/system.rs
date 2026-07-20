use std::{env, path::PathBuf, process::Command};

pub fn home_dir() -> PathBuf {
    #[cfg(windows)]
    let home = env::var("USERPROFILE").or_else(|_| env::var("HOME"));
    #[cfg(not(windows))]
    let home = env::var("HOME");

    home.map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("."))
}

pub fn hostname() -> String {
    Command::new("hostname")
        .output()
        .ok()
        .and_then(|output| String::from_utf8(output.stdout).ok())
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_default()
}
