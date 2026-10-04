#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/signals.h>
#include <sqlite3.h>
#include <limits.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ox_sql owns the system-SQLite FFI: compile against <sqlite3.h>, link via
   pkg-config, and expose native SQLite operations such as backup and extension
   loading. Keep shared SQL behavior in OCaml modules instead of hiding
   foreign contracts behind one C extension. */

typedef struct ox_sqlite_db_state {
  sqlite3 *db;
  pthread_mutex_t mutex;
  int mutex_initialized;
  /* Only the exclusive operation owner installs/removes this pointer. The
     token is rooted by with_handler; concurrent request touches its atomic
     flag, never this pointer. Close clears it under mutex. */
  _Atomic int *cancelled;
} ox_sqlite_db_state;

typedef struct {
  ox_sqlite_db_state *state;
} ox_sqlite_db;

typedef struct {
  sqlite3_stmt *stmt;
} ox_sqlite_stmt;

typedef struct {
  char *ptr;
} ox_sqlite_string_owner;

static void ox_sqlite_finalize_db(value v_db)
{
  ox_sqlite_db *slot = (ox_sqlite_db *)Data_custom_val(v_db);
  ox_sqlite_db_state *db = slot->state;
  if (db == NULL) return;
  if (db->mutex_initialized) pthread_mutex_lock(&db->mutex);
  if (db->db != NULL) {
    /* Custom finalizers run from the OCaml runtime's finalization path; entering
       a blocking section here aborts under OCaml 5. Explicit close functions
       below release the runtime lock, so finalization is only a last-resort
       cleanup path for leaked handles. */
    (void)sqlite3_close_v2(db->db);
    db->db = NULL;
  }
  if (db->mutex_initialized) {
    pthread_mutex_unlock(&db->mutex);
    pthread_mutex_destroy(&db->mutex);
    db->mutex_initialized = 0;
  }
  free(db);
  slot->state = NULL;
}

static void ox_sqlite_finalize_stmt(value v_stmt)
{
  ox_sqlite_stmt *stmt = (ox_sqlite_stmt *)Data_custom_val(v_stmt);
  if (stmt->stmt != NULL) {
    /* See ox_sqlite_finalize_db: explicit statement finalization releases the
       runtime lock; the custom finalizer must stay within runtime finalizer
       constraints. */
    (void)sqlite3_finalize(stmt->stmt);
    stmt->stmt = NULL;
  }
}

static struct custom_operations ox_sqlite_db_ops = {
  "ox.sqlite.db",
  ox_sqlite_finalize_db,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default,
  custom_compare_ext_default,
  custom_fixed_length_default
};

static struct custom_operations ox_sqlite_stmt_ops = {
  "ox.sqlite.stmt",
  ox_sqlite_finalize_stmt,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default,
  custom_compare_ext_default,
  custom_fixed_length_default
};

static ox_sqlite_string_owner *sqlite_string_owner_val(value v_owner)
{
  return (ox_sqlite_string_owner *)Data_custom_val(v_owner);
}

static void sqlite_string_owner_finalize(value v_owner)
{
  ox_sqlite_string_owner *owner = sqlite_string_owner_val(v_owner);
  if (owner->ptr != NULL) {
    sqlite3_free(owner->ptr);
    owner->ptr = NULL;
  }
}

static struct custom_operations sqlite_string_owner_ops = {
  "ox.sqlite.string_owner",
  sqlite_string_owner_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default,
  custom_compare_ext_default,
  custom_fixed_length_default
};

static value sqlite_string_owner_alloc(void)
{
  CAMLparam0();
  CAMLlocal1(v_owner);
  ox_sqlite_string_owner *owner;
  v_owner = caml_alloc_custom(&sqlite_string_owner_ops, sizeof(ox_sqlite_string_owner), 0, 1);
  owner = sqlite_string_owner_val(v_owner);
  owner->ptr = NULL;
  CAMLreturn(v_owner);
}

static void sqlite_string_owner_set(value v_owner, char *ptr)
{
  sqlite_string_owner_val(v_owner)->ptr = ptr;
}

static void sqlite_string_owner_release(value v_owner)
{
  ox_sqlite_string_owner *owner = sqlite_string_owner_val(v_owner);
  if (owner->ptr != NULL) {
    char *ptr = owner->ptr;
    owner->ptr = NULL;
    sqlite3_free(ptr);
  }
}

static ox_sqlite_db_state *ox_sqlite_db_state_val(value v_db)
{
  ox_sqlite_db *db = (ox_sqlite_db *)Data_custom_val(v_db);
  return db->state;
}

static sqlite3 *ox_sqlite_db_val(value v_db)
{
  ox_sqlite_db_state *db = ox_sqlite_db_state_val(v_db);
  return db == NULL ? NULL : db->db;
}

/* An operation owns a stable, GC-independent cancellation flag. SQLite's
   idle interrupt is not sticky: native entry checks reject pre-requested work,
   and the progress callback preserves cooperative interruption after entry. */
static _Atomic int *ox_sqlite_cancellation_val(value token)
{
  return *(_Atomic int **)Data_custom_val(token);
}

static void ox_sqlite_cancellation_finalize(value token)
{
  free(ox_sqlite_cancellation_val(token));
}

static struct custom_operations ox_sqlite_cancellation_ops = {
  "ox.sqlite.operation_cancellation",
  ox_sqlite_cancellation_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default,
  custom_compare_ext_default,
  custom_fixed_length_default
};

CAMLprim value ox_sqlite_cancellation_create(value unit)
{
  CAMLparam1(unit);
  CAMLlocal1(token);
  _Atomic int *cancelled;
  token = caml_alloc_custom(&ox_sqlite_cancellation_ops, sizeof(cancelled), 0, 1);
  *(_Atomic int **)Data_custom_val(token) = NULL;
  cancelled = malloc(sizeof(*cancelled));
  if (cancelled == NULL) caml_raise_out_of_memory();
  atomic_init(cancelled, 0);
  *(_Atomic int **)Data_custom_val(token) = cancelled;
  CAMLreturn(token);
}

CAMLprim value ox_sqlite_cancellation_request(value token)
{
  atomic_store(ox_sqlite_cancellation_val(token), 1);
  return Val_unit;
}

