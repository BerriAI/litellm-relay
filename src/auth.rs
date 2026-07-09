use std::{
    io::{self, Write},
    process::Command,
    time::Duration,
};

use anyhow::{anyhow, Context, Result};
use reqwest::StatusCode;
use serde::Deserialize;
use serde_json::Value;
use tokio::time::sleep;
use url::Url;

const CLI_SOURCE: &str = "litellm-cli";
const POLL_TIMEOUT: Duration = Duration::from_secs(300);
const POLL_INTERVAL: Duration = Duration::from_secs(2);

#[derive(Debug)]
pub struct GatewayAuth {
    pub api_key: String,
    pub user_id: Option<String>,
    pub team_id: Option<String>,
}

pub struct GatewaySsoClient {
    http_client: reqwest::Client,
}

impl GatewaySsoClient {
    pub fn new() -> Self {
        let http_client = reqwest::Client::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .expect("reqwest client configuration should be valid");
        Self { http_client }
    }

    pub async fn login(&self, gateway_url: &str) -> Result<GatewayAuth> {
        let gateway_url = normalize_gateway_url(gateway_url)?;
        let key_id = format!("sk-{}", uuid::Uuid::new_v4());
        let sso_url = build_sso_url(&gateway_url, &key_id)?;

        println!();
        println!("Opening LiteLLM Gateway SSO in your browser.");
        println!("{sso_url}");
        println!();
        println!("Complete the sign-in in your browser. Relay will keep waiting here.");

        open_browser(sso_url.as_str());

        let poll_result = self.poll_until_ready(&gateway_url, &key_id, None).await?;
        if poll_result.requires_team_selection.unwrap_or(false) {
            let teams = normalize_teams(&poll_result);
            if teams.is_empty() {
                return Err(anyhow!(
                    "Gateway requires team selection but did not return any teams"
                ));
            }
            let team_id = prompt_team_selection(&teams)?;
            let team_result = self
                .poll_until_ready(&gateway_url, &key_id, Some(&team_id))
                .await?;
            return auth_from_poll_result(team_result);
        }

        auth_from_poll_result(poll_result)
    }

    async fn poll_until_ready(
        &self,
        gateway_url: &str,
        key_id: &str,
        team_id: Option<&str>,
    ) -> Result<PollResponse> {
        let poll_url = build_poll_url(gateway_url, key_id, team_id)?;
        let attempts = POLL_TIMEOUT.as_secs() / POLL_INTERVAL.as_secs();
        for attempt in 0..attempts {
            match self.http_client.get(poll_url.clone()).send().await {
                Ok(response) if response.status() == StatusCode::OK => {
                    let poll_response = response
                        .json::<PollResponse>()
                        .await
                        .context("Gateway returned an invalid SSO poll response")?;
                    if poll_response.status.as_deref() == Some("ready") {
                        return Ok(poll_response);
                    }
                }
                Ok(response) if attempt % 10 == 0 => {
                    println!(
                        "Waiting for Gateway authorization... HTTP {}",
                        response.status()
                    );
                }
                Err(error) if attempt % 10 == 0 => {
                    println!("Waiting for Gateway authorization... {error}");
                }
                _ => {}
            }

            if attempt % 10 == 0 {
                println!("Waiting for Gateway authorization...");
            }
            sleep(POLL_INTERVAL).await;
        }

        Err(anyhow!(
            "Gateway SSO timed out after {} seconds",
            POLL_TIMEOUT.as_secs()
        ))
    }
}

#[derive(Debug, Deserialize)]
struct PollResponse {
    status: Option<String>,
    key: Option<String>,
    user_id: Option<String>,
    team_id: Option<String>,
    teams: Option<Vec<Value>>,
    team_details: Option<Vec<TeamDetail>>,
    requires_team_selection: Option<bool>,
}

