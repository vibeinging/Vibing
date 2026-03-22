//
//  main.rs
//  Vibe Terminal Server
//
//  终端同步服务器 - 主端
//

use anyhow::{Context, Result};
use clap::Parser;
use std::path::Path;
use tokio::signal::unix::SignalKind;
use tracing::{error, info, warn, Level};
use tracing_subscriber::fmt;

mod config;
mod protocol;
mod pty;
mod relay_client;
mod render;
mod server;
mod vt100;

use config::ServerConfig;
use server::TerminalServer;
use relay_client::{RelayClient, RelayRole};

#[derive(Parser, Debug)]
#[command(name = "vibe-terminal-server")]
#[command(author = "YiY")]
#[command(version = "0.1.0")]
#[command(about = "Vibe Terminal Server - 多端终端同步服务", long_about = None)]
struct Args {
    /// 配置文件路径
    #[arg(short, long, default_value = "config.toml")]
    config: String,

    /// 监听地址（直接模式）
    #[arg(short, long, default_value = "0.0.0.0:8765")]
    bind: String,

    /// 日志级别 (trace, debug, info, warn, error)
    #[arg(long, default_value = "info")]
    log: String,

    /// 创建默认配置文件并退出
    #[arg(long)]
    init_config: bool,

    /// 验证配置文件并退出
    #[arg(long)]
    validate_config: bool,

    /// 中继模式：连接到中继服务器
    #[arg(long)]
    relay: bool,

    /// 中继服务器地址
    #[arg(long, default_value = "ws://localhost:8766")]
    relay_url: String,

    /// 会话 ID（中继模式，16 字符）
    #[arg(long)]
    session_id: Option<String>,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();

    // 初始化日志
    init_logging(&args.log);

    // 处理初始化配置
    if args.init_config {
        return init_config_file(&args.config);
    }

    // 中继模式
    if args.relay {
        return run_relay_mode(args).await;
    }

    // 加载或创建配置
    let config = load_or_create_config(&args.config)?;

    // 验证模式
    if args.validate_config {
        validate_config(&config);
        return Ok(());
    }

    // 直接模式：启动服务器
    run_server(args.bind, config).await
}

/// 初始化日志系统
fn init_logging(log_level: &str) {
    let level = match log_level.to_lowercase().as_str() {
        "trace" => Level::TRACE,
        "debug" => Level::DEBUG,
        "info" => Level::INFO,
        "warn" => Level::WARN,
        "error" => Level::ERROR,
        _ => {
            eprintln!("Unknown log level '{}', using 'info'", log_level);
            Level::INFO
        }
    };

    fmt()
        .with_max_level(level)
        .with_target(false)
        .with_thread_ids(false)
        .with_file(false)
        .with_line_number(false)
        .init();
}

/// 初始化配置文件
fn init_config_file(config_path: &str) -> Result<()> {
    let config = ServerConfig::default();

    // 检查文件是否存在
    if Path::new(config_path).exists() {
        eprintln!("配置文件 '{}' 已存在", config_path);
        eprintln!("如需重新生成，请先删除现有文件");
        std::process::exit(1);
    }

    config
        .save(config_path)
        .with_context(|| format!("无法保存配置文件到 '{}'", config_path))?;

    println!("已创建默认配置文件: {}", config_path);
    Ok(())
}

/// 加载配置文件，如果不存在则创建默认配置
fn load_or_create_config(config_path: &str) -> Result<ServerConfig> {
    let path = Path::new(config_path);

    if !path.exists() {
        warn!("配置文件 '{}' 不存在，使用默认配置", config_path);
        warn!("提示: 使用 --init-config 创建配置文件");

        let default_config = ServerConfig::default();
        info!("使用默认配置:");
        print_config_info(&default_config);

        return Ok(default_config);
    }

    ServerConfig::load(config_path)
        .with_context(|| format!("无法加载配置文件 '{}'", config_path))
        .and_then(|config| {
            validate_config(&config);
            Ok(config)
        })
}

/// 验证配置
fn validate_config(config: &ServerConfig) {
    info!("配置验证通过:");
    print_config_info(config);
}

