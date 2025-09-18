use std::net::SocketAddr;

use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use chrono::{DateTime, Local};
use r2d2::{Pool, PooledConnection};
use r2d2_sqlite::SqliteConnectionManager;
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};
use tokio::signal;
use tracing::{error, info};
use tracing_subscriber::EnvFilter;

#[derive(Clone)]
struct AppState {
    db: Pool<SqliteConnectionManager>,
}

#[derive(Debug, Serialize, Deserialize)]
struct ProcessRequest {
    barcode: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct ProcessResponse {
    success: bool,
    message: String,
    group: String,
    shift: String,
    plan_target: i64,
    realtime_count: i64,
    barcode: String,
    timestamp: DateTime<Local>,
}

#[derive(Debug, Serialize, Deserialize)]
struct SettingsResponse {
    group: String,
    shift: String,
    plan_target: i64,
    realtime_count: i64,
}

#[derive(Debug, Deserialize)]
struct SetGroupRequest {
    group: String,
}

#[derive(Debug, Deserialize)]
struct MockScanRequest {
    success: bool,
}

fn get_conn(state: &AppState) -> anyhow::Result<PooledConnection<SqliteConnectionManager>> {
    Ok(state.db.get()?)
}

fn init_db(pool: &Pool<SqliteConnectionManager>) -> anyhow::Result<()> {
    let conn = pool.get()?;
    conn.execute_batch(
        "PRAGMA journal_mode=WAL;\n\
         PRAGMA synchronous=NORMAL;\n\
         CREATE TABLE IF NOT EXISTS scans (\n\
             id INTEGER PRIMARY KEY AUTOINCREMENT,\n\
             barcode TEXT NOT NULL,\n\
             success INTEGER NOT NULL,\n\
             ts TEXT NOT NULL\n\
         );\n\
         CREATE TABLE IF NOT EXISTS settings (\n\
             id INTEGER PRIMARY KEY CHECK (id = 1),\n\
             group_name TEXT NOT NULL,\n\
             shift_name TEXT NOT NULL,\n\
             plan_target INTEGER NOT NULL\n\
         );\n\
         INSERT OR IGNORE INTO settings (id, group_name, shift_name, plan_target)\n\
         VALUES (1, 'A组', '白班', 500);\n",
    )?;
    Ok(())
}

fn read_settings(conn: &rusqlite::Connection) -> anyhow::Result<(String, String, i64)> {
    let row: (String, String, i64) = conn
        .query_row(
            "SELECT group_name, shift_name, plan_target FROM settings WHERE id = 1",
            [],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )
        .optional()?
        .unwrap_or_else(|| ("A组".to_string(), "白班".to_string(), 500));
    Ok(row)
}

fn count_success_today(conn: &rusqlite::Connection) -> anyhow::Result<i64> {
    let start_of_day = Local::now().date_naive().and_hms_opt(0, 0, 0).unwrap();
    let start_of_day_str = start_of_day.and_local_timezone(Local).unwrap().to_rfc3339();
    let count: i64 = conn.query_row(
        "SELECT COUNT(1) FROM scans WHERE success = 1 AND ts >= ?1",
        params![start_of_day_str],
        |r| r.get(0),
    )?;
    Ok(count)
}

async fn get_settings(State(state): State<AppState>) -> impl IntoResponse {
    let conn = match get_conn(&state) {
        Ok(c) => c,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    };
    match (|| -> anyhow::Result<SettingsResponse> {
        let (group, shift, plan_target) = read_settings(&conn)?;
        let realtime = count_success_today(&conn)?;
        Ok(SettingsResponse { group, shift, plan_target, realtime_count: realtime })
    })() {
        Ok(s) => (StatusCode::OK, Json(s)).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}

async fn process_barcode(State(state): State<AppState>, Json(req): Json<ProcessRequest>) -> impl IntoResponse {
    if req.barcode.trim().is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "barcode is empty"})),
        )
            .into_response();
    }

    let conn = match get_conn(&state) {
        Ok(c) => c,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    };

    let now = Local::now();
    let success = mock_external_service(&req.barcode);

    if let Err(e) = conn.execute(
        "INSERT INTO scans (barcode, success, ts) VALUES (?1, ?2, ?3)",
        params![req.barcode, if success { 1 } else { 0 }, now.to_rfc3339()],
    ) {
        error!("DB insert error: {}", e);
    }

    let (group, shift, plan_target) = match read_settings(&conn) {
        Ok(v) => v,
        Err(_) => ("A组".into(), "白班".into(), 500),
    };
    let realtime = count_success_today(&conn).unwrap_or(0);

    let resp = ProcessResponse {
        success,
        message: if success { "扫码正确".into() } else { "扫码错误".into() },
        group,
        shift,
        plan_target,
        realtime_count: realtime,
        barcode: req.barcode,
        timestamp: now,
    };
    (StatusCode::OK, Json(resp)).into_response()
}