/* TEST-ONLY post-entry gate, distinct from the before-step fixture. It is
   reached only inside SQLite's VM progress callback. The gate uses no handle
   mutex: cancellation request/interrupt must be able to finish while paused.
   Private test-local externals are its only callers; no public SQL API. */
static pthread_mutex_t ox_sqlite_progress_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t ox_sqlite_progress_cond = PTHREAD_COND_INITIALIZER;
static _Atomic int ox_sqlite_progress_state = 0;

CAMLprim value ox_sqlite_test_progress_arm(value unit)
{
  (void)unit;
  atomic_store(&ox_sqlite_progress_state, 1);
  return Val_unit;
}

CAMLprim value ox_sqlite_test_progress_wait(value unit)
{
  CAMLparam1(unit);
  caml_enter_blocking_section();
  pthread_mutex_lock(&ox_sqlite_progress_mu);
  while (atomic_load(&ox_sqlite_progress_state) == 1)
    pthread_cond_wait(&ox_sqlite_progress_cond, &ox_sqlite_progress_mu);
  pthread_mutex_unlock(&ox_sqlite_progress_mu);
  caml_leave_blocking_section();
  CAMLreturn(Val_unit);
}

CAMLprim value ox_sqlite_test_progress_release(value unit)
{
  (void)unit;
  pthread_mutex_lock(&ox_sqlite_progress_mu);
  atomic_store(&ox_sqlite_progress_state, 0);
  pthread_cond_broadcast(&ox_sqlite_progress_cond);
  pthread_mutex_unlock(&ox_sqlite_progress_mu);
  return Val_unit;
}

static int ox_sqlite_cancellation_progress(void *cancelled)
{
  if (atomic_load(&ox_sqlite_progress_state) == 1) {
    pthread_mutex_lock(&ox_sqlite_progress_mu);
    if (atomic_load(&ox_sqlite_progress_state) == 1) {
      atomic_store(&ox_sqlite_progress_state, 2);
      pthread_cond_broadcast(&ox_sqlite_progress_cond);
      while (atomic_load(&ox_sqlite_progress_state) == 2)
        pthread_cond_wait(&ox_sqlite_progress_cond, &ox_sqlite_progress_mu);
    }
    pthread_mutex_unlock(&ox_sqlite_progress_mu);
  }
  return atomic_load((_Atomic int *)cancelled);
}

static int ox_sqlite_cancelled_at_entry(ox_sqlite_db_state *slot)
{
  return slot->cancelled != NULL && atomic_load(slot->cancelled);
}

CAMLprim value ox_sqlite_cancellation_install(value v_db, value token)
{
  ox_sqlite_db_state *slot = ox_sqlite_db_state_val(v_db);
  if (slot == NULL) return Val_unit;
  pthread_mutex_lock(&slot->mutex);
  if (slot->db != NULL) {
    slot->cancelled = ox_sqlite_cancellation_val(token);
    sqlite3_progress_handler(slot->db, 1000, ox_sqlite_cancellation_progress,
                             slot->cancelled);
  }
  pthread_mutex_unlock(&slot->mutex);
  return Val_unit;
}

CAMLprim value ox_sqlite_cancellation_remove(value v_db, value token)
{
  ox_sqlite_db_state *slot = ox_sqlite_db_state_val(v_db);
  /* Passing token here keeps its native storage live until the callback has
     been removed; the worker has finished all SQLite calls at this point. */
  (void)token;
  if (slot == NULL) return Val_unit;
  pthread_mutex_lock(&slot->mutex);
  if (slot->db != NULL) sqlite3_progress_handler(slot->db, 0, NULL, NULL);
  slot->cancelled = NULL;
  pthread_mutex_unlock(&slot->mutex);
  return Val_unit;
}

static void ox_sqlite_db_init(value v_db)
{
  ox_sqlite_db *slot = (ox_sqlite_db *)Data_custom_val(v_db);
  ox_sqlite_db_state *db = malloc(sizeof(ox_sqlite_db_state));
  slot->state = NULL;
  if (db == NULL) {
    caml_failwith("sqlite open: state allocation failed");
  }
  db->db = NULL;
  db->cancelled = NULL;
  db->mutex_initialized = 0;
  if (pthread_mutex_init(&db->mutex, NULL) != 0) {
    free(db);
    caml_failwith("sqlite open: mutex init failed");
  }
  db->mutex_initialized = 1;
  slot->state = db;
}

static sqlite3_stmt *ox_sqlite_stmt_val(value v_stmt)
{
  ox_sqlite_stmt *stmt = (ox_sqlite_stmt *)Data_custom_val(v_stmt);
  return stmt->stmt;
}

static char *ox_sqlite_copy_ocaml_string(value v_string, size_t *len_out)
{
  mlsize_t len = caml_string_length(v_string);
  char *copy = malloc((size_t)len + 1);
  if (copy == NULL) {
    return NULL;
  }
  memcpy(copy, String_val(v_string), (size_t)len);
  copy[len] = '\0';
  if (len_out != NULL) {
    *len_out = (size_t)len;
  }
  return copy;
}

static int ox_sqlite_ocaml_string_len_as_int(value v_string, int *len_out)
{
  mlsize_t len = caml_string_length(v_string);
  if (len > (mlsize_t)INT_MAX) {
    return SQLITE_TOOBIG;
  }
  *len_out = (int)len;
  return SQLITE_OK;
}

CAMLprim intnat ox_sqlite_rc_ok(value v_unit)
{
  (void)v_unit;
  return SQLITE_OK;
}

CAMLprim value ox_sqlite_rc_ok_bc(value v_unit)
{
  (void)v_unit;
  return Val_int(SQLITE_OK);
}

CAMLprim intnat ox_sqlite_rc_row(value v_unit)
{
  (void)v_unit;
  return SQLITE_ROW;
}

CAMLprim value ox_sqlite_rc_row_bc(value v_unit)
{
  (void)v_unit;
  return Val_int(SQLITE_ROW);
}

CAMLprim intnat ox_sqlite_rc_done(value v_unit)
{
  (void)v_unit;
  return SQLITE_DONE;
}

CAMLprim value ox_sqlite_rc_done_bc(value v_unit)
{
  (void)v_unit;
  return Val_int(SQLITE_DONE);
}

CAMLprim intnat ox_sqlite_rc_misuse(value v_unit)
{
  (void)v_unit;
  return SQLITE_MISUSE;
}

