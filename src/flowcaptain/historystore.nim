import std/[json, os]

import ./history
import ./types

type
  Sqlite3 = pointer
  Sqlite3Stmt = pointer

const
  SqliteOk = 0.cint
  SqliteRow = 100.cint
  SqliteDone = 101.cint
  SqliteTransient = cast[pointer](-1)
  SqliteLib = "libsqlite3.so(|.0)"

proc sqlite3_open(filename: cstring; db: ptr Sqlite3): cint
  {.cdecl, dynlib: SqliteLib, importc.}
proc sqlite3_close(db: Sqlite3): cint
  {.cdecl, dynlib: SqliteLib, importc.}
proc sqlite3_exec(db: Sqlite3; sql: cstring; callback, arg: pointer;
    errmsg: ptr cstring): cint
  {.cdecl, dynlib: SqliteLib, importc.}
proc sqlite3_free(value: pointer)
  {.cdecl, dynlib: SqliteLib, importc.}
proc sqlite3_prepare_v2(db: Sqlite3; sql: cstring; nBytes: cint;
    stmt: ptr Sqlite3Stmt; tail: ptr cstring): cint
  {.cdecl, dynlib: SqliteLib, importc.}
proc sqlite3_finalize(stmt: Sqlite3Stmt): cint
  {.cdecl, dynlib: SqliteLib, importc.}
proc sqlite3_step(stmt: Sqlite3Stmt): cint
  {.cdecl, dynlib: SqliteLib, importc.}
proc sqlite3_bind_text(stmt: Sqlite3Stmt; index: cint; value: cstring;
    nBytes: cint; destructor: pointer): cint
  {.cdecl, dynlib: SqliteLib, importc.}
proc sqlite3_bind_int64(stmt: Sqlite3Stmt; index: cint; value: int64): cint
  {.cdecl, dynlib: SqliteLib, importc.}
proc sqlite3_column_text(stmt: Sqlite3Stmt; index: cint): cstring
  {.cdecl, dynlib: SqliteLib, importc.}
proc sqlite3_errmsg(db: Sqlite3): cstring
  {.cdecl, dynlib: SqliteLib, importc.}

proc ensureParent(path: string) =
  let parent = parentDir(path)
  if parent.len > 0 and parent != ".":
    createDir(parent)

proc appendHistorySnapshotFile*(path: string;
    snapshot: CaptainHistorySnapshot) =
  path.ensureParent()
  let line = $snapshot.toJson()
  if fileExists(path) and getFileSize(path) > 0:
    var file = open(path, fmAppend)
    try:
      file.write("\n")
      file.write(line)
    finally:
      file.close()
  else:
    writeFile(path, line)

proc writeHistorySnapshotsFile*(path: string;
    snapshots: openArray[CaptainHistorySnapshot]) =
  path.ensureParent()
  writeFile(path, historySnapshotsJsonLines(snapshots))

proc loadHistorySnapshotsFile*(path: string): seq[CaptainHistorySnapshot] =
  if not fileExists(path):
    return @[]
  parseHistorySnapshotsJsonLines(readFile(path))

proc sqliteError(db: Sqlite3; prefix: string): ref ValueError =
  let message =
    if db == nil: prefix
    else: prefix & ": " & $sqlite3_errmsg(db)
  newException(ValueError, message)

proc openSqlite(path: string): Sqlite3 =
  path.ensureParent()
  var db: Sqlite3
  if sqlite3_open(path.cstring, addr db) != SqliteOk:
    let exc = sqliteError(db, "could not open history sqlite database")
    if db != nil:
      discard sqlite3_close(db)
    raise exc
  db

proc execSql(db: Sqlite3; statement: string) =
  var err: cstring
  if sqlite3_exec(db, statement.cstring, nil, nil, addr err) != SqliteOk:
    let message =
      if err == nil: $sqlite3_errmsg(db)
      else: $err
    if err != nil:
      sqlite3_free(cast[pointer](err))
    raise newException(ValueError, "history sqlite execution failed: " & message)

proc initHistorySqliteStore*(path: string) =
  let db = openSqlite(path)
  try:
    db.execSql("""
      create table if not exists flowcaptain_history (
        id integer primary key autoincrement,
        flow_id text not null,
        run_id text not null,
        recorded_at_ms integer not null,
        snapshot_json text not null
      );
      create index if not exists flowcaptain_history_flow_id_idx
        on flowcaptain_history(flow_id, id);
    """)
  finally:
    discard sqlite3_close(db)

proc prepare(db: Sqlite3; statement: string): Sqlite3Stmt =
  var stmt: Sqlite3Stmt
  if sqlite3_prepare_v2(db, statement.cstring, -1, addr stmt, nil) != SqliteOk:
    raise sqliteError(db, "could not prepare history sqlite statement")
  stmt

proc bindText(stmt: Sqlite3Stmt; index: cint; value: string) =
  if sqlite3_bind_text(stmt, index, value.cstring, -1, SqliteTransient) != SqliteOk:
    raise newException(ValueError, "could not bind history sqlite text")

proc appendHistorySnapshotSqlite*(path: string;
    snapshot: CaptainHistorySnapshot) =
  initHistorySqliteStore(path)
  let db = openSqlite(path)
  var stmt: Sqlite3Stmt
  try:
    stmt = db.prepare("""
      insert into flowcaptain_history
        (flow_id, run_id, recorded_at_ms, snapshot_json)
      values (?, ?, ?, ?)
    """)
    stmt.bindText(1, snapshot.flowId)
    stmt.bindText(2, snapshot.runId)
    if sqlite3_bind_int64(stmt, 3, snapshot.recordedAtMs.int64) != SqliteOk:
      raise newException(ValueError, "could not bind history sqlite timestamp")
    stmt.bindText(4, $snapshot.toJson())
    if sqlite3_step(stmt) != SqliteDone:
      raise sqliteError(db, "could not insert history sqlite snapshot")
  finally:
    if stmt != nil:
      discard sqlite3_finalize(stmt)
    discard sqlite3_close(db)

proc loadHistorySnapshotsSqlite*(path: string; flowId = ""):
    seq[CaptainHistorySnapshot] =
  if not fileExists(path):
    return @[]
  let db = openSqlite(path)
  var stmt: Sqlite3Stmt
  try:
    if flowId.len > 0:
      stmt = db.prepare("""
        select snapshot_json from flowcaptain_history
        where flow_id = ?
        order by id asc
      """)
      stmt.bindText(1, flowId)
    else:
      stmt = db.prepare("""
        select snapshot_json from flowcaptain_history
        order by id asc
      """)

    while true:
      let code = sqlite3_step(stmt)
      if code == SqliteRow:
        let raw = sqlite3_column_text(stmt, 0)
        if raw != nil:
          result.add(($raw).parseHistorySnapshotsJsonLines()[0])
      elif code == SqliteDone:
        break
      else:
        raise sqliteError(db, "could not read history sqlite snapshots")
  finally:
    if stmt != nil:
      discard sqlite3_finalize(stmt)
    discard sqlite3_close(db)
