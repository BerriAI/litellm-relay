use std::{
    env, fs,
    io::{self, Write},
};

use anyhow::{anyhow, Result};

use crate::{auth::GatewaySsoClient, config::relay_home};

pub async fn run_setup(gateway_url: Option<String>, api_key: Option<String>) -> Result<()> {
    let default_gateway_url =
        env::var("LITELLM_GATEWAY_URL").unwrap_or_else(|_| "http://127.0.0.1:4000".into());
    let gateway_url =
        gateway_url.unwrap_or_else(|| prompt("LiteLLM Gateway URL", &default_gateway_url));

    println!();
    println!("LiteLLM Relay needs to authenticate to your Gateway.");
    println!("Press Enter to use browser SSO, or type 'key' to paste an API key.");

    let (api_key, user_id, team_id) = match api_key {
        Some(api_key) => (api_key, None, None),
        None if prompt_auth_method() == AuthMethod::Sso => {
            let auth = GatewaySsoClient::new().login(&gateway_url).await?;
            (auth.api_key, auth.user_id, auth.team_id)
        }
        None => (prompt("Paste Relay Gateway key", ""), None, None),
    };

    if api_key.trim().is_empty() {
        return Err(anyhow!("setup requires a LiteLLM Gateway API key"));
    }

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
    println!("Wrote {}", env_path.display());
    if let Some(user_id) = user_id {
        println!("Authenticated Gateway user: {user_id}");
    }
    if let Some(team_id) = team_id {
        println!("Gateway team: {team_id}");
    }
    Ok(())
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum AuthMethod {
    Sso,
    ApiKey,
}

fn prompt_auth_method() -> AuthMethod {
    loop {
        let value = prompt("Authentication method", "sso");
        match value.trim().to_ascii_lowercase().as_str() {
            "" | "sso" | "browser" | "login" => return AuthMethod::Sso,
            "key" | "api-key" | "apikey" | "manual" => return AuthMethod::ApiKey,
            _ => println!("Use 'sso' or 'key'."),
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