CAMLprim value ox_sqlite_rc_misuse_bc(value v_unit)
{
  (void)v_unit;
  return Val_int(SQLITE_MISUSE);
}

CAMLprim intnat ox_sqlite_rc_range(value v_unit)
{
  (void)v_unit;
  return SQLITE_RANGE;
}

CAMLprim value ox_sqlite_rc_range_bc(value v_unit)
{
  (void)v_unit;
  return Val_int(SQLITE_RANGE);
}

CAMLprim intnat ox_sqlite_rc_constraint(value v_unit)
{
  (void)v_unit;
  return SQLITE_CONSTRAINT;
}

CAMLprim value ox_sqlite_rc_constraint_bc(value v_unit)
{
  (void)v_unit;
  return Val_int(SQLITE_CONSTRAINT);
}

static int ox_sqlite_flags_of_mode(intnat mode)
{
  switch (mode) {
  case 0:
    return SQLITE_OPEN_READONLY | SQLITE_OPEN_URI;
  case 1:
    return SQLITE_OPEN_READWRITE | SQLITE_OPEN_URI;
  default:
    return SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_URI;
  }
}

CAMLprim value ox_sqlite_open(value v_path, intnat mode)
{
  CAMLparam1(v_path);
  CAMLlocal1(v_block);
  sqlite3 *db = NULL;
  char *path = ox_sqlite_copy_ocaml_string(v_path, NULL);
  int rc;
  v_block = caml_alloc_custom(&ox_sqlite_db_ops, sizeof(ox_sqlite_db), 0, 1);
  ox_sqlite_db_init(v_block);
  if (path == NULL) {
    caml_failwith("sqlite open: out of memory");
  }
  caml_enter_blocking_section();
  rc = sqlite3_open_v2(path, &db, ox_sqlite_flags_of_mode(mode), NULL);
  caml_leave_blocking_section();
  free(path);
  if (rc != SQLITE_OK) {
    const char *message = db == NULL ? sqlite3_errstr(rc) : sqlite3_errmsg(db);
    char buffer[256];
    snprintf(buffer, sizeof(buffer), "sqlite open: %s", message);
    if (db != NULL) {
      (void)sqlite3_close_v2(db);
    }
    caml_failwith(buffer);
  }

  ox_sqlite_db_state_val(v_block)->db = db;
  CAMLreturn(v_block);
}

CAMLprim value ox_sqlite_open_bc(value v_path, value v_mode)
{
  return ox_sqlite_open(v_path, Int_val(v_mode));
}

/* TEST-ONLY close/interrupt order handshake (close_order_probe.exe).
   Single synchronization discipline: all shared state below is accessed
   only while holding ox_sqlite_test_mu (no volatile). States: 0 disarmed,
   1 armed, 2 closer paused, 3 interrupt arrived. The closer pauses after
   sqlite3_close_v2 while still holding slot->mutex with the runtime
   released; the interrupt hook signals arrival BEFORE attempting the slot
   mutex and releases the test mutex first, so the test mutex is never held
   while waiting on the slot mutex or the runtime. Waits are unbounded
   cond-waits; the whole probe executable runs under an external timeout.
   Reachable from OCaml only through test-local externals (no .mli
   surface). Production closes never pause: the pause branch requires
   state == 1, reachable only via the armed probe. */
static pthread_mutex_t ox_sqlite_test_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t ox_sqlite_test_cond = PTHREAD_COND_INITIALIZER;
static int ox_sqlite_test_state = 0;

CAMLprim intnat ox_sqlite_close(value v_db)
{
  CAMLparam1(v_db);
  ox_sqlite_db_state *slot = ox_sqlite_db_state_val(v_db);
  sqlite3 *db;
  int rc;
  if (slot == NULL) {
    CAMLreturnT(intnat, SQLITE_OK);
  }
  pthread_mutex_lock(&slot->mutex);
  db = slot->db;
  if (db == NULL) {
    pthread_mutex_unlock(&slot->mutex);
    CAMLreturnT(intnat, SQLITE_OK);
  }
  caml_enter_blocking_section();
  rc = sqlite3_close_v2(db);
  /* TEST-ONLY handshake: while armed, pause here holding slot->mutex with
     the runtime released until the interrupt hook signals arrival. No OCaml
     heap access, no allocation, no runtime reacquire before the wait ends.
     Lock order slot->test_mu is nested only here and bounded (setters hold
     test_mu alone, briefly); the hook releases test_mu before slot. */
  pthread_mutex_lock(&ox_sqlite_test_mu);
  if (ox_sqlite_test_state == 1) {
    ox_sqlite_test_state = 2;
    pthread_cond_broadcast(&ox_sqlite_test_cond);
    while (ox_sqlite_test_state == 2) {
      pthread_cond_wait(&ox_sqlite_test_cond, &ox_sqlite_test_mu);
    }
  }
  pthread_mutex_unlock(&ox_sqlite_test_mu);
  if (rc == SQLITE_OK) {
    slot->db = NULL;
    slot->cancelled = NULL;
  }
  /* Lock-order repair, unconditional: publish the closed handle and release
     the slot mutex BEFORE reacquiring the OCaml runtime. The previous order
     reacquired the runtime first, so a closer holding the mutex waited on
     the runtime while an interrupter owning the runtime waited on the
     mutex. */
  pthread_mutex_unlock(&slot->mutex);
  caml_leave_blocking_section();
  CAMLreturnT(intnat, rc);
}

CAMLprim value ox_sqlite_test_close_arm(value v_unit)
{
  CAMLparam1(v_unit);
  pthread_mutex_lock(&ox_sqlite_test_mu);
  ox_sqlite_test_state = 1;
  pthread_mutex_unlock(&ox_sqlite_test_mu);
  CAMLreturn(Val_unit);
}

CAMLprim value ox_sqlite_test_close_wait(value unit)
{
  CAMLparam1(unit);
  caml_enter_blocking_section();
  pthread_mutex_lock(&ox_sqlite_test_mu);
  while (ox_sqlite_test_state == 1)
    pthread_cond_wait(&ox_sqlite_test_cond, &ox_sqlite_test_mu);
  pthread_mutex_unlock(&ox_sqlite_test_mu);
  caml_leave_blocking_section();
  CAMLreturn(Val_unit);
}