#[derive(Clone, Debug, Deserialize)]
struct TeamDetail {
    team_id: Option<String>,
    id: Option<String>,
    team_alias: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct TeamOption {
    id: String,
    alias: Option<String>,
}

fn auth_from_poll_result(poll_response: PollResponse) -> Result<GatewayAuth> {
    let api_key = poll_response
        .key
        .filter(|key| !key.trim().is_empty())
        .ok_or_else(|| anyhow!("Gateway SSO completed but did not return an API key"))?;

    Ok(GatewayAuth {
        api_key,
        user_id: poll_response.user_id,
        team_id: poll_response.team_id,
    })
}

fn normalize_gateway_url(gateway_url: &str) -> Result<String> {
    let mut gateway_url = gateway_url.trim().trim_end_matches('/').to_string();
    if gateway_url.is_empty() {
        return Err(anyhow!("LiteLLM Gateway URL is required"));
    }
    if !gateway_url.starts_with("http://") && !gateway_url.starts_with("https://") {
        gateway_url = format!("https://{gateway_url}");
    }
    Url::parse(&gateway_url).with_context(|| format!("invalid Gateway URL: {gateway_url}"))?;
    Ok(gateway_url)
}

fn build_sso_url(gateway_url: &str, key_id: &str) -> Result<Url> {
    let mut url = Url::parse(&format!(
        "{}/sso/key/generate",
        gateway_url.trim_end_matches('/')
    ))?;
    url.query_pairs_mut()
        .append_pair("source", CLI_SOURCE)
        .append_pair("key", key_id);
    Ok(url)
}

fn build_poll_url(gateway_url: &str, key_id: &str, team_id: Option<&str>) -> Result<Url> {
    let mut url = Url::parse(&format!(
        "{}/sso/cli/poll/{}",
        gateway_url.trim_end_matches('/'),
        key_id
    ))?;
    if let Some(team_id) = team_id {
        url.query_pairs_mut().append_pair("team_id", team_id);
    }
    Ok(url)
}

fn normalize_teams(poll_response: &PollResponse) -> Vec<TeamOption> {
    if let Some(team_details) = &poll_response.team_details {
        let teams: Vec<TeamOption> = team_details
            .iter()
            .filter_map(|team| {
                let id = team.team_id.as_ref().or(team.id.as_ref())?;
                Some(TeamOption {
                    id: id.to_string(),
                    alias: team.team_alias.clone(),
                })
            })
            .collect();
        if !teams.is_empty() {
            return teams;
        }
    }

    poll_response
        .teams
        .as_deref()
        .unwrap_or_default()
        .iter()
        .filter_map(|team| team.as_str())
        .map(|id| TeamOption {
            id: id.to_string(),
            alias: None,
        })
        .collect()
}

fn prompt_team_selection(teams: &[TeamOption]) -> Result<String> {
    println!();
    println!("Select the Gateway team Relay should use:");
    for (index, team) in teams.iter().enumerate() {
        let label = team.alias.as_deref().unwrap_or(&team.id);
        println!("  {}. {} ({})", index + 1, label, team.id);
    }

    loop {
        print!("Team [1]: ");
        let _ = io::stdout().flush();
        let mut line = String::new();
        io::stdin().read_line(&mut line)?;
        let choice = line.trim();
        if choice.is_empty() {
            return Ok(teams[0].id.clone());
        }
        let Ok(index) = choice.parse::<usize>() else {
            println!("Enter a team number.");
            continue;
        };
        if let Some(team) = teams.get(index.saturating_sub(1)) {
            return Ok(team.id.clone());
        }
        println!("Enter a number from 1 to {}.", teams.len());
    }
}

fn open_browser(url: &str) {
    let status = if cfg!(target_os = "macos") {
        Command::new("open").arg(url).status()
    } else if cfg!(target_os = "windows") {
        Command::new("cmd").args(["/C", "start", url]).status()
    } else {
        Command::new("xdg-open").arg(url).status()
    };

    if status.is_err() {
        println!("Could not open a browser automatically. Open the URL above.");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn should_build_gateway_sso_url() {
        let url = build_sso_url("https://gateway.example.com/", "sk-test").unwrap();
        assert_eq!(
            url.as_str(),
            "https://gateway.example.com/sso/key/generate?source=litellm-cli&key=sk-test"
        );
    }

    #[test]
    fn should_build_team_poll_url_with_encoding() {
        let url =
            build_poll_url("https://gateway.example.com", "sk-test", Some("team one")).unwrap();
        assert_eq!(
            url.as_str(),
            "https://gateway.example.com/sso/cli/poll/sk-test?team_id=team+one"
        );
    }

    #[test]
    fn should_normalize_gateway_url() {
        assert_eq!(
            normalize_gateway_url("gateway.example.com/").unwrap(),
            "https://gateway.example.com"
        );
    }
}
