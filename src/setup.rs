use std::{
    env, fs,
    io::{self, Write},
};

use anyhow::{anyhow, Result};

use crate::{
    auth::GatewaySsoClient,
    config::relay_home,
    terminal::{print_setup_complete, print_setup_intro, print_step},
};

pub async fn run_setup(gateway_url: Option<String>, api_key: Option<String>) -> Result<()> {
    print_setup_intro();

    let default_gateway_url =
        env::var("LITELLM_GATEWAY_URL").unwrap_or_else(|_| "http://127.0.0.1:4000".into());
    print_step(1, 3, "Choose your LiteLLM Gateway");
    let gateway_url = match gateway_url {
        Some(gateway_url) => {
            println!("  Gateway URL: {}", gateway_url.trim_end_matches('/'));
            gateway_url
        }
        None => prompt("Gateway URL", &default_gateway_url),
    };

    println!();
    print_step(2, 3, "Sign in");
    let (api_key, user_id, team_id) = match api_key {
        Some(api_key) => {
            println!("  Using API key from command line or environment.");
            (api_key, None, None)
        }
        None if prompt_browser_sso() => {
            let auth = GatewaySsoClient::new().login(&gateway_url).await?;
            (auth.api_key, auth.user_id, auth.team_id)
        }
        None => (prompt("Gateway API key", ""), None, None),
    };

    if api_key.trim().is_empty() {
        return Err(anyhow!("setup requires a LiteLLM Gateway API key"));
    }

    println!();
    print_step(3, 3, "Save local Relay config");
    let relay_home = relay_home();
    fs::create_dir_all(&relay_home)?;
    let env_path = relay_home.join("env");
    let contents = format!(
        "LITELLM_RELAY_HOST=127.0.0.1\n\
         LITELLM_RELAY_PORT={}\n\
         LITELLM_RELAY_LOG_PATH={}/relay.log.jsonl\n\
         LITELLM_GATEWAY_URL={}\n\
         LITELLM_GATEWAY_API_KEY={}\n\
         LITELLM_RELAY_SHADOW_ENABLED={}\n\
         LITELLM_RELAY_SHADOW_MODEL={}\n\
         LITELLM_RELAY_CAPTURE_PAYLOADS={}\n\
         LITELLM_RELAY_MITM_CA_DIR={}/mitm\n",
        env::var("LITELLM_RELAY_PORT").unwrap_or_else(|_| "4142".into()),
        relay_home.display(),
        gateway_url.trim_end_matches('/'),
        api_key.trim(),
        env::var("LITELLM_RELAY_SHADOW_ENABLED").unwrap_or_else(|_| "0".into()),
        env::var("LITELLM_RELAY_SHADOW_MODEL").unwrap_or_else(|_| "gpt-4o-mini".into()),
        env::var("LITELLM_RELAY_CAPTURE_PAYLOADS").unwrap_or_else(|_| "1".into()),
        relay_home.display()
    );
    fs::write(&env_path, contents)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&env_path, fs::Permissions::from_mode(0o600))?;
    }
    print_setup_complete(&env_path, user_id.as_deref(), team_id.as_deref());
    Ok(())
}

fn prompt_browser_sso() -> bool {
    loop {
        let value = prompt("Use browser SSO", "Y");
        match value.trim().to_ascii_lowercase().as_str() {
            "" | "y" | "yes" => return true,
            "n" | "no" => return false,
            _ => println!("Enter 'Y' for browser SSO or 'n' to paste an API key."),
        }
    }
}

fn prompt(label: &str, default: &str) -> String {
    if default.is_empty() {
        print!("{label}: ");
    } else {
        print!("{label} [{default}]: ");
    }
    let _ = io::stdout().flush();
    let mut line = String::new();
    let _ = io::stdin().read_line(&mut line);
    let value = line.trim();
    if value.is_empty() {
        default.to_string()
    } else {
        value.to_string()
    }
}