CAMLprim value ox_sqlite_test_close_state(value v_unit)
{
  CAMLparam1(v_unit);
  int st;
  pthread_mutex_lock(&ox_sqlite_test_mu);
  st = ox_sqlite_test_state;
  pthread_mutex_unlock(&ox_sqlite_test_mu);
  CAMLreturn(Val_int(st));
}

CAMLprim value ox_sqlite_test_close_release(value v_unit)
{
  CAMLparam1(v_unit);
  pthread_mutex_lock(&ox_sqlite_test_mu);
  ox_sqlite_test_state = 0;
  pthread_cond_broadcast(&ox_sqlite_test_cond);
  pthread_mutex_unlock(&ox_sqlite_test_mu);
  CAMLreturn(Val_unit);
}

CAMLprim value ox_sqlite_close_bc(value v_db)
{
  return Val_int(ox_sqlite_close(v_db));
}

CAMLprim intnat ox_sqlite_busy_timeout(value v_db, intnat ms)
{
  sqlite3 *db = ox_sqlite_db_val(v_db);
  if (db == NULL) {
    return SQLITE_MISUSE;
  }
  return sqlite3_busy_timeout(db, (int)ms);
}

CAMLprim value ox_sqlite_busy_timeout_bc(value v_db, value v_ms)
{
  return Val_int(ox_sqlite_busy_timeout(v_db, Int_val(v_ms)));
}

CAMLprim intnat ox_sqlite_exec_script(value v_db, value v_sql)
{
  CAMLparam2(v_db, v_sql);
  ox_sqlite_db_state *slot = ox_sqlite_db_state_val(v_db);
  sqlite3 *db = slot == NULL ? NULL : slot->db;
  char *sql;
  char *errmsg = NULL;
  int rc;
  if (db == NULL) {
    CAMLreturnT(intnat, SQLITE_MISUSE);
  }
  sql = ox_sqlite_copy_ocaml_string(v_sql, NULL);
  if (sql == NULL) {
    CAMLreturnT(intnat, SQLITE_NOMEM);
  }
  caml_enter_blocking_section();
  rc = ox_sqlite_cancelled_at_entry(slot)
         ? SQLITE_INTERRUPT : sqlite3_exec(db, sql, NULL, NULL, &errmsg);
  caml_leave_blocking_section();
  free(sql);
  if (errmsg != NULL) {
    sqlite3_free(errmsg);
  }
  CAMLreturnT(intnat, rc);
}

CAMLprim value ox_sqlite_exec_script_bc(value v_db, value v_sql)
{
  return Val_int(ox_sqlite_exec_script(v_db, v_sql));
}

CAMLprim value ox_sqlite_prepare(value v_db, value v_sql)
{
  CAMLparam2(v_db, v_sql);
  CAMLlocal4(v_stmt, result, error, text);
  ox_sqlite_db_state *db_slot = ox_sqlite_db_state_val(v_db);
  sqlite3 *db = db_slot == NULL ? NULL : db_slot->db;
  sqlite3_stmt *stmt = NULL;
  size_t sql_len;
  char *sql = NULL;
  char message[512];
  int rc = SQLITE_MISUSE;
  v_stmt = caml_alloc_custom(&ox_sqlite_stmt_ops, sizeof(ox_sqlite_stmt), 0, 1);
  ((ox_sqlite_stmt *)Data_custom_val(v_stmt))->stmt = NULL;
  if (db == NULL) {
    snprintf(message, sizeof(message), "sqlite prepare: database is closed");
  } else {
    sql = ox_sqlite_copy_ocaml_string(v_sql, &sql_len);
    if (sql == NULL) {
      rc = SQLITE_NOMEM;
      snprintf(message, sizeof(message), "sqlite prepare: out of memory");
    } else if (sql_len > INT_MAX) {
      rc = SQLITE_TOOBIG;
      snprintf(message, sizeof(message), "sqlite prepare: SQL string too long");
    } else {
      caml_enter_blocking_section();
      if (ox_sqlite_cancelled_at_entry(db_slot)) {
        rc = SQLITE_INTERRUPT;
        snprintf(message, sizeof(message), "sqlite prepare: %s", sqlite3_errstr(rc));
      } else {
        rc = sqlite3_prepare_v2(db, sql, (int)sql_len, &stmt, NULL);
        if (rc != SQLITE_OK || stmt == NULL) {
          snprintf(message, sizeof(message), "sqlite prepare: %s", sqlite3_errmsg(db));
          if (rc == SQLITE_OK) rc = SQLITE_ERROR;
        }
      }
      caml_leave_blocking_section();
    }
    free(sql);
  }
  if (rc != SQLITE_OK) {
    text = caml_copy_string(message);
    error = caml_alloc_tuple(2);
    Store_field(error, 0, Val_int(rc));
    Store_field(error, 1, text);
    result = caml_alloc(1, 1); /* Error (rc, message), not an expected exception. */
    Store_field(result, 0, error);
  } else {
    ((ox_sqlite_stmt *)Data_custom_val(v_stmt))->stmt = stmt;
    result = caml_alloc(1, 0); /* Ok stmt */
    Store_field(result, 0, v_stmt);
  }
  CAMLreturn(result);
}

CAMLprim intnat ox_sqlite_finalize(value v_stmt)
{
  CAMLparam1(v_stmt);
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  int rc;
  if (stmt == NULL) {
    CAMLreturnT(intnat, SQLITE_OK);
  }
  caml_enter_blocking_section();
  rc = sqlite3_finalize(stmt);
  caml_leave_blocking_section();
  ((ox_sqlite_stmt *)Data_custom_val(v_stmt))->stmt = NULL;
  CAMLreturnT(intnat, rc);
}

CAMLprim value ox_sqlite_finalize_bc(value v_stmt)
{
  return Val_int(ox_sqlite_finalize(v_stmt));
}

CAMLprim intnat ox_sqlite_reset(value v_stmt)
{
  CAMLparam1(v_stmt);
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  int rc;
  if (stmt == NULL) {
    CAMLreturnT(intnat, SQLITE_MISUSE);
  }
  caml_enter_blocking_section();
  rc = sqlite3_reset(stmt);
  caml_leave_blocking_section();
  CAMLreturnT(intnat, rc);
}

