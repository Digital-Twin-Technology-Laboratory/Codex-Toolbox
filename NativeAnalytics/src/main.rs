//! Fixed read-only commands. No generic HTTP proxy, prompts, tools or credit redemption.
use codex_config::ManagedAuthPolicy;
use codex_backend_client::{Client, TaskUsageThread, TaskUsageStatus};
use codex_http_client::{HttpClientFactory, OutboundProxyPolicy};
use codex_login::{
    AuthCredentialsStoreMode, AuthKeyringBackendKind, AuthManager, AuthManagerConfig,
    AuthRouteConfig,
};
use codex_protocol::config_types::ForcedLoginMethod;
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    io::{self, Read},
    path::PathBuf,
};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Input {
    command: Command,
    salt: String,
    #[serde(default)]
    threads: Vec<ThreadInput>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct ThreadInput {
    id: String,
    created_at: Option<String>,
    descendant_ids: Vec<String>,
}
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
enum Command { Identity, TaskUsage }
struct Config {
    home: PathBuf,
    store: AuthCredentialsStoreMode,
    keyring: AuthKeyringBackendKind,
    forced: Option<ForcedLoginMethod>,
    workspace: Option<Vec<String>>,
    external_provider: bool,
}
impl Config {
    fn load() -> Result<Self, &'static str> {
        let home = std::env::var_os("CODEX_HOME")
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|p| PathBuf::from(p).join(".codex")))
            .ok_or("signInRequired")?;
        let raw = std::fs::read_to_string(home.join("config.toml")).unwrap_or_default();
        let config: toml::Value = if raw.is_empty() {
            toml::Value::Table(Default::default())
        } else {
            toml::from_str(&raw).map_err(|_| "unsupportedConfiguration")?
        };
        let read = |key: &str| config.get(key).cloned();
        let store = setting(read("cli_auth_credentials_store"))?.unwrap_or_default();
        let keyring = setting(read("auth_keyring_backend"))?.unwrap_or_default();
        let forced = setting(read("forced_login_method"))?;
        let workspace = match read("forced_chatgpt_workspace_id") {
            Some(toml::Value::String(s)) => Some(vec![s]),
            other => setting(other)?,
        };
        let profile = config.get("profile").and_then(|v| v.as_str())
            .and_then(|name| config.get("profiles").and_then(|v| v.get(name)));
        let provider = profile.and_then(|v| v.get("model_provider"))
            .or_else(|| config.get("model_provider")).and_then(|v| v.as_str()).unwrap_or("openai");
        let external_provider = provider != "openai" && !config.get("model_providers")
            .and_then(|v| v.get(provider)).and_then(|v| v.get("requires_openai_auth"))
            .and_then(|v| v.as_bool()).unwrap_or(false);
        Ok(Self {
            external_provider,
            home,
            store,
            keyring,
            forced,
            workspace,
        })
    }
}
fn setting<T: serde::de::DeserializeOwned>(
    value: Option<toml::Value>,
) -> Result<Option<T>, &'static str> {
    value
        .map(|value| value.try_into().map_err(|_| "unsupportedConfiguration"))
        .transpose()
}
impl AuthManagerConfig for Config {
    fn codex_home(&self) -> PathBuf {
        self.home.clone()
    }
    fn cli_auth_credentials_store_mode(&self) -> AuthCredentialsStoreMode {
        self.store
    }
    fn auth_keyring_backend_kind(&self) -> AuthKeyringBackendKind {
        self.keyring
    }
    fn forced_login_method(&self) -> Option<ForcedLoginMethod> {
        self.forced
    }
    fn forced_chatgpt_workspace_id(&self) -> Option<Vec<String>> {
        self.workspace.clone()
    }
    fn managed_auth_policy(&self) -> ManagedAuthPolicy {
        ManagedAuthPolicy::default()
    }
    fn chatgpt_base_url(&self) -> String {
        "https://chatgpt.com/backend-api".into()
    }
    fn auth_route_config(&self) -> AuthRouteConfig {
        AuthRouteConfig::from_http_client_factory(factory())
    }
}
fn factory() -> HttpClientFactory {
    HttpClientFactory::new(OutboundProxyPolicy::RespectSystemProxy)
}
fn error(code: &str) -> Value {
    json!({"schemaVersion":1,"error":code})
}
async fn identity(config: &Config, salt: &str) -> Result<Value, &'static str> {
    if config.external_provider { return Ok(auth_response("api", None)); }
    let manager = AuthManager::shared_from_config(config, false)
        .await.map_err(|_| "unsupportedConfiguration")?;
    manager.reload().await;
    let Some(auth) = manager.auth().await else { return Ok(auth_response("signedOut", None)); };
    if !auth.is_chatgpt_auth() { return Ok(auth_response("api", None)); }
    let (Some(account), Some(user)) = (auth.get_account_id(), auth.get_chatgpt_user_id()) else {
        return Ok(auth_response("unknown", None));
    };
    let key = account_fingerprint(salt, &account, &user);
    Ok(auth_response("chatGPT", Some(&key)))
}
fn account_fingerprint(salt: &str, account: &str, user: &str) -> String {
    let mut digest = Sha256::new();
    for part in [salt, account, user] { digest.update(part.as_bytes()); digest.update([0]); }
    format!("{:x}", digest.finalize())
}
fn auth_response(mode: &str, key: Option<&str>) -> Value {
    json!({"schemaVersion":2,"authMode":mode,"accountKey":key})
}
fn validate(input: &Input) -> bool {
    if input.salt.len() != 64 || !input.salt.bytes().all(|c| c.is_ascii_hexdigit()) { return false; }
    if matches!(input.command, Command::Identity) { return input.threads.is_empty(); }
    let mut ids = std::collections::HashSet::new();
    !input.threads.is_empty() && input.threads.len() <= 100 && input.threads.iter().all(|t| {
        (t.created_at.as_ref().is_none_or(|v| v.len() <= 64 && chrono::DateTime::parse_from_rfc3339(v).is_ok()))
        && std::iter::once(&t.id).chain(&t.descendant_ids).all(|id| {
            id.len() == 36 && id.bytes().enumerate().all(|(i, c)| {
                if [8,13,18,23].contains(&i) { c == b'-' } else { c.is_ascii_hexdigit() }
            }) && ids.insert(id)
        })
    }) && ids.len() <= 1000
}
async fn task_usage(config: &Config, input: &Input) -> Result<Value, &'static str> {
    let before = identity(config, &input.salt).await?;
    if before["authMode"] != "chatGPT" { return Err("accountUnavailable"); }
    let manager = AuthManager::shared_from_config(config, false).await.map_err(|_| "accountUnavailable")?;
    manager.reload().await;
    let auth = manager.auth().await.ok_or("accountUnavailable")?;
    if !auth.is_chatgpt_auth() { return Err("accountChanged"); }
    let account = auth.get_account_id().ok_or("accountUnavailable")?;
    let user = auth.get_chatgpt_user_id().ok_or("accountUnavailable")?;
    if before["accountKey"] != account_fingerprint(&input.salt, &account, &user) { return Err("accountChanged"); }
    let client = Client::from_auth(config.chatgpt_base_url(), &auth, factory())
        .with_chatgpt_account_id(account);
    let client = if auth.is_fedramp_account() { client.with_fedramp_routing_header() } else { client };
    let threads: Vec<_> = input.threads.iter().map(|t| TaskUsageThread {
        thread_id: t.id.clone(), created_at: t.created_at.clone(), descendant_thread_ids: t.descendant_ids.clone(),
    }).collect();
    let response = tokio::time::timeout(std::time::Duration::from_secs(30), client.get_task_usage(&threads))
        .await.map_err(|_| "timeout")?.map_err(|_| "accountUnavailable")?;
    let after = identity(&Config::load()?, &input.salt).await?;
    if before != after { return Err("accountChanged"); }
    let rows: Vec<_> = response.threads.into_iter().map(|row| json!({
        "id": row.thread_id,
        "status": match row.data_status { TaskUsageStatus::Available => "available", TaskUsageStatus::Partial => "partial", TaskUsageStatus::Unavailable => "unavailable" },
        "usageSource": row.usage_source,
        "fiveHourPercent": row.amounts.five_hour_limit_percent,
        "weeklyPercent": row.amounts.weekly_limit_percent,
        "groups": row.groups.into_iter().map(|g| json!({
            "product": g.product_experience, "model": g.model, "effort": g.reasoning_effort, "speed": g.speed,
            "fiveHourPercent": g.amounts.five_hour_limit_percent, "weeklyPercent": g.amounts.weekly_limit_percent,
        })).collect::<Vec<_>>(),
    })).collect();
    Ok(json!({"schemaVersion":3,"accountKey":before["accountKey"],
        "planType":auth.account_plan_type().map(|p| format!("{p:?}")),
        "collectedAt":chrono::Utc::now().to_rfc3339(),"dataAsOf":response.data_as_of,"threads":rows}))
}
async fn run(input: Input) -> Result<Value, &'static str> {
    if !validate(&input) { return Err("invalidRequest"); }
    let config = Config::load()?;
    match input.command { Command::Identity => identity(&config, &input.salt).await, Command::TaskUsage => task_usage(&config, &input).await }
}
#[tokio::main]
async fn main() {
    let mut bytes = Vec::new();
    let result = if io::stdin().take(131073).read_to_end(&mut bytes).is_err() || bytes.len() > 131072 {
        Err("invalidRequest")
    } else {
        match serde_json::from_slice::<Input>(&bytes) {
            Ok(input) => run(input).await,
            Err(_) => Err("invalidRequest"),
        }
    };
    println!("{}", result.unwrap_or_else(error));
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_bounded_read_commands_are_allowed() {
        assert!(serde_json::from_value::<Input>(json!({"command":"snapshot","salt":"a".repeat(64)})).is_err());
        assert!(serde_json::from_value::<Input>(json!({"command":"identity","salt":"a".repeat(64),"url":"https://example.com"})).is_err());
        assert!(validate(&Input {command: Command::Identity, salt:"a".repeat(64), threads:vec![]}));
        assert!(!validate(&Input {command: Command::Identity, salt:"invalid".into(), threads:vec![]}));
        let row = || ThreadInput {id:"01a1010a-47ba-74c0-bcea-4bd709d5f6ca".into(), created_at:None, descendant_ids:vec![]};
        assert!(validate(&Input {command:Command::TaskUsage, salt:"a".repeat(64), threads:vec![row()]}));
        assert!(!validate(&Input {command:Command::TaskUsage, salt:"a".repeat(64), threads:vec![row(),row()]}));
    }
    #[test]
    fn invalid_auth_constraints_are_not_silently_dropped() {
        assert!(setting::<ForcedLoginMethod>(Some(toml::Value::String("invalid".into()))).is_err());
        assert!(setting::<AuthCredentialsStoreMode>(Some(toml::Value::Boolean(false))).is_err());
        assert!(setting::<ForcedLoginMethod>(None).unwrap().is_none());
    }
    #[test]
    fn api_and_signed_out_have_no_account_identifier() {
        for mode in ["api", "signedOut", "unknown"] {
            let value = auth_response(mode, None);
            assert_eq!(value["schemaVersion"], 2);
            assert!(value["accountKey"].is_null());
        }
    }
}