/// 打印配置信息
fn print_config_info(config: &ServerConfig) {
    info!("  监听地址: {}", config.bind);
    info!("  默认 Shell: {}", config.default_shell);
    info!("  最大会话数: {}", config.max_sessions);
    info!("  空闲超时: {} 分钟", config.idle_timeout_minutes);
    info!("  默认环境变量: {} 个", config.default_env.len());
}

/// 运行服务器
async fn run_server(bind_addr: String, config: ServerConfig) -> Result<()> {
    print_startup_banner(&bind_addr, &config);

    // 创建服务器
    let server = TerminalServer::new(bind_addr.clone(), config)
        .await
        .context("无法创建服务器实例")?;

    // 启动服务器任务
    let server_handle = tokio::spawn(async move {
        if let Err(e) = server.start().await {
            error!("服务器错误: {}", e);
        }
    });

    // 等待关闭信号
    info!("服务器正在运行，按 Ctrl+C 停止");

    tokio::select! {
        // Ctrl+C (跨平台)
        _ = tokio::signal::ctrl_c() => {
            info!("收到 Ctrl+C 信号");
        }
        // SIGTERM (Unix only)
        _ = wait_for_sigterm() => {
            info!("收到 SIGTERM 信号");
        }
        // 服务器任务结束
        result = server_handle => {
            match result {
                Ok(()) => info!("服务器任务正常结束"),
                Err(e) => error!("服务器任务异常: {}", e),
            }
        }
    }

    info!("正在关闭服务器...");
    info!("再见!");
    Ok(())
}

/// 打印启动横幅
fn print_startup_banner(bind_addr: &str, config: &ServerConfig) {
    info!("==================================");
    info!(" Vibe Terminal Server");
    info!(" 多端终端同步服务");
    info!("==================================");
    info!("监听地址: {}", bind_addr);
    info!("默认 Shell: {}", config.default_shell);
    info!("终端特性: VT100/ANSI 支持");
    info!("最大会话: {}", config.max_sessions);
    info!("==================================");
}

/// 运行中继模式
async fn run_relay_mode(args: Args) -> Result<()> {
    // 获取或生成 session_id
    let session_id = if let Some(sid) = args.session_id {
        sid
    } else {
        // 生成随机 session_id
        use rand::Rng;
        const CHARSET: &[u8] = b"abcdefghjkmnpqrstuvwxyz23456789";
        let mut rng = rand::thread_rng();
        (0..16)
            .map(|_| CHARSET[rng.gen_range(0..CHARSET.len())] as char)
            .collect()
    };

    info!("==================================");
    info!(" Vibe Terminal - Relay Mode");
    info!("==================================");
    info!("中继服务器: {}", args.relay_url);
    info!("会话 ID: {}", session_id);
    info!("角色: Host (桌面端)");
    info!("==================================");
    info!("");
    info!("请在移动端输入相同的会话 ID 连接");

    // 创建中继客户端
    let client = RelayClient::new(
        args.relay_url,
        session_id.clone(),
        RelayRole::Host,
    )?;

    // 连接到中继服务器
    client.connect().await.context("无法连接到中继服务器")?;

    info!("已连接到中继服务器，等待移动端连接...");

    // 等待对端连接
    loop {
        tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;

        if client.is_peer_connected().await {
            info!("✅ 移动端已连接！会话建立成功");
            break;
        }
    }

    // 保持运行，处理数据
    info!("会话中运行，按 Ctrl+C 停止");

    tokio::select! {
        // Ctrl+C
        _ = tokio::signal::ctrl_c() => {
            info!("收到 Ctrl+C 信号");
        }
        // SIGTERM (Unix only)
        _ = wait_for_sigterm() => {
            info!("收到 SIGTERM 信号");
        }
    }

    client.disconnect().await?;
    info!("中继连接已关闭");
    Ok(())
}

/// 等待 SIGTERM 信号 (Unix only)
#[cfg(unix)]
async fn wait_for_sigterm() {
    match tokio::signal::unix::signal(SignalKind::terminate()) {
        Ok(mut sigterm) => {
            sigterm.recv().await;
        }
        Err(e) => {
            warn!("无法设置 SIGTERM 处理器: {}", e);
            // 永远等待，让其他信号处理
            std::future::pending::<()>().await;
        }
    }
}

/// 在非 Unix 平台上，SIGTERM 处理器永远等待
#[cfg(not(unix))]
async fn wait_for_sigterm() {
    std::future::pending::<()>().await;
}