CAMLprim value ox_sqlite_reset_bc(value v_stmt)
{
  return Val_int(ox_sqlite_reset(v_stmt));
}

CAMLprim intnat ox_sqlite_clear_bindings(value v_stmt)
{
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  if (stmt == NULL) {
    return SQLITE_MISUSE;
  }
  return sqlite3_clear_bindings(stmt);
}

CAMLprim value ox_sqlite_clear_bindings_bc(value v_stmt)
{
  return Val_int(ox_sqlite_clear_bindings(v_stmt));
}

CAMLprim intnat ox_sqlite_bind_parameter_count(value v_stmt)
{
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  if (stmt == NULL) {
    return 0;
  }
  return sqlite3_bind_parameter_count(stmt);
}

CAMLprim value ox_sqlite_bind_parameter_count_bc(value v_stmt)
{
  return Val_int(ox_sqlite_bind_parameter_count(v_stmt));
}

CAMLprim intnat ox_sqlite_bind_null(value v_stmt, intnat index)
{
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  if (stmt == NULL) {
    return SQLITE_MISUSE;
  }
  return sqlite3_bind_null(stmt, (int)index);
}

CAMLprim value ox_sqlite_bind_null_bc(value v_stmt, value v_index)
{
  return Val_int(ox_sqlite_bind_null(v_stmt, Int_val(v_index)));
}

CAMLprim intnat ox_sqlite_bind_int64(value v_stmt, intnat index, int64_t value)
{
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  if (stmt == NULL) {
    return SQLITE_MISUSE;
  }
  return sqlite3_bind_int64(stmt, (int)index, (sqlite3_int64)value);
}

CAMLprim value ox_sqlite_bind_int64_bc(value v_stmt, value v_index, value v_value)
{
  return Val_int(ox_sqlite_bind_int64(v_stmt, Int_val(v_index), Int64_val(v_value)));
}

CAMLprim intnat ox_sqlite_bind_int(value v_stmt, intnat index, intnat value)
{
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  if (stmt == NULL) {
    return SQLITE_MISUSE;
  }
  return sqlite3_bind_int64(stmt, (int)index, (sqlite3_int64)value);
}

CAMLprim value ox_sqlite_bind_int_bc(value v_stmt, value v_index, value v_value)
{
  return Val_int(ox_sqlite_bind_int(v_stmt, Int_val(v_index), Int_val(v_value)));
}

CAMLprim intnat ox_sqlite_bind_text(value v_stmt, intnat index, value v_text)
{
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  int len;
  int rc;
  if (stmt == NULL) {
    return SQLITE_MISUSE;
  }
  rc = ox_sqlite_ocaml_string_len_as_int(v_text, &len);
  if (rc != SQLITE_OK) {
    return rc;
  }
  return sqlite3_bind_text(
    stmt,
    (int)index,
    String_val(v_text),
    len,
    SQLITE_TRANSIENT);
}

CAMLprim value ox_sqlite_bind_text_bc(value v_stmt, value v_index, value v_text)
{
  return Val_int(ox_sqlite_bind_text(v_stmt, Int_val(v_index), v_text));
}

CAMLprim intnat ox_sqlite_bind_float(value v_stmt, intnat index, double value)
{
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  if (stmt == NULL) {
    return SQLITE_MISUSE;
  }
  return sqlite3_bind_double(stmt, (int)index, value);
}

CAMLprim value ox_sqlite_bind_float_bc(value v_stmt, value v_index, value v_value)
{
  return Val_int(ox_sqlite_bind_float(v_stmt, Int_val(v_index), Double_val(v_value)));
}

CAMLprim intnat ox_sqlite_bind_blob(value v_stmt, intnat index, value v_blob)
{
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  int len;
  int rc;
  if (stmt == NULL) {
    return SQLITE_MISUSE;
  }
  rc = ox_sqlite_ocaml_string_len_as_int(v_blob, &len);
  if (rc != SQLITE_OK) {
    return rc;
  }
  return sqlite3_bind_blob(
    stmt,
    (int)index,
    Bytes_val(v_blob),
    len,
    SQLITE_TRANSIENT);
}

CAMLprim value ox_sqlite_bind_blob_bc(value v_stmt, value v_index, value v_blob)
{
  return Val_int(ox_sqlite_bind_blob(v_stmt, Int_val(v_index), v_blob));
}

CAMLprim intnat ox_sqlite_bind_zeroblob(value v_stmt, intnat index, intnat size)
{
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  if (stmt == NULL) {
    return SQLITE_MISUSE;
  }
  return sqlite3_bind_zeroblob(stmt, (int)index, (int)size);
}

CAMLprim value ox_sqlite_bind_zeroblob_bc(value v_stmt, value v_index, value v_size)
{
  return Val_int(ox_sqlite_bind_zeroblob(v_stmt, Int_val(v_index), Int_val(v_size)));
}

/* TEST-ONLY seam: a tagged step waits until the real interrupt call has
   completed, forcing cancellation into SQLite's otherwise unobservable gap. */
static _Atomic int ox_sqlite_test_step_state = 0;

CAMLprim value ox_sqlite_test_step_arm(value unit)
{
  (void)unit;
  atomic_store(&ox_sqlite_test_step_state, 1);
  return Val_unit;
}

CAMLprim value ox_sqlite_test_step_state_get(value unit)
{
  (void)unit;
  return Val_int(atomic_load(&ox_sqlite_test_step_state));
}

CAMLprim value ox_sqlite_test_step_release(value unit)
{
  (void)unit;
  pthread_mutex_lock(&ox_sqlite_test_mu);
  atomic_store(&ox_sqlite_test_step_state, 0);
  pthread_cond_broadcast(&ox_sqlite_test_cond);
  pthread_mutex_unlock(&ox_sqlite_test_mu);
  return Val_unit;
}

static void ox_sqlite_test_before_step(sqlite3_stmt *stmt)
{
  if (atomic_load(&ox_sqlite_test_step_state) == 0) return;
  if (strstr(sqlite3_sql(stmt), "ox-test-interrupt-before-step") == NULL) return;
  pthread_mutex_lock(&ox_sqlite_test_mu);
  if (atomic_load(&ox_sqlite_test_step_state) == 1) {
    atomic_store(&ox_sqlite_test_step_state, 2);
    while (atomic_load(&ox_sqlite_test_step_state) == 2)
      pthread_cond_wait(&ox_sqlite_test_cond, &ox_sqlite_test_mu);
  }
  pthread_mutex_unlock(&ox_sqlite_test_mu);
}