async fn set_group(State(state): State<AppState>, Json(req): Json<SetGroupRequest>) -> impl IntoResponse {
    let conn = match get_conn(&state) {
        Ok(c) => c,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    };
    let new_group = match req.group.as_str() {
        "A组" | "B组" => req.group,
        _ => return (StatusCode::BAD_REQUEST, "invalid group").into_response(),
    };
    if let Err(e) = conn.execute(
        "UPDATE settings SET group_name = ?1 WHERE id = 1",
        params![new_group],
    ) {
        return (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response();
    }
    get_settings(State(state)).await
}

async fn mock_scan(State(state): State<AppState>, Json(req): Json<MockScanRequest>) -> impl IntoResponse {
    let conn = match get_conn(&state) {
        Ok(c) => c,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    };
    let now = Local::now();
    if let Err(e) = conn.execute(
        "INSERT INTO scans (barcode, success, ts) VALUES (?1, ?2, ?3)",
        params!["模拟", if req.success { 1 } else { 0 }, now.to_rfc3339()],
    ) {
        error!("DB insert error: {}", e);
    }
    let (group, shift, plan_target) = match read_settings(&conn) {
        Ok(v) => v,
        Err(_) => ("A组".into(), "白班".into(), 500),
    };
    let realtime = count_success_today(&conn).unwrap_or(0);
    let resp = ProcessResponse {
        success: req.success,
        message: if req.success { "扫码正确".into() } else { "扫码错误".into() },
        group,
        shift,
        plan_target,
        realtime_count: realtime,
        barcode: "模拟".into(),
        timestamp: now,
    };
    (StatusCode::OK, Json(resp)).into_response()
}

fn mock_external_service(barcode: &str) -> bool {
    // Demo logic: success if length is even and not ending with '9'
    let len = barcode.trim().len();
    len > 0 && len % 2 == 0 && !barcode.ends_with('9')
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    let db_path = std::env::var("SCAN_DEMO_DB").unwrap_or_else(|_| "scan_demo.sqlite".into());
    let manager = SqliteConnectionManager::file(db_path);
    let pool = Pool::new(manager)?;
    init_db(&pool)?;

    let state = AppState { db: pool };

    let app = Router::new()
        .route("/api/settings", get(get_settings))
        .route("/api/process_barcode", post(process_barcode))
        .route("/api/set_group", post(set_group))
        .route("/api/mock_scan", post(mock_scan))
        .with_state(state);

    let port: u16 = std::env::var("PORT").ok().and_then(|s| s.parse().ok()).unwrap_or(8080);
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    info!("Starting server on {}", addr);

    let server = axum::serve(tokio::net::TcpListener::bind(addr).await?, app);

    tokio::select! {
        res = server => {
            if let Err(e) = res { error!("server error: {}", e); }
        }
        _ = signal::ctrl_c() => {
            info!("Shutting down");
        }
    }

    Ok(())
}