CAMLprim intnat ox_sqlite_step(value v_db, value v_stmt)
{
  CAMLparam2(v_db, v_stmt);
  ox_sqlite_db_state *slot = ox_sqlite_db_state_val(v_db);
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  int rc;
  if (stmt == NULL || slot == NULL || slot->db == NULL) {
    CAMLreturnT(intnat, SQLITE_MISUSE);
  }
  caml_enter_blocking_section();
  ox_sqlite_test_before_step(stmt);
  rc = ox_sqlite_cancelled_at_entry(slot) ? SQLITE_INTERRUPT : sqlite3_step(stmt);
  caml_leave_blocking_section();
  CAMLreturnT(intnat, rc);
}

CAMLprim value ox_sqlite_step_bc(value v_db, value v_stmt)
{
  return Val_int(ox_sqlite_step(v_db, v_stmt));
}

CAMLprim int64_t ox_sqlite_column_int64(value v_stmt, intnat index)
{
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  if (stmt == NULL) {
    return 0;
  }
  return sqlite3_column_int64(stmt, (int)index);
}

CAMLprim value ox_sqlite_column_int64_bc(value v_stmt, value v_index)
{
  return caml_copy_int64(ox_sqlite_column_int64(v_stmt, Int_val(v_index)));
}

CAMLprim intnat ox_sqlite_column_int(value v_stmt, intnat index)
{
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  if (stmt == NULL) {
    return 0;
  }
  return (intnat)sqlite3_column_int64(stmt, (int)index);
}

CAMLprim value ox_sqlite_column_int_bc(value v_stmt, value v_index)
{
  return Val_int(ox_sqlite_column_int(v_stmt, Int_val(v_index)));
}

CAMLprim value ox_sqlite_column_text(value v_stmt, intnat index)
{
  CAMLparam1(v_stmt);
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  sqlite3 *db;
  const unsigned char *text;
  int kind;
  int len;
  if (stmt == NULL) {
    caml_failwith("sqlite column_text: statement is finalized");
  }
  db = sqlite3_db_handle(stmt);
  kind = sqlite3_column_type(stmt, (int)index);
  if (kind == SQLITE_NULL) CAMLreturn(caml_copy_string(""));
  text = sqlite3_column_text(stmt, (int)index);
  if (text == NULL && sqlite3_errcode(db) == SQLITE_NOMEM)
    caml_failwith("sqlite column_text: out of memory");
  if (text == NULL)
    caml_failwith("sqlite column_text: null pointer for non-null value");
  len = sqlite3_column_bytes(stmt, (int)index);
  if (len < 0) caml_failwith("sqlite column_text: negative length");
  /* SQLite returns NULL for SQL NULL and for OOM during type conversion.
     SQL NULL is handled above; a NULL pointer here must not become "". */
  CAMLreturn(caml_alloc_initialized_string(len, (const char *)text));
}

CAMLprim value ox_sqlite_column_text_bc(value v_stmt, value v_index)
{
  return ox_sqlite_column_text(v_stmt, Int_val(v_index));
}

CAMLprim double ox_sqlite_column_float(value v_stmt, intnat index)
{
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  if (stmt == NULL) {
    return 0.0;
  }
  return sqlite3_column_double(stmt, (int)index);
}

CAMLprim value ox_sqlite_column_float_bc(value v_stmt, value v_index)
{
  return caml_copy_double(ox_sqlite_column_float(v_stmt, Int_val(v_index)));
}

CAMLprim value ox_sqlite_column_blob(value v_stmt, intnat index)
{
  CAMLparam1(v_stmt);
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  const void *blob;
  int len;
  if (stmt == NULL) {
    caml_failwith("sqlite column_blob: statement is finalized");
  }
  blob = sqlite3_column_blob(stmt, (int)index);
  len = sqlite3_column_bytes(stmt, (int)index);
  if (len < 0) caml_failwith("sqlite column_blob: negative length");
  if (len > 0 && blob == NULL) caml_failwith("sqlite column_blob: null pointer for non-empty value");
  CAMLreturn(caml_alloc_initialized_string(len, len == 0 ? "" : (const char *)blob));
}

CAMLprim value ox_sqlite_column_blob_bc(value v_stmt, value v_index)
{
  return ox_sqlite_column_blob(v_stmt, Int_val(v_index));
}

CAMLprim value ox_sqlite_column_is_null(value v_stmt, intnat index)
{
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  if (stmt == NULL) {
    return Val_true;
  }
  return Val_bool(sqlite3_column_type(stmt, (int)index) == SQLITE_NULL);
}

CAMLprim value ox_sqlite_column_is_null_bc(value v_stmt, value v_index)
{
  return ox_sqlite_column_is_null(v_stmt, Int_val(v_index));
}

CAMLprim intnat ox_sqlite_column_count(value v_stmt)
{
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  if (stmt == NULL) {
    return 0;
  }
  return sqlite3_column_count(stmt);
}

CAMLprim value ox_sqlite_column_count_bc(value v_stmt)
{
  return Val_int(ox_sqlite_column_count(v_stmt));
}

CAMLprim value ox_sqlite_column_name(value v_stmt, intnat index)
{
  CAMLparam1(v_stmt);
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  const char *name;
  if (stmt == NULL) {
    caml_failwith("sqlite column_name: statement is finalized");
  }
  name = sqlite3_column_name(stmt, (int)index);
  CAMLreturn(caml_copy_string(name == NULL ? "" : name));
}

CAMLprim value ox_sqlite_column_name_bc(value v_stmt, value v_index)
{
  return ox_sqlite_column_name(v_stmt, Int_val(v_index));
}

CAMLprim intnat ox_sqlite_column_type_code(value v_stmt, intnat index)
{
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  if (stmt == NULL) {
    return SQLITE_NULL;
  }
  return sqlite3_column_type(stmt, (int)index);
}

CAMLprim value ox_sqlite_column_type_code_bc(value v_stmt, value v_index)
{
  return Val_int(ox_sqlite_column_type_code(v_stmt, Int_val(v_index)));
}

CAMLprim intnat ox_sqlite_data_count(value v_stmt)
{
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  if (stmt == NULL) {
    return 0;
  }
  return sqlite3_data_count(stmt);
}

CAMLprim value ox_sqlite_data_count_bc(value v_stmt)
{
  return Val_int(ox_sqlite_data_count(v_stmt));
}

CAMLprim value ox_sqlite_statement_sql(value v_stmt)
{
  CAMLparam1(v_stmt);
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  const char *sql;
  if (stmt == NULL) {
    caml_failwith("sqlite statement_sql: statement is finalized");
  }
  sql = sqlite3_sql(stmt);
  CAMLreturn(caml_copy_string(sql == NULL ? "" : sql));
}

CAMLprim value ox_sqlite_expanded_sql(value v_stmt)
{
  CAMLparam1(v_stmt);
  CAMLlocal2(result, owner);
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  char *sql;
  if (stmt == NULL) {
    caml_failwith("sqlite expanded_sql: statement is finalized");
  }
  owner = sqlite_string_owner_alloc();
  sql = sqlite3_expanded_sql(stmt);
  sqlite_string_owner_set(owner, sql);
  result = caml_copy_string(sql == NULL ? "" : sql);
  sqlite_string_owner_release(owner);
  CAMLreturn(result);
}

CAMLprim value ox_sqlite_statement_readonly(value v_stmt)
{
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  if (stmt == NULL) {
    return Val_false;
  }
  return Val_bool(sqlite3_stmt_readonly(stmt));
}

CAMLprim value ox_sqlite_statement_readonly_bc(value v_stmt)
{
  return ox_sqlite_statement_readonly(v_stmt);
}

CAMLprim value ox_sqlite_statement_busy(value v_stmt)
{
  sqlite3_stmt *stmt = ox_sqlite_stmt_val(v_stmt);
  if (stmt == NULL) {
    return Val_false;
  }
  return Val_bool(sqlite3_stmt_busy(stmt));
}

CAMLprim value ox_sqlite_statement_busy_bc(value v_stmt)
{
  return ox_sqlite_statement_busy(v_stmt);
}

CAMLprim intnat ox_sqlite_changes(value v_db)
{
  sqlite3 *db = ox_sqlite_db_val(v_db);
  if (db == NULL) {
    return 0;
  }
  return sqlite3_changes(db);
}

CAMLprim value ox_sqlite_changes_bc(value v_db)
{
  return Val_int(ox_sqlite_changes(v_db));
}

CAMLprim intnat ox_sqlite_total_changes(value v_db)
{
  sqlite3 *db = ox_sqlite_db_val(v_db);
  if (db == NULL) {
    return 0;
  }
  return sqlite3_total_changes(db);
}

CAMLprim value ox_sqlite_total_changes_bc(value v_db)
{
  return Val_int(ox_sqlite_total_changes(v_db));
}

CAMLprim int64_t ox_sqlite_last_insert_rowid(value v_db)
{
  sqlite3 *db = ox_sqlite_db_val(v_db);
  if (db == NULL) {
    return 0;
  }
  return sqlite3_last_insert_rowid(db);
}

CAMLprim value ox_sqlite_last_insert_rowid_bc(value v_db)
{
  return caml_copy_int64(ox_sqlite_last_insert_rowid(v_db));
}

CAMLprim intnat ox_sqlite_error_code(value v_db)
{
  sqlite3 *db = ox_sqlite_db_val(v_db);
  if (db == NULL) {
    return SQLITE_MISUSE;
  }
  return sqlite3_errcode(db);
}

CAMLprim value ox_sqlite_error_code_bc(value v_db)
{
  return Val_int(ox_sqlite_error_code(v_db));
}

CAMLprim intnat ox_sqlite_extended_error_code(value v_db)
{
  sqlite3 *db = ox_sqlite_db_val(v_db);
  if (db == NULL) {
    return SQLITE_MISUSE;
  }
  return sqlite3_extended_errcode(db);
}

CAMLprim value ox_sqlite_extended_error_code_bc(value v_db)
{
  return Val_int(ox_sqlite_extended_error_code(v_db));
}

CAMLprim value ox_sqlite_error_message(value v_db)
{
  CAMLparam1(v_db);
  sqlite3 *db = ox_sqlite_db_val(v_db);
  if (db == NULL) {
    CAMLreturn(caml_copy_string("database is closed"));
  }
  CAMLreturn(caml_copy_string(sqlite3_errmsg(db)));
}

CAMLprim value ox_sqlite_autocommit(value v_db)
{
  sqlite3 *db = ox_sqlite_db_val(v_db);
  if (db == NULL) {
    return Val_true;
  }
  return Val_bool(sqlite3_get_autocommit(db));
}

CAMLprim value ox_sqlite_autocommit_bc(value v_db)
{
  return ox_sqlite_autocommit(v_db);
}

CAMLprim value ox_sqlite_database_readonly(value v_db, value v_name)
{
  sqlite3 *db = ox_sqlite_db_val(v_db);
  int rc;
  if (db == NULL) {
    return Val_false;
  }
  rc = sqlite3_db_readonly(db, String_val(v_name));
  return Val_bool(rc > 0);
}

CAMLprim value ox_sqlite_database_readonly_bc(value v_db, value v_name)
{
  return ox_sqlite_database_readonly(v_db, v_name);
}

CAMLprim value ox_sqlite_interrupt(value v_db)
{
  ox_sqlite_db_state *slot = ox_sqlite_db_state_val(v_db);
  sqlite3 *db;
  if (slot == NULL) {
    return Val_unit;
  }
  /* TEST-ONLY handshake: signal arrival before attempting the slot mutex.
     The test mutex is released first, so this never nests test->slot. */
  pthread_mutex_lock(&ox_sqlite_test_mu);
  if (ox_sqlite_test_state == 2) {
    ox_sqlite_test_state = 3;
    pthread_cond_broadcast(&ox_sqlite_test_cond);
  }
  pthread_mutex_unlock(&ox_sqlite_test_mu);
  pthread_mutex_lock(&slot->mutex);
  db = slot->db;
  if (db != NULL) {
    sqlite3_interrupt(db);
  }
  pthread_mutex_unlock(&slot->mutex);
  if (atomic_load(&ox_sqlite_test_step_state) != 0) {
    pthread_mutex_lock(&ox_sqlite_test_mu);
    atomic_store(&ox_sqlite_test_step_state, 3);
    pthread_cond_broadcast(&ox_sqlite_test_cond);
    pthread_mutex_unlock(&ox_sqlite_test_mu);
  }
  return Val_unit;
}

CAMLprim value ox_sqlite_is_interrupted(value v_db)
{
  ox_sqlite_db_state *slot = ox_sqlite_db_state_val(v_db);
  sqlite3 *db;
  value result;
  if (slot == NULL) {
    return Val_false;
  }
  pthread_mutex_lock(&slot->mutex);
  db = slot->db;
  if (db == NULL) {
    pthread_mutex_unlock(&slot->mutex);
    return Val_false;
  }
  result = Val_bool(sqlite3_is_interrupted(db));
  pthread_mutex_unlock(&slot->mutex);
  return result;
}

CAMLprim value ox_sqlite_is_interrupted_bc(value v_db)
{
  return ox_sqlite_is_interrupted(v_db);
}

CAMLprim value ox_sqlite_complete(value v_sql)
{
  return Val_bool(sqlite3_complete(String_val(v_sql)));
}

CAMLprim value ox_sqlite_complete_bc(value v_sql)
{
  return ox_sqlite_complete(v_sql);
}

CAMLprim intnat ox_sqlite_enable_load_extension(value v_db, value v_on)
{
  sqlite3 *db = ox_sqlite_db_val(v_db);
  if (db == NULL) {
    return SQLITE_MISUSE;
  }
  return sqlite3_enable_load_extension(db, Bool_val(v_on));
}

CAMLprim value ox_sqlite_enable_load_extension_bc(value v_db, value v_on)
{
  return Val_int(ox_sqlite_enable_load_extension(v_db, v_on));
}

CAMLprim intnat ox_sqlite_load_extension(value v_db, value v_path)
{
  CAMLparam2(v_db, v_path);
  sqlite3 *db = ox_sqlite_db_val(v_db);
  char *path;
  char *errmsg = NULL;
  int rc;
  if (db == NULL) {
    CAMLreturnT(intnat, SQLITE_MISUSE);
  }
  path = ox_sqlite_copy_ocaml_string(v_path, NULL);
  if (path == NULL) {
    CAMLreturnT(intnat, SQLITE_NOMEM);
  }
  caml_enter_blocking_section();
  rc = sqlite3_load_extension(db, path, NULL, &errmsg);
  caml_leave_blocking_section();
  free(path);
  if (errmsg != NULL) {
    sqlite3_free(errmsg);
  }
  CAMLreturnT(intnat, rc);
}

CAMLprim value ox_sqlite_load_extension_bc(value v_db, value v_path)
{
  return Val_int(ox_sqlite_load_extension(v_db, v_path));
}

static int ox_sqlite_backup_between(sqlite3 *dst, sqlite3 *src)
{
  sqlite3_backup *backup = sqlite3_backup_init(dst, "main", src, "main");
  int rc;
  if (backup == NULL) {
    return sqlite3_errcode(dst);
  }
  do {
    rc = sqlite3_backup_step(backup, 128);
    if (rc == SQLITE_BUSY || rc == SQLITE_LOCKED) {
      (void)sqlite3_sleep(1);
    }
  } while (rc == SQLITE_OK || rc == SQLITE_BUSY || rc == SQLITE_LOCKED);
  if (rc == SQLITE_DONE) {
    rc = SQLITE_OK;
  }
  {
    int finish_rc = sqlite3_backup_finish(backup);
    if (rc == SQLITE_OK && finish_rc != SQLITE_OK) {
      rc = finish_rc;
    }
  }
  return rc;
}

CAMLprim intnat ox_sqlite_backup_to_path(value v_db, value v_path)
{
  CAMLparam2(v_db, v_path);
  sqlite3 *src = ox_sqlite_db_val(v_db);
  sqlite3 *dst = NULL;
  char *path;
  int rc;
  if (src == NULL) {
    CAMLreturnT(intnat, SQLITE_MISUSE);
  }
  path = ox_sqlite_copy_ocaml_string(v_path, NULL);
  if (path == NULL) {
    CAMLreturnT(intnat, SQLITE_NOMEM);
  }
  caml_enter_blocking_section();
  rc = sqlite3_open_v2(path, &dst, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_URI, NULL);
  if (rc != SQLITE_OK) {
    if (dst != NULL) {
      (void)sqlite3_close_v2(dst);
    }
    caml_leave_blocking_section();
    free(path);
    CAMLreturnT(intnat, rc);
  }
  rc = ox_sqlite_backup_between(dst, src);
  (void)sqlite3_close_v2(dst);
  caml_leave_blocking_section();
  free(path);
  CAMLreturnT(intnat, rc);
}

CAMLprim value ox_sqlite_backup_to_path_bc(value v_db, value v_path)
{
  return Val_int(ox_sqlite_backup_to_path(v_db, v_path));
}

CAMLprim intnat ox_sqlite_restore_from_path(value v_db, value v_path)
{
  CAMLparam2(v_db, v_path);
  sqlite3 *dst = ox_sqlite_db_val(v_db);
  sqlite3 *src = NULL;
  char *path;
  int rc;
  if (dst == NULL) {
    CAMLreturnT(intnat, SQLITE_MISUSE);
  }
  path = ox_sqlite_copy_ocaml_string(v_path, NULL);
  if (path == NULL) {
    CAMLreturnT(intnat, SQLITE_NOMEM);
  }
  caml_enter_blocking_section();
  rc = sqlite3_open_v2(path, &src, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, NULL);
  if (rc != SQLITE_OK) {
    if (src != NULL) {
      (void)sqlite3_close_v2(src);
    }
    caml_leave_blocking_section();
    free(path);
    CAMLreturnT(intnat, rc);
  }
  rc = ox_sqlite_backup_between(dst, src);
  (void)sqlite3_close_v2(src);
  caml_leave_blocking_section();
  free(path);
  CAMLreturnT(intnat, rc);
}

CAMLprim value ox_sqlite_restore_from_path_bc(value v_db, value v_path)
{
  return Val_int(ox_sqlite_restore_from_path(v_db, v_path));
}
