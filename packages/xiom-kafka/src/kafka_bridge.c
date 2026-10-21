/* XIOM -- xiom.kafka: librdkafka runtime bridge.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * DESIGN: no link-time dependency.  The bridge resolves librdkafka at
 * RUNTIME (LoadLibraryA on Windows, dlopen on POSIX), verifies the declared
 * export set, and exposes a flat extern "C" surface to module xiom.kafka.
 * When the library is absent every entry point reports a typed ABSENT
 * classification and the suite SKIPs; a present but broken install is ABI
 * (FAIL), never a silent SKIP.
 *
 * Upstream pin: librdkafka v2.16.0, commit
 * c6c9973cf1b25394c58e0cade13a36f386856f77 (PROVENANCE.md).  The ABI facts
 * encoded below (rd_kafka_message_t head layout at that commit, the
 * producev-era stable message head, the metadata struct field order and
 * the mock-cluster API) come from src/rdkafka.h and src/rdkafka_mock.h at
 * the pin.
 *
 * Threading: the delivery-report callback is served from I app calls
 * (rd_kafka_poll / rd_kafka_flush), never from a librdkafka thread, so the
 * report ring needs no lock.  XIOM call sites are single-threaded.
 *
 * Pointers never cross into XIOM: handles are int64, copy-out happens in
 * this file, and every foreign struct read is confined here (G5).
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
typedef HMODULE xkd_lib_t;
static xkd_lib_t xkd_dlopen(const char *name) { return LoadLibraryA(name); }
static void *xkd_dlsym(xkd_lib_t h, const char *name) {
    return h ? (void *)GetProcAddress(h, name) : 0;
}
static void xkd_dlclose(xkd_lib_t h) { if (h) FreeLibrary(h); }
static void xkd_dlerror(char *buf, size_t cap) {
    DWORD e = GetLastError();
    snprintf(buf, cap, "win32 error %lu", (unsigned long)e);
}
#else
#include <dlfcn.h>
typedef void *xkd_lib_t;
static xkd_lib_t xkd_dlopen(const char *name) { return dlopen(name, RTLD_NOW | RTLD_LOCAL); }
static void *xkd_dlsym(xkd_lib_t h, const char *name) { return h ? dlsym(h, name) : 0; }
static void xkd_dlclose(xkd_lib_t h) { if (h) dlclose(h); }
static void xkd_dlerror(char *buf, size_t cap) {
    const char *e = dlerror();
    snprintf(buf, cap, "%s", e ? e : "unknown dlopen error");
}
#endif

/* -- pinned public types (src/rdkafka.h @ v2.16.0) ----------------------- */

typedef int32_t rd_kafka_resp_err_t;
typedef int rd_kafka_conf_res_t;
typedef struct rd_kafka_s rd_kafka_t;
typedef struct rd_kafka_conf_s rd_kafka_conf_t;
typedef struct rd_kafka_topic_s rd_kafka_topic_t;
typedef struct rd_kafka_topic_partition_list_s rd_kafka_topic_partition_list_t;
typedef struct rd_kafka_message_s rd_kafka_message_t;
typedef struct rd_kafka_metadata_s rd_kafka_metadata_t;
typedef struct rd_kafka_queue_s rd_kafka_queue_t;
typedef struct rd_kafka_event_s rd_kafka_event_t;
typedef struct rd_kafka_NewTopic_s rd_kafka_NewTopic_t;
typedef struct rd_kafka_DeleteTopic_s rd_kafka_DeleteTopic_t;
typedef struct rd_kafka_topic_result_s rd_kafka_topic_result_t;
typedef struct rd_kafka_AdminOptions_s rd_kafka_AdminOptions_t;
typedef struct rd_kafka_error_s rd_kafka_error_t;
typedef struct rd_kafka_mock_cluster_s rd_kafka_mock_cluster_t;

/* Public head layout of rd_kafka_message_t (rdkafka.h:1508-1538).  v2.16
 * moved timestamp/timestamp_type out of the struct into
 * rd_kafka_message_timestamp(), so only this stable head is encoded. */
typedef struct xkd_message_s {
    int32_t err;        /* @0  */
    void *rkt;          /* @8  */
    int32_t partition;  /* @16 */
    void *payload;      /* @24 */
    size_t len;         /* @32 */
    void *key;          /* @40 */
    size_t key_len;     /* @48 */
    int64_t offset;     /* @56 */
    void *_private;     /* @64 */
} xkd_message_t;

/* Metadata structs (rdkafka.h:6143-6185): the field order is the pinned
 * public ABI and is stable across v2.x. */
typedef struct xkd_metadata_broker_s {
    int32_t id;
    char *host;
    int port;
} xkd_metadata_broker_t;

typedef struct xkd_metadata_partition_s {
    int32_t id;
    int32_t err;
    int32_t leader;
    int replica_cnt;
    int32_t *replicas;
    int isr_cnt;
    int32_t *isrs;
} xkd_metadata_partition_t;

typedef struct xkd_metadata_topic_s {
    char *topic;
    int partition_cnt;
    xkd_metadata_partition_t *partitions;
    int32_t err;
} xkd_metadata_topic_t;

struct rd_kafka_metadata_s {
    int broker_cnt;
    xkd_metadata_broker_t *brokers;
    int topic_cnt;
    xkd_metadata_topic_t *topics;
    int32_t orig_broker_id;
    char *orig_broker_name;
};

/* -- pinned constants ---------------------------------------------------- */

#define XKD_PRODUCER 0
#define XKD_CONSUMER 1
#define XKD_MSG_F_COPY 0x2
#define XKD_OFFSET_BEGINNING (-2)
#define XKD_OFFSET_END (-1)
#define XKD_OFFSET_STORED (-1000)
#define XKD_OFFSET_INVALID (-1001)
#define XKD_ADMIN_OP_CREATETOPICS 1
#define XKD_ADMIN_OP_DELETETOPICS 2
#define XKD_E_INVALID_ARG (-186)
#define XKD_E_TIMED_OUT (-185)
#define XKD_E_UNSUPPORTED (-165)
#define XKD_E_STATE (-172)

/* -- resolved entry points ----------------------------------------------- */

typedef void (*xkd_dr_cb_t)(rd_kafka_t *, const rd_kafka_message_t *, void *);
typedef void (*xkd_dr_set_t)(rd_kafka_conf_t *, xkd_dr_cb_t);

typedef struct xkd_api_s {
    int (*version)(void);
    const char *(*version_str)(void);
    const char *(*err2str)(rd_kafka_resp_err_t);
    const char *(*err2name)(rd_kafka_resp_err_t);
    rd_kafka_resp_err_t (*last_error)(void);

    rd_kafka_conf_t *(*conf_new)(void);
    void (*conf_destroy)(rd_kafka_conf_t *);
    rd_kafka_conf_res_t (*conf_set)(rd_kafka_conf_t *, const char *,
                                    const char *, char *, size_t);
    rd_kafka_conf_res_t (*conf_get)(const rd_kafka_conf_t *, const char *,
                                    char *, size_t *);
    xkd_dr_set_t conf_set_dr_msg_cb;
    void (*conf_set_opaque)(rd_kafka_conf_t *, void *);

    rd_kafka_t *(*new_client)(int, rd_kafka_conf_t *, char *, size_t);
    void (*client_destroy)(rd_kafka_t *);
    const char *(*client_name)(const rd_kafka_t *);
    int (*poll)(rd_kafka_t *, int);
    int (*outq_len)(rd_kafka_t *);
    rd_kafka_resp_err_t (*flush)(rd_kafka_t *, int);
    char *(*clusterid)(rd_kafka_t *, int);
    void (*mem_free)(rd_kafka_t *, void *);

    rd_kafka_topic_t *(*topic_new)(rd_kafka_t *, const char *, rd_kafka_conf_t *);
    void (*topic_destroy)(rd_kafka_topic_t *);
    const char *(*topic_name)(const rd_kafka_topic_t *);
    int (*produce)(rd_kafka_topic_t *, int32_t, int, void *, size_t,
                   const void *, size_t, void *);

    rd_kafka_topic_partition_list_t *(*tpl_new)(int);
    void (*tpl_destroy)(rd_kafka_topic_partition_list_t *);
    void *(*tpl_add)(rd_kafka_topic_partition_list_t *, const char *, int32_t);
    rd_kafka_resp_err_t (*tpl_set_offset)(rd_kafka_topic_partition_list_t *,
                                          const char *, int32_t, int64_t);

    rd_kafka_resp_err_t (*subscribe)(rd_kafka_t *,
                                     const rd_kafka_topic_partition_list_t *);
    rd_kafka_resp_err_t (*assign)(rd_kafka_t *,
                                  const rd_kafka_topic_partition_list_t *);
    rd_kafka_resp_err_t (*unsubscribe)(rd_kafka_t *);
    rd_kafka_message_t *(*consumer_poll)(rd_kafka_t *, int);
    void (*message_destroy)(rd_kafka_message_t *);
    int64_t (*message_timestamp)(const rd_kafka_message_t *, int *);
    const char *(*message_errstr)(const rd_kafka_message_t *);
    rd_kafka_resp_err_t (*commit)(rd_kafka_t *,
                                  const rd_kafka_topic_partition_list_t *, int);
    rd_kafka_resp_err_t (*consumer_close)(rd_kafka_t *);

    rd_kafka_resp_err_t (*metadata)(rd_kafka_t *, int, rd_kafka_topic_t *,
                                    const rd_kafka_metadata_t **, int);
    void (*metadata_destroy)(const rd_kafka_metadata_t *);

    rd_kafka_error_t *(*init_transactions)(rd_kafka_t *, int);
    rd_kafka_error_t *(*begin_transaction)(rd_kafka_t *);
    rd_kafka_error_t *(*commit_transaction)(rd_kafka_t *, int);
    rd_kafka_error_t *(*abort_transaction)(rd_kafka_t *, int);
    void (*error_destroy)(rd_kafka_error_t *);
    rd_kafka_resp_err_t (*error_code)(const rd_kafka_error_t *);
    const char *(*error_string)(const rd_kafka_error_t *);
    int (*error_is_retriable)(const rd_kafka_error_t *);
    int (*error_is_fatal)(const rd_kafka_error_t *);

    rd_kafka_queue_t *(*queue_new)(rd_kafka_t *);
    void (*queue_destroy)(rd_kafka_queue_t *);
    rd_kafka_event_t *(*queue_poll)(rd_kafka_queue_t *, int);
    void (*event_destroy)(rd_kafka_event_t *);
    int (*event_type)(const rd_kafka_event_t *);
    rd_kafka_resp_err_t (*event_error)(const rd_kafka_event_t *);
    const char *(*event_error_string)(const rd_kafka_event_t *);

    const rd_kafka_topic_result_t **(*create_topics_result)(
        const rd_kafka_event_t *, size_t *);
    const rd_kafka_topic_result_t **(*delete_topics_result)(
        const rd_kafka_event_t *, size_t *);
    rd_kafka_resp_err_t (*topic_result_error)(const rd_kafka_topic_result_t *);
    const char *(*topic_result_error_string)(const rd_kafka_topic_result_t *);
    const char *(*topic_result_name)(const rd_kafka_topic_result_t *);

    rd_kafka_NewTopic_t *(*new_topic_new)(const char *, int, int, char *, size_t);
    void (*new_topic_destroy)(rd_kafka_NewTopic_t *);
    rd_kafka_DeleteTopic_t *(*delete_topic_new)(const char *);
    void (*delete_topic_destroy)(rd_kafka_DeleteTopic_t *);
    void (*create_topics)(rd_kafka_t *, rd_kafka_NewTopic_t **, size_t,
                          const rd_kafka_AdminOptions_t *, rd_kafka_queue_t *);
    void (*delete_topics)(rd_kafka_t *, rd_kafka_DeleteTopic_t **, size_t,
                          const rd_kafka_AdminOptions_t *, rd_kafka_queue_t *);
    rd_kafka_AdminOptions_t *(*admin_options_new)(rd_kafka_t *, int);
    void (*admin_options_destroy)(rd_kafka_AdminOptions_t *);
    rd_kafka_resp_err_t (*admin_options_timeout)(rd_kafka_AdminOptions_t *, int,
                                                 char *, size_t);

    rd_kafka_mock_cluster_t *(*mock_cluster_new)(rd_kafka_t *, int);
    void (*mock_cluster_destroy)(rd_kafka_mock_cluster_t *);
    const char *(*mock_bootstraps)(const rd_kafka_mock_cluster_t *);
    rd_kafka_resp_err_t (*mock_topic_create)(rd_kafka_mock_cluster_t *,
                                             const char *, int, int);
    void (*mock_set_controller)(rd_kafka_mock_cluster_t *, int32_t);
} xkd_api;

static xkd_api A;
static xkd_lib_t g_lib = 0;
static char g_soname[256];
static char g_error[1024];
static char g_missing[3072];
static int g_missing_count = 0;
static int g_required_missing = 0;
static int g_mock_ok = 0;
static int32_t g_last_err = 0;

void xkd_unload(void);
int32_t xkd_topic_list_add_at(int64_t tpl, const char *topic, int32_t partition,
                              int64_t offset);

/* -- small helpers ------------------------------------------------------- */

static void xkd_set_error(const char *msg) {
    snprintf(g_error, sizeof(g_error), "%s", msg ? msg : "");
}

static int32_t xkd_copy_str(const char *s, char *dest, int64_t cap) {
    size_t n;
    if (!s) {
        if (dest && cap > 0) dest[0] = 0;
        return 0;
    }
    n = strlen(s);
    if (dest && cap > 0) {
        size_t c = (n < (size_t)(cap - 1)) ? n : (size_t)(cap - 1);
        memcpy(dest, s, c);
        dest[c] = 0;
    }
    return (int32_t)n;
}

static void xkd_missing_add(const char *name, int required) {
    size_t used = strlen(g_missing);
    size_t left = sizeof(g_missing) - used;
    if (g_missing_count > 0 && left > 1) {
        strncat(g_missing, ",", left - 1);
        left = sizeof(g_missing) - strlen(g_missing);
    }
    if (left > 1) strncat(g_missing, name, left - 1);
    g_missing_count++;
    if (required) g_required_missing++;
}

#define XKD_REQ(field, sym)                                                     \
    do {                                                                        \
        A.field = (void *)xkd_dlsym(g_lib, sym);                                \
        if (!A.field) xkd_missing_add(sym, 1);                                  \
    } while (0)

#define XKD_OPT(field, sym)                                                     \
    do {                                                                        \
        A.field = (void *)xkd_dlsym(g_lib, sym);                                \
        if (!A.field) xkd_missing_add(sym, 0);                                  \
    } while (0)

static void xkd_clear_api(void) { memset(&A, 0, sizeof(A)); }
static void xkd_reset_scan(void) {
    g_missing[0] = 0;
    g_missing_count = 0;
    g_required_missing = 0;
    g_mock_ok = 0;
}

/* -- loader -------------------------------------------------------------- */

int32_t xkd_load_named(const char *soname) {
    char detail[256];
    if (!soname || !soname[0]) {
        xkd_set_error("soname must not be empty");
        return 1;
    }
    xkd_unload();
    xkd_reset_scan();
    g_lib = xkd_dlopen(soname);
    if (!g_lib) {
        xkd_dlerror(detail, sizeof(detail));
        snprintf(g_error, sizeof(g_error), "%s: %s", soname, detail);
        return 1; /* ABSENT */
    }
    snprintf(g_soname, sizeof(g_soname), "%s", soname);

    XKD_REQ(version, "rd_kafka_version");
    XKD_REQ(version_str, "rd_kafka_version_str");
    XKD_REQ(err2str, "rd_kafka_err2str");
    XKD_REQ(err2name, "rd_kafka_err2name");
    XKD_REQ(last_error, "rd_kafka_last_error");
    XKD_REQ(conf_new, "rd_kafka_conf_new");
    XKD_REQ(conf_destroy, "rd_kafka_conf_destroy");
    XKD_REQ(conf_set, "rd_kafka_conf_set");
    XKD_REQ(conf_get, "rd_kafka_conf_get");
    XKD_REQ(conf_set_dr_msg_cb, "rd_kafka_conf_set_dr_msg_cb");
    XKD_REQ(conf_set_opaque, "rd_kafka_conf_set_opaque");
    XKD_REQ(new_client, "rd_kafka_new");
    XKD_REQ(client_destroy, "rd_kafka_destroy");
    XKD_REQ(client_name, "rd_kafka_name");
    XKD_REQ(poll, "rd_kafka_poll");
    XKD_REQ(outq_len, "rd_kafka_outq_len");
    XKD_REQ(flush, "rd_kafka_flush");
    XKD_REQ(clusterid, "rd_kafka_clusterid");
    XKD_REQ(mem_free, "rd_kafka_mem_free");
    XKD_REQ(topic_new, "rd_kafka_topic_new");
    XKD_REQ(topic_destroy, "rd_kafka_topic_destroy");
    XKD_REQ(topic_name, "rd_kafka_topic_name");
    XKD_REQ(produce, "rd_kafka_produce");
    XKD_REQ(tpl_new, "rd_kafka_topic_partition_list_new");
    XKD_REQ(tpl_destroy, "rd_kafka_topic_partition_list_destroy");
    XKD_REQ(tpl_add, "rd_kafka_topic_partition_list_add");
    XKD_REQ(tpl_set_offset, "rd_kafka_topic_partition_list_set_offset");
    XKD_REQ(subscribe, "rd_kafka_subscribe");
    XKD_REQ(assign, "rd_kafka_assign");
    XKD_REQ(unsubscribe, "rd_kafka_unsubscribe");
    XKD_REQ(consumer_poll, "rd_kafka_consumer_poll");
    XKD_REQ(message_destroy, "rd_kafka_message_destroy");
    XKD_REQ(message_timestamp, "rd_kafka_message_timestamp");
    XKD_REQ(message_errstr, "rd_kafka_message_errstr");
    XKD_REQ(commit, "rd_kafka_commit");
    XKD_REQ(consumer_close, "rd_kafka_consumer_close");
    XKD_REQ(metadata, "rd_kafka_metadata");
    XKD_REQ(metadata_destroy, "rd_kafka_metadata_destroy");
    XKD_REQ(init_transactions, "rd_kafka_init_transactions");
    XKD_REQ(begin_transaction, "rd_kafka_begin_transaction");
    XKD_REQ(commit_transaction, "rd_kafka_commit_transaction");
    XKD_REQ(abort_transaction, "rd_kafka_abort_transaction");
    XKD_REQ(error_destroy, "rd_kafka_error_destroy");
    XKD_REQ(error_code, "rd_kafka_error_code");
    XKD_REQ(error_string, "rd_kafka_error_string");
    XKD_REQ(error_is_retriable, "rd_kafka_error_is_retriable");
    XKD_REQ(error_is_fatal, "rd_kafka_error_is_fatal");
    XKD_REQ(queue_new, "rd_kafka_queue_new");
    XKD_REQ(queue_destroy, "rd_kafka_queue_destroy");
    XKD_REQ(queue_poll, "rd_kafka_queue_poll");
    XKD_REQ(event_destroy, "rd_kafka_event_destroy");
    XKD_REQ(event_type, "rd_kafka_event_type");
    XKD_REQ(event_error, "rd_kafka_event_error");
    XKD_REQ(event_error_string, "rd_kafka_event_error_string");
    XKD_REQ(create_topics_result, "rd_kafka_CreateTopics_result_topics");
    XKD_REQ(delete_topics_result, "rd_kafka_DeleteTopics_result_topics");
    XKD_REQ(topic_result_error, "rd_kafka_topic_result_error");
    XKD_REQ(topic_result_error_string, "rd_kafka_topic_result_error_string");
    XKD_REQ(topic_result_name, "rd_kafka_topic_result_name");
    XKD_REQ(new_topic_new, "rd_kafka_NewTopic_new");
    XKD_REQ(new_topic_destroy, "rd_kafka_NewTopic_destroy");
    XKD_REQ(delete_topic_new, "rd_kafka_DeleteTopic_new");
    XKD_REQ(delete_topic_destroy, "rd_kafka_DeleteTopic_destroy");
    XKD_REQ(create_topics, "rd_kafka_CreateTopics");
    XKD_REQ(delete_topics, "rd_kafka_DeleteTopics");
    XKD_REQ(admin_options_new, "rd_kafka_AdminOptions_new");
    XKD_REQ(admin_options_destroy, "rd_kafka_AdminOptions_destroy");
    XKD_REQ(admin_options_timeout, "rd_kafka_AdminOptions_set_operation_timeout");

    XKD_OPT(mock_cluster_new, "rd_kafka_mock_cluster_new");
    XKD_OPT(mock_cluster_destroy, "rd_kafka_mock_cluster_destroy");
    XKD_OPT(mock_bootstraps, "rd_kafka_mock_cluster_bootstraps");
    XKD_OPT(mock_topic_create, "rd_kafka_mock_topic_create");
    XKD_OPT(mock_set_controller, "rd_kafka_mock_set_controller_id");

    g_mock_ok = A.mock_cluster_new && A.mock_cluster_destroy &&
                A.mock_bootstraps && A.mock_topic_create &&
                A.mock_set_controller;

    if (g_required_missing > 0) {
        snprintf(g_error, sizeof(g_error),
                 "%s: %d required export(s) missing: %s", soname,
                 g_required_missing, g_missing);
        xkd_unload();
        return 2; /* ABI */
    }
    g_error[0] = 0;
    return 0;
}

int32_t xkd_load(void) {
    static const char *candidates[] = {
#if defined(_WIN32)
        "librdkafka.dll",
        "rdkafka.dll",
        "librdkafka-2.dll",
#else
        "librdkafka.so.1",
        "librdkafka.so",
        "librdkafka.1.dylib",
        "librdkafka.dylib",
#endif
        0
    };
    int i;
    char last[512];
    last[0] = 0;
    for (i = 0; candidates[i]; i++) {
        int32_t rc = xkd_load_named(candidates[i]);
        if (rc == 0) return 0;
        snprintf(last, sizeof(last), "%s", g_error);
        if (rc == 2) return 2;
    }
    snprintf(g_error, sizeof(g_error), "%s",
             last[0] ? last : "librdkafka not found");
    return 1;
}

int32_t xkd_loaded(void) { return g_lib ? 1 : 0; }
const char *xkd_soname(void) { return g_soname; }
const char *xkd_error(void) { return g_error; }
int32_t xkd_abi_missing_count(void) { return g_missing_count; }
const char *xkd_abi_missing(void) { return g_missing; }
int32_t xkd_mock_available(void) { return g_mock_ok; }

void xkd_unload(void) {
    if (g_lib) {
        xkd_dlclose(g_lib);
        g_lib = 0;
    }
    xkd_clear_api();
}

int32_t xkd_version_int(void) { return A.version ? A.version() : -1; }

const char *xkd_version_str(void) {
    return A.version_str ? A.version_str() : "unavailable";
}

const char *xkd_err2str(int32_t code) {
    return A.err2str ? A.err2str((rd_kafka_resp_err_t)code) : "unavailable";
}

const char *xkd_err2name(int32_t code) {
    return A.err2name ? A.err2name((rd_kafka_resp_err_t)code) : "unavailable";
}

int32_t xkd_err_is_retryable(int32_t code) {
    switch (code) {
    case -195: /* __TRANSPORT */
    case -193: /* __RESOLVE */
    case -192: /* __MSG_TIMED_OUT */
    case -187: /* __ALL_BROKERS_DOWN */
    case -185: /* __TIMED_OUT */
    case -184: /* __QUEUE_FULL */
    case -180: /* __WAIT_COORD */
    case -178: /* __IN_PROGRESS */
    case -166: /* __TIMED_OUT_QUEUE */
        return 1;
    default:
        return 0;
    }
}

int32_t xkd_last_error_code(void) { return g_last_err; }

/* -- configuration ------------------------------------------------------- */

int64_t xkd_conf_new(void) {
    if (!A.conf_new) {
        xkd_set_error("librdkafka is not loaded");
        return 0;
    }
    return (int64_t)(intptr_t)A.conf_new();
}

void xkd_conf_destroy(int64_t conf) {
    if (conf && A.conf_destroy) A.conf_destroy((rd_kafka_conf_t *)(intptr_t)conf);
}

int32_t xkd_conf_set(int64_t conf, const char *name, const char *value,
                     char *errstr, int64_t cap) {
    rd_kafka_conf_res_t rc;
    if (!conf || !A.conf_set) {
        if (errstr && cap > 0) snprintf(errstr, (size_t)cap, "%s", "librdkafka is not loaded");
        g_last_err = XKD_E_STATE;
        return XKD_E_STATE;
    }
    if (errstr && cap > 0) errstr[0] = 0;
    rc = A.conf_set((rd_kafka_conf_t *)(intptr_t)conf, name, value, errstr,
                    (size_t)cap);
    if (rc != 0) {
        if (errstr && cap > 0 && !errstr[0])
            snprintf(errstr, (size_t)cap, "invalid configuration property: %s",
                     name ? name : "");
        g_last_err = XKD_E_INVALID_ARG;
        return XKD_E_INVALID_ARG;
    }
    return 0;
}

int32_t xkd_conf_get(int64_t conf, const char *name, char *dest, int64_t cap,
                     char *errstr, int64_t errcap) {
    size_t sz = cap > 0 ? (size_t)cap : 0;
    rd_kafka_conf_res_t rc;
    if (!conf || !A.conf_get) {
        if (errstr && errcap > 0) snprintf(errstr, (size_t)errcap, "%s", "librdkafka is not loaded");
        g_last_err = XKD_E_STATE;
        return XKD_E_STATE;
    }
    if (errstr && errcap > 0) errstr[0] = 0;
    if (dest && cap > 0) dest[0] = 0;
    rc = A.conf_get((const rd_kafka_conf_t *)(intptr_t)conf, name, dest, &sz);
    if (rc != 0) {
        if (errstr && errcap > 0)
            snprintf(errstr, (size_t)errcap, "unknown configuration property: %s",
                     name ? name : "");
        g_last_err = XKD_E_INVALID_ARG;
        return XKD_E_INVALID_ARG;
    }
    return 0;
}

int32_t xkd_conf_set_validate(const char *name, const char *value, char *errstr,
                              int64_t cap) {
    int64_t conf = xkd_conf_new();
    int32_t rc;
    if (!conf) {
        if (errstr && cap > 0) snprintf(errstr, (size_t)cap, "%s", g_error);
        return XKD_E_STATE;
    }
    rc = xkd_conf_set(conf, name, value, errstr, cap);
    xkd_conf_destroy(conf);
    return rc;
}

int32_t xkd_conf_get_default(const char *name, char *dest, int64_t cap,
                             char *errstr, int64_t errcap) {
    int64_t conf = xkd_conf_new();
    int32_t rc;
    if (!conf) {
        if (errstr && errcap > 0) snprintf(errstr, (size_t)errcap, "%s", g_error);
        return XKD_E_STATE;
    }
    rc = xkd_conf_get(conf, name, dest, cap, errstr, errcap);
    xkd_conf_destroy(conf);
    return rc;
}

/* -- clients ------------------------------------------------------------- */

int32_t xkd_client_name(int64_t rk, char *dest, int64_t cap) {
    if (!rk || !A.client_name) return -1;
    return xkd_copy_str(A.client_name((const rd_kafka_t *)(intptr_t)rk), dest, cap);
}

int32_t xkd_cluster_id(int64_t rk, int32_t timeout_ms, char *dest, int64_t cap) {
    char *id;
    int32_t n;
    if (!rk || !A.clusterid) return -1;
    id = A.clusterid((rd_kafka_t *)(intptr_t)rk, timeout_ms);
    if (!id) return -1;
    n = xkd_copy_str(id, dest, cap);
    if (A.mem_free) A.mem_free((rd_kafka_t *)(intptr_t)rk, id);
    return n;
}

void xkd_client_destroy(int64_t rk) {
    if (rk && A.client_destroy) A.client_destroy((rd_kafka_t *)(intptr_t)rk);
}

/* -- producer ------------------------------------------------------------ */

#define XKD_REPORT_RING 1024
#define XKD_TOPIC_MAX 256

typedef struct xkd_report_s {
    int64_t id;
    int32_t partition;
    int32_t err;
    int64_t offset;
    int64_t timestamp;
    char topic[XKD_TOPIC_MAX];
} xkd_report;

typedef struct xkd_producer_ctx_s {
    rd_kafka_t *rk;
    int64_t next_id;
    xkd_report reports[XKD_REPORT_RING];
    int head;
    int tail;
    int count;
    xkd_report last;
    int has_last;
} xkd_producer_ctx;

static void xkd_dr_cb(rd_kafka_t *rk, const rd_kafka_message_t *m, void *opaque) {
    xkd_producer_ctx *ctx = (xkd_producer_ctx *)opaque;
    const xkd_message_t *msg = (const xkd_message_t *)m;
    xkd_report *r;
    int tstype = 0;
    int64_t ts = 0;
    (void)rk;
    if (!ctx || !msg) return;
    if (A.message_timestamp) ts = A.message_timestamp(m, &tstype);
    if (ctx->count == XKD_REPORT_RING) {
        ctx->head = (ctx->head + 1) % XKD_REPORT_RING;
        ctx->count--;
    }
    r = &ctx->reports[ctx->tail];
    memset(r, 0, sizeof(*r));
    r->id = (int64_t)(intptr_t)msg->_private;
    r->partition = msg->partition;
    r->err = msg->err;
    r->offset = msg->offset;
    r->timestamp = ts;
    if (msg->rkt && A.topic_name) {
        const char *t = A.topic_name((const rd_kafka_topic_t *)msg->rkt);
        if (t) snprintf(r->topic, sizeof(r->topic), "%s", t);
    }
    ctx->tail = (ctx->tail + 1) % XKD_REPORT_RING;
    ctx->count++;
}

int64_t xkd_producer_new(int64_t conf, char *errstr, int64_t cap) {
    xkd_producer_ctx *ctx;
    rd_kafka_t *rk;
    if (!conf || !A.new_client) {
        if (errstr && cap > 0) snprintf(errstr, (size_t)cap, "%s", "librdkafka is not loaded");
        return 0;
    }
    ctx = (xkd_producer_ctx *)calloc(1, sizeof(*ctx));
    if (!ctx) {
        if (errstr && cap > 0) snprintf(errstr, (size_t)cap, "%s", "out of memory");
        xkd_conf_destroy(conf);
        return 0;
    }
    ctx->next_id = 1;
    if (A.conf_set_opaque) A.conf_set_opaque((rd_kafka_conf_t *)(intptr_t)conf, ctx);
    if (A.conf_set_dr_msg_cb)
        A.conf_set_dr_msg_cb((rd_kafka_conf_t *)(intptr_t)conf, xkd_dr_cb);
    if (errstr && cap > 0) errstr[0] = 0;
    rk = A.new_client(XKD_PRODUCER, (rd_kafka_conf_t *)(intptr_t)conf, errstr,
                      (size_t)cap);
    if (!rk) {
        /* rd_kafka_new only takes ownership on success. */
        xkd_conf_destroy(conf);
        free(ctx);
        return 0;
    }
    ctx->rk = rk;
    return (int64_t)(intptr_t)ctx;
}

int64_t xkd_produce(int64_t pctx, const char *topic, int32_t partition,
                    const void *key, int64_t keylen, const void *value,
                    int64_t vallen) {
    xkd_producer_ctx *ctx = (xkd_producer_ctx *)(intptr_t)pctx;
    rd_kafka_topic_t *rkt;
    int64_t id;
    int rc;
    if (!ctx || !A.topic_new || !A.produce) {
        g_last_err = XKD_E_STATE;
        return -1;
    }
    rkt = A.topic_new(ctx->rk, topic, 0);
    if (!rkt) {
        g_last_err = A.last_error ? A.last_error() : XKD_E_INVALID_ARG;
        return -1;
    }
    id = ctx->next_id++;
    rc = A.produce(rkt, partition, XKD_MSG_F_COPY, (void *)value,
                   (size_t)vallen, key, (size_t)keylen,
                   (void *)(intptr_t)id);
    if (rc != 0) {
        g_last_err = A.last_error ? A.last_error() : XKD_E_INVALID_ARG;
        A.topic_destroy(rkt);
        return -1;
    }
    A.topic_destroy(rkt);
    g_last_err = 0;
    return id;
}

int32_t xkd_producer_cluster_id(int64_t pctx, int32_t timeout_ms, char *dest,
                                int64_t cap) {
    xkd_producer_ctx *ctx = (xkd_producer_ctx *)(intptr_t)pctx;
    if (!ctx) return -1;
    return xkd_cluster_id((int64_t)(intptr_t)ctx->rk, timeout_ms, dest, cap);
}

int32_t xkd_producer_poll(int64_t pctx, int32_t timeout_ms) {
    xkd_producer_ctx *ctx = (xkd_producer_ctx *)(intptr_t)pctx;
    if (!ctx || !A.poll) return XKD_E_STATE;
    return A.poll(ctx->rk, timeout_ms);
}

int32_t xkd_producer_poll_report(int64_t pctx, int32_t timeout_ms) {
    xkd_producer_ctx *ctx = (xkd_producer_ctx *)(intptr_t)pctx;
    if (!ctx || !A.poll) return -1;
    A.poll(ctx->rk, timeout_ms);
    if (ctx->count == 0) {
        ctx->has_last = 0;
        return 0;
    }
    ctx->last = ctx->reports[ctx->head];
    ctx->head = (ctx->head + 1) % XKD_REPORT_RING;
    ctx->count--;
    ctx->has_last = 1;
    return 1;
}

int64_t xkd_report_id(int64_t pctx) {
    xkd_producer_ctx *ctx = (xkd_producer_ctx *)(intptr_t)pctx;
    return ctx && ctx->has_last ? ctx->last.id : -1;
}

int32_t xkd_report_partition(int64_t pctx) {
    xkd_producer_ctx *ctx = (xkd_producer_ctx *)(intptr_t)pctx;
    return ctx && ctx->has_last ? ctx->last.partition : -1;
}

int32_t xkd_report_err(int64_t pctx) {
    xkd_producer_ctx *ctx = (xkd_producer_ctx *)(intptr_t)pctx;
    return ctx && ctx->has_last ? ctx->last.err : XKD_E_STATE;
}

int64_t xkd_report_offset(int64_t pctx) {
    xkd_producer_ctx *ctx = (xkd_producer_ctx *)(intptr_t)pctx;
    return ctx && ctx->has_last ? ctx->last.offset : -1;
}

int64_t xkd_report_timestamp(int64_t pctx) {
    xkd_producer_ctx *ctx = (xkd_producer_ctx *)(intptr_t)pctx;
    return ctx && ctx->has_last ? ctx->last.timestamp : 0;
}

int32_t xkd_report_topic(int64_t pctx, char *dest, int64_t cap) {
    xkd_producer_ctx *ctx = (xkd_producer_ctx *)(intptr_t)pctx;
    return ctx && ctx->has_last ? xkd_copy_str(ctx->last.topic, dest, cap) : 0;
}

int32_t xkd_flush(int64_t pctx, int32_t timeout_ms) {
    xkd_producer_ctx *ctx = (xkd_producer_ctx *)(intptr_t)pctx;
    rd_kafka_resp_err_t err;
    if (!ctx || !A.flush) return XKD_E_STATE;
    err = A.flush(ctx->rk, timeout_ms);
    g_last_err = err;
    return err;
}

int32_t xkd_outq_len(int64_t pctx) {
    xkd_producer_ctx *ctx = (xkd_producer_ctx *)(intptr_t)pctx;
    return ctx && A.outq_len ? A.outq_len(ctx->rk) : 0;
}

void xkd_producer_destroy(int64_t pctx) {
    xkd_producer_ctx *ctx = (xkd_producer_ctx *)(intptr_t)pctx;
    if (!ctx) return;
    if (ctx->rk && A.client_destroy) A.client_destroy(ctx->rk);
    free(ctx);
}

/* -- transactions -------------------------------------------------------- */

int64_t xkd_init_transactions(int64_t pctx, int32_t timeout_ms) {
    xkd_producer_ctx *ctx = (xkd_producer_ctx *)(intptr_t)pctx;
    if (!ctx || !A.init_transactions) return 0;
    return (int64_t)(intptr_t)A.init_transactions(ctx->rk, timeout_ms);
}

int64_t xkd_begin_transaction(int64_t pctx) {
    xkd_producer_ctx *ctx = (xkd_producer_ctx *)(intptr_t)pctx;
    if (!ctx || !A.begin_transaction) return 0;
    return (int64_t)(intptr_t)A.begin_transaction(ctx->rk);
}

int64_t xkd_commit_transaction(int64_t pctx, int32_t timeout_ms) {
    xkd_producer_ctx *ctx = (xkd_producer_ctx *)(intptr_t)pctx;
    if (!ctx || !A.commit_transaction) return 0;
    return (int64_t)(intptr_t)A.commit_transaction(ctx->rk, timeout_ms);
}

int64_t xkd_abort_transaction(int64_t pctx, int32_t timeout_ms) {
    xkd_producer_ctx *ctx = (xkd_producer_ctx *)(intptr_t)pctx;
    if (!ctx || !A.abort_transaction) return 0;
    return (int64_t)(intptr_t)A.abort_transaction(ctx->rk, timeout_ms);
}

int32_t xkd_error_code(int64_t errh) {
    if (!errh || !A.error_code) return 0;
    return A.error_code((const rd_kafka_error_t *)(intptr_t)errh);
}

int32_t xkd_error_is_retriable(int64_t errh) {
    if (!errh || !A.error_is_retriable) return 0;
    return A.error_is_retriable((const rd_kafka_error_t *)(intptr_t)errh);
}

int32_t xkd_error_is_fatal(int64_t errh) {
    if (!errh || !A.error_is_fatal) return 0;
    return A.error_is_fatal((const rd_kafka_error_t *)(intptr_t)errh);
}

int32_t xkd_error_string(int64_t errh, char *dest, int64_t cap) {
    if (!errh || !A.error_string) {
        if (dest && cap > 0) dest[0] = 0;
        return 0;
    }
    return xkd_copy_str(A.error_string((const rd_kafka_error_t *)(intptr_t)errh),
                        dest, cap);
}

void xkd_error_destroy(int64_t errh) {
    if (errh && A.error_destroy) A.error_destroy((rd_kafka_error_t *)(intptr_t)errh);
}

/* -- consumer ------------------------------------------------------------ */

int64_t xkd_consumer_new(int64_t conf, char *errstr, int64_t cap) {
    if (!conf || !A.new_client) {
        if (errstr && cap > 0) snprintf(errstr, (size_t)cap, "%s", "librdkafka is not loaded");
        return 0;
    }
    if (errstr && cap > 0) errstr[0] = 0;
    {
        rd_kafka_t *rk = A.new_client(XKD_CONSUMER,
                                      (rd_kafka_conf_t *)(intptr_t)conf,
                                      errstr, (size_t)cap);
        if (!rk) xkd_conf_destroy(conf); /* rd_kafka_new owns it only on success */
        return (int64_t)(intptr_t)rk;
    }
}

int64_t xkd_topic_list_new(void) {
    if (!A.tpl_new) return 0;
    return (int64_t)(intptr_t)A.tpl_new(1);
}

void xkd_topic_list_destroy(int64_t tpl) {
    if (tpl && A.tpl_destroy) A.tpl_destroy((rd_kafka_topic_partition_list_t *)(intptr_t)tpl);
}

int32_t xkd_topic_list_add(int64_t tpl, const char *topic, int32_t partition) {
    return xkd_topic_list_add_at(tpl, topic, partition, XKD_OFFSET_INVALID);
}

int32_t xkd_topic_list_add_at(int64_t tpl, const char *topic, int32_t partition,
                              int64_t offset) {
    rd_kafka_topic_partition_list_t *l =
        (rd_kafka_topic_partition_list_t *)(intptr_t)tpl;
    rd_kafka_resp_err_t err;
    if (!l || !A.tpl_add || !A.tpl_set_offset) return XKD_E_STATE;
    if (!A.tpl_add(l, topic, partition)) return XKD_E_INVALID_ARG;
    err = A.tpl_set_offset(l, topic, partition, offset);
    return err;
}

int32_t xkd_subscribe(int64_t rk, int64_t tpl) {
    rd_kafka_resp_err_t err;
    if (!rk || !tpl || !A.subscribe) return XKD_E_STATE;
    err = A.subscribe((rd_kafka_t *)(intptr_t)rk,
                      (const rd_kafka_topic_partition_list_t *)(intptr_t)tpl);
    g_last_err = err;
    return err;
}

int32_t xkd_assign(int64_t rk, int64_t tpl) {
    rd_kafka_resp_err_t err;
    if (!rk || !tpl || !A.assign) return XKD_E_STATE;
    err = A.assign((rd_kafka_t *)(intptr_t)rk,
                   (const rd_kafka_topic_partition_list_t *)(intptr_t)tpl);
    g_last_err = err;
    return err;
}

int32_t xkd_unsubscribe(int64_t rk) {
    rd_kafka_resp_err_t err;
    if (!rk || !A.unsubscribe) return XKD_E_STATE;
    err = A.unsubscribe((rd_kafka_t *)(intptr_t)rk);
    g_last_err = err;
    return err;
}

int64_t xkd_consumer_poll(int64_t rk, int32_t timeout_ms) {
    if (!rk || !A.consumer_poll) return 0;
    return (int64_t)(intptr_t)A.consumer_poll((rd_kafka_t *)(intptr_t)rk,
                                              timeout_ms);
}

int32_t xkd_commit(int64_t rk, int32_t async) {
    rd_kafka_resp_err_t err;
    if (!rk || !A.commit) return XKD_E_STATE;
    err = A.commit((rd_kafka_t *)(intptr_t)rk, 0, async);
    g_last_err = err;
    return err;
}

int32_t xkd_consumer_close(int64_t rk) {
    rd_kafka_resp_err_t err = 0;
    if (!rk) return XKD_E_STATE;
    if (A.consumer_close) err = A.consumer_close((rd_kafka_t *)(intptr_t)rk);
    if (A.client_destroy) A.client_destroy((rd_kafka_t *)(intptr_t)rk);
    g_last_err = err;
    return err;
}

int32_t xkd_consumer_name(int64_t rk, char *dest, int64_t cap) {
    return xkd_client_name(rk, dest, cap);
}

/* -- messages ------------------------------------------------------------ */

int32_t xkd_message_err(int64_t msg) {
    const xkd_message_t *m = (const xkd_message_t *)(intptr_t)msg;
    return m ? m->err : XKD_E_INVALID_ARG;
}

int32_t xkd_message_error_string(int64_t msg, char *dest, int64_t cap) {
    const rd_kafka_message_t *m = (const rd_kafka_message_t *)(intptr_t)msg;
    if (!m || !A.message_errstr) {
        if (dest && cap > 0) dest[0] = 0;
        return 0;
    }
    return xkd_copy_str(A.message_errstr(m), dest, cap);
}

int32_t xkd_message_topic(int64_t msg, char *dest, int64_t cap) {
    const xkd_message_t *m = (const xkd_message_t *)(intptr_t)msg;
    const char *t = 0;
    if (!m) return 0;
    if (m->rkt && A.topic_name)
        t = A.topic_name((const rd_kafka_topic_t *)m->rkt);
    return xkd_copy_str(t, dest, cap);
}

int32_t xkd_message_partition(int64_t msg) {
    const xkd_message_t *m = (const xkd_message_t *)(intptr_t)msg;
    return m ? m->partition : -1;
}

int64_t xkd_message_offset(int64_t msg) {
    const xkd_message_t *m = (const xkd_message_t *)(intptr_t)msg;
    return m ? m->offset : -1;
}

int64_t xkd_message_timestamp(int64_t msg) {
    const rd_kafka_message_t *m = (const rd_kafka_message_t *)(intptr_t)msg;
    int type = 0;
    if (!m || !A.message_timestamp) return 0;
    return A.message_timestamp(m, &type);
}

int32_t xkd_message_timestamp_type(int64_t msg) {
    const rd_kafka_message_t *m = (const rd_kafka_message_t *)(intptr_t)msg;
    int type = 0;
    if (!m || !A.message_timestamp) return 0;
    A.message_timestamp(m, &type);
    return type;
}

int64_t xkd_message_key_len(int64_t msg) {
    const xkd_message_t *m = (const xkd_message_t *)(intptr_t)msg;
    return (m && m->key) ? (int64_t)m->key_len : 0;
}

int64_t xkd_message_value_len(int64_t msg) {
    const xkd_message_t *m = (const xkd_message_t *)(intptr_t)msg;
    return m ? (int64_t)m->len : 0;
}

int64_t xkd_message_key_copy(int64_t msg, void *dest, int64_t cap) {
    const xkd_message_t *m = (const xkd_message_t *)(intptr_t)msg;
    if (!m || !m->key) return 0;
    if (dest && cap > 0) {
        size_t n = m->key_len < (size_t)cap ? m->key_len : (size_t)cap;
        memcpy(dest, m->key, n);
    }
    return (int64_t)m->key_len;
}

int64_t xkd_message_value_copy(int64_t msg, void *dest, int64_t cap) {
    const xkd_message_t *m = (const xkd_message_t *)(intptr_t)msg;
    if (!m) return 0;
    if (dest && cap > 0 && m->payload) {
        size_t n = m->len < (size_t)cap ? m->len : (size_t)cap;
        memcpy(dest, m->payload, n);
    }
    return (int64_t)m->len;
}

void xkd_message_destroy(int64_t msg) {
    if (msg && A.message_destroy)
        A.message_destroy((rd_kafka_message_t *)(intptr_t)msg);
}

/* -- metadata ------------------------------------------------------------ */

int64_t xkd_metadata(int64_t rk, int32_t timeout_ms) {
    const rd_kafka_metadata_t *md = 0;
    rd_kafka_resp_err_t err;
    if (!rk || !A.metadata) {
        g_last_err = XKD_E_STATE;
        return 0;
    }
    err = A.metadata((rd_kafka_t *)(intptr_t)rk, 1, 0, &md, timeout_ms);
    g_last_err = err;
    if (err != 0 || !md) return 0;
    return (int64_t)(intptr_t)md;
}

int64_t xkd_producer_metadata(int64_t pctx, int32_t timeout_ms) {
    xkd_producer_ctx *ctx = (xkd_producer_ctx *)(intptr_t)pctx;
    return ctx ? xkd_metadata((int64_t)(intptr_t)ctx->rk, timeout_ms) : 0;
}

int64_t xkd_metadata_for_conf(int64_t conf, int32_t timeout_ms) {
    rd_kafka_t *rk;
    const rd_kafka_metadata_t *md = 0;
    rd_kafka_resp_err_t err;
    char errstr[256];
    if (!conf || !A.new_client || !A.metadata) {
        g_last_err = XKD_E_STATE;
        return 0;
    }
    errstr[0] = 0;
    rk = A.new_client(XKD_PRODUCER, (rd_kafka_conf_t *)(intptr_t)conf, errstr,
                      sizeof(errstr));
    if (!rk) {
        xkd_conf_destroy(conf); /* rd_kafka_new owns it only on success */
        g_last_err = XKD_E_STATE;
        return 0;
    }
    err = A.metadata(rk, 1, 0, &md, timeout_ms);
    g_last_err = err;
    if (err != 0) md = 0;
    A.client_destroy(rk);
    return (int64_t)(intptr_t)md;
}

void xkd_metadata_destroy(int64_t md) {
    if (md && A.metadata_destroy)
        A.metadata_destroy((const rd_kafka_metadata_t *)(intptr_t)md);
}

int32_t xkd_metadata_broker_count(int64_t md) {
    const rd_kafka_metadata_t *m = (const rd_kafka_metadata_t *)(intptr_t)md;
    return m ? m->broker_cnt : 0;
}

int32_t xkd_metadata_broker_id(int64_t md, int32_t i) {
    const rd_kafka_metadata_t *m = (const rd_kafka_metadata_t *)(intptr_t)md;
    return (m && i >= 0 && i < m->broker_cnt) ? m->brokers[i].id : -1;
}

int32_t xkd_metadata_broker_host(int64_t md, int32_t i, char *dest, int64_t cap) {
    const rd_kafka_metadata_t *m = (const rd_kafka_metadata_t *)(intptr_t)md;
    if (!m || i < 0 || i >= m->broker_cnt) return 0;
    return xkd_copy_str(m->brokers[i].host, dest, cap);
}

int32_t xkd_metadata_broker_port(int64_t md, int32_t i) {
    const rd_kafka_metadata_t *m = (const rd_kafka_metadata_t *)(intptr_t)md;
    return (m && i >= 0 && i < m->broker_cnt) ? m->brokers[i].port : -1;
}

int32_t xkd_metadata_topic_count(int64_t md) {
    const rd_kafka_metadata_t *m = (const rd_kafka_metadata_t *)(intptr_t)md;
    return m ? m->topic_cnt : 0;
}

int32_t xkd_metadata_topic_name(int64_t md, int32_t i, char *dest, int64_t cap) {
    const rd_kafka_metadata_t *m = (const rd_kafka_metadata_t *)(intptr_t)md;
    if (!m || i < 0 || i >= m->topic_cnt) return 0;
    return xkd_copy_str(m->topics[i].topic, dest, cap);
}

int32_t xkd_metadata_topic_err(int64_t md, int32_t i) {
    const rd_kafka_metadata_t *m = (const rd_kafka_metadata_t *)(intptr_t)md;
    return (m && i >= 0 && i < m->topic_cnt) ? m->topics[i].err : 0;
}

int32_t xkd_metadata_topic_partition_count(int64_t md, int32_t i) {
    const rd_kafka_metadata_t *m = (const rd_kafka_metadata_t *)(intptr_t)md;
    return (m && i >= 0 && i < m->topic_cnt) ? m->topics[i].partition_cnt : 0;
}

static const xkd_metadata_partition_t *xkd_md_part(int64_t md, int32_t i,
                                                   int32_t j) {
    const rd_kafka_metadata_t *m = (const rd_kafka_metadata_t *)(intptr_t)md;
    if (!m || i < 0 || i >= m->topic_cnt) return 0;
    if (j < 0 || j >= m->topics[i].partition_cnt) return 0;
    return &m->topics[i].partitions[j];
}

int32_t xkd_metadata_partition_id(int64_t md, int32_t i, int32_t j) {
    const xkd_metadata_partition_t *p = xkd_md_part(md, i, j);
    return p ? p->id : -1;
}

int32_t xkd_metadata_partition_err(int64_t md, int32_t i, int32_t j) {
    const xkd_metadata_partition_t *p = xkd_md_part(md, i, j);
    return p ? p->err : 0;
}

int32_t xkd_metadata_partition_leader(int64_t md, int32_t i, int32_t j) {
    const xkd_metadata_partition_t *p = xkd_md_part(md, i, j);
    return p ? p->leader : -1;
}

int32_t xkd_metadata_partition_replica_count(int64_t md, int32_t i, int32_t j) {
    const xkd_metadata_partition_t *p = xkd_md_part(md, i, j);
    return p ? p->replica_cnt : 0;
}

int32_t xkd_metadata_partition_replica(int64_t md, int32_t i, int32_t j,
                                       int32_t k) {
    const xkd_metadata_partition_t *p = xkd_md_part(md, i, j);
    return (p && k >= 0 && k < p->replica_cnt) ? p->replicas[k] : -1;
}

int32_t xkd_metadata_partition_isr_count(int64_t md, int32_t i, int32_t j) {
    const xkd_metadata_partition_t *p = xkd_md_part(md, i, j);
    return p ? p->isr_cnt : 0;
}

int32_t xkd_metadata_partition_isr(int64_t md, int32_t i, int32_t j,
                                   int32_t k) {
    const xkd_metadata_partition_t *p = xkd_md_part(md, i, j);
    return (p && k >= 0 && k < p->isr_cnt) ? p->isrs[k] : -1;
}

/* -- admin --------------------------------------------------------------- */

int64_t xkd_admin_new(int64_t conf, char *errstr, int64_t cap) {
    if (!conf || !A.new_client) {
        if (errstr && cap > 0) snprintf(errstr, (size_t)cap, "%s", "librdkafka is not loaded");
        return 0;
    }
    if (errstr && cap > 0) errstr[0] = 0;
    {
        rd_kafka_t *rk = A.new_client(XKD_PRODUCER,
                                      (rd_kafka_conf_t *)(intptr_t)conf,
                                      errstr, (size_t)cap);
        if (!rk) xkd_conf_destroy(conf); /* rd_kafka_new owns it only on success */
        return (int64_t)(intptr_t)rk;
    }
}

void xkd_admin_destroy(int64_t rk) { xkd_client_destroy(rk); }

static int32_t xkd_admin_result_error(rd_kafka_event_t *ev,
                                      const rd_kafka_topic_result_t **trs,
                                      size_t cnt, char *errstr, int64_t cap) {
    rd_kafka_resp_err_t err = A.event_error(ev);
    if (err != 0) {
        const char *s = A.event_error_string ? A.event_error_string(ev) : 0;
        xkd_copy_str(s ? s : A.err2str(err), errstr, cap);
        return err;
    }
    if (trs && cnt > 0) {
        rd_kafka_resp_err_t terr = A.topic_result_error(trs[0]);
        if (terr != 0) {
            const char *s = A.topic_result_error_string
                                ? A.topic_result_error_string(trs[0])
                                : 0;
            xkd_copy_str(s ? s : A.err2str(terr), errstr, cap);
            return terr;
        }
    }
    return 0;
}

int32_t xkd_create_topic(int64_t rk, const char *topic, int32_t partitions,
                         int32_t replication, int32_t timeout_ms, char *errstr,
                         int64_t cap) {
    rd_kafka_NewTopic_t *nt = 0;
    rd_kafka_AdminOptions_t *opts = 0;
    rd_kafka_queue_t *q = 0;
    rd_kafka_event_t *ev = 0;
    const rd_kafka_topic_result_t **trs = 0;
    size_t cnt = 0;
    int32_t rc = 0;
    char local[512];
    if (!rk || !A.new_topic_new || !A.create_topics || !A.queue_new) {
        if (errstr && cap > 0) snprintf(errstr, (size_t)cap, "%s", "librdkafka is not loaded");
        return XKD_E_STATE;
    }
    if (errstr && cap > 0) errstr[0] = 0;
    local[0] = 0;
    nt = A.new_topic_new(topic, partitions, replication, local, sizeof(local));
    if (!nt) {
        xkd_copy_str(local[0] ? local : "invalid topic arguments", errstr, cap);
        return XKD_E_INVALID_ARG;
    }
    opts = A.admin_options_new ? A.admin_options_new((rd_kafka_t *)(intptr_t)rk,
                                                      XKD_ADMIN_OP_CREATETOPICS)
                               : 0;
    if (opts && A.admin_options_timeout) {
        char oerr[256];
        oerr[0] = 0;
        A.admin_options_timeout(opts, timeout_ms > 0 ? timeout_ms : 10000, oerr,
                                sizeof(oerr));
    }
    q = A.queue_new((rd_kafka_t *)(intptr_t)rk);
    if (!q) {
        if (errstr && cap > 0) snprintf(errstr, (size_t)cap, "%s", "queue allocation failed");
        A.new_topic_destroy(nt);
        if (opts && A.admin_options_destroy) A.admin_options_destroy(opts);
        return XKD_E_STATE;
    }
    A.create_topics((rd_kafka_t *)(intptr_t)rk, &nt, 1, opts, q);
    ev = A.queue_poll(q, timeout_ms > 0 ? timeout_ms + 500 : 10500);
    if (!ev) {
        xkd_copy_str("timed out waiting for CreateTopics result", errstr, cap);
        rc = XKD_E_TIMED_OUT;
    } else if (A.event_type && A.event_type(ev) != 100 /* CREATETOPICS */) {
        xkd_copy_str("unexpected CreateTopics event type", errstr, cap);
        rc = XKD_E_UNSUPPORTED;
        A.event_destroy(ev);
    } else {
        if (A.create_topics_result)
            trs = A.create_topics_result(ev, &cnt);
        rc = xkd_admin_result_error(ev, trs, cnt, errstr, cap);
        A.event_destroy(ev);
    }
    A.queue_destroy(q);
    if (opts && A.admin_options_destroy) A.admin_options_destroy(opts);
    A.new_topic_destroy(nt);
    g_last_err = rc;
    return rc;
}

int32_t xkd_delete_topic(int64_t rk, const char *topic, int32_t timeout_ms,
                         char *errstr, int64_t cap) {
    rd_kafka_DeleteTopic_t *dt = 0;
    rd_kafka_AdminOptions_t *opts = 0;
    rd_kafka_queue_t *q = 0;
    rd_kafka_event_t *ev = 0;
    const rd_kafka_topic_result_t **trs = 0;
    size_t cnt = 0;
    int32_t rc = 0;
    if (!rk || !A.delete_topic_new || !A.delete_topics || !A.queue_new) {
        if (errstr && cap > 0) snprintf(errstr, (size_t)cap, "%s", "librdkafka is not loaded");
        return XKD_E_STATE;
    }
    if (errstr && cap > 0) errstr[0] = 0;
    dt = A.delete_topic_new(topic);
    if (!dt) {
        xkd_copy_str("invalid topic argument", errstr, cap);
        return XKD_E_INVALID_ARG;
    }
    opts = A.admin_options_new ? A.admin_options_new((rd_kafka_t *)(intptr_t)rk,
                                                      XKD_ADMIN_OP_DELETETOPICS)
                               : 0;
    if (opts && A.admin_options_timeout) {
        char oerr[256];
        oerr[0] = 0;
        A.admin_options_timeout(opts, timeout_ms > 0 ? timeout_ms : 10000, oerr,
                                sizeof(oerr));
    }
    q = A.queue_new((rd_kafka_t *)(intptr_t)rk);
    if (!q) {
        if (errstr && cap > 0) snprintf(errstr, (size_t)cap, "%s", "queue allocation failed");
        A.delete_topic_destroy(dt);
        if (opts && A.admin_options_destroy) A.admin_options_destroy(opts);
        return XKD_E_STATE;
    }
    A.delete_topics((rd_kafka_t *)(intptr_t)rk, &dt, 1, opts, q);
    ev = A.queue_poll(q, timeout_ms > 0 ? timeout_ms + 500 : 10500);
    if (!ev) {
        xkd_copy_str("timed out waiting for DeleteTopics result", errstr, cap);
        rc = XKD_E_TIMED_OUT;
    } else if (A.event_type && A.event_type(ev) != 101 /* DELETETOPICS */) {
        xkd_copy_str("unexpected DeleteTopics event type", errstr, cap);
        rc = XKD_E_UNSUPPORTED;
        A.event_destroy(ev);
    } else {
        if (A.delete_topics_result)
            trs = A.delete_topics_result(ev, &cnt);
        rc = xkd_admin_result_error(ev, trs, cnt, errstr, cap);
        A.event_destroy(ev);
    }
    A.queue_destroy(q);
    if (opts && A.admin_options_destroy) A.admin_options_destroy(opts);
    A.delete_topic_destroy(dt);
    g_last_err = rc;
    return rc;
}

/* -- mock cluster (test support; public librdkafka API) ------------------ */

typedef struct xkd_mock_ctx_s {
    rd_kafka_t *rk;
    rd_kafka_mock_cluster_t *mcl;
} xkd_mock_ctx;

int64_t xkd_mock_cluster_new(int32_t broker_cnt, char *bootstraps, int64_t cap,
                             char *errstr, int64_t errcap) {
    xkd_mock_ctx *ctx;
    rd_kafka_conf_t *conf;
    rd_kafka_t *rk;
    rd_kafka_mock_cluster_t *mcl;
    char local[512];
    if (!g_mock_ok || !A.conf_new || !A.new_client) {
        if (errstr && errcap > 0) snprintf(errstr, (size_t)errcap, "%s",
                                           "mock cluster API is not available");
        return 0;
    }
    if (errstr && errcap > 0) errstr[0] = 0;
    conf = A.conf_new();
    if (!conf) {
        if (errstr && errcap > 0) snprintf(errstr, (size_t)errcap, "%s", "conf allocation failed");
        return 0;
    }
    /* The owner client needs no bootstrap: the mock cluster creates its own
     * listeners and the owner is only the cluster's lifetime anchor.  Silence
     * the "no bootstrap.servers" config warning for this anchor only. */
    local[0] = 0;
    A.conf_set(conf, "log_level", "0", local, sizeof(local));
    rk = A.new_client(XKD_PRODUCER, conf, local, sizeof(local));
    if (!rk) {
        A.conf_destroy(conf);
        if (errstr && errcap > 0) snprintf(errstr, (size_t)errcap, "%s", local);
        return 0;
    }
    mcl = A.mock_cluster_new(rk, broker_cnt > 0 ? broker_cnt : 1);
    if (!mcl) {
        A.client_destroy(rk);
        if (errstr && errcap > 0) snprintf(errstr, (size_t)errcap, "%s", "mock cluster creation failed");
        return 0;
    }
    ctx = (xkd_mock_ctx *)calloc(1, sizeof(*ctx));
    if (!ctx) {
        A.mock_cluster_destroy(mcl);
        A.client_destroy(rk);
        if (errstr && errcap > 0) snprintf(errstr, (size_t)errcap, "%s", "out of memory");
        return 0;
    }
    ctx->rk = rk;
    ctx->mcl = mcl;
    if (bootstraps) xkd_copy_str(A.mock_bootstraps(mcl), bootstraps, cap);
    return (int64_t)(intptr_t)ctx;
}

int32_t xkd_mock_bootstraps(int64_t mctx, char *dest, int64_t cap) {
    xkd_mock_ctx *ctx = (xkd_mock_ctx *)(intptr_t)mctx;
    if (!ctx || !A.mock_bootstraps) return 0;
    return xkd_copy_str(A.mock_bootstraps(ctx->mcl), dest, cap);
}

int32_t xkd_mock_topic_create(int64_t mctx, const char *topic, int32_t partitions,
                              int32_t replication) {
    xkd_mock_ctx *ctx = (xkd_mock_ctx *)(intptr_t)mctx;
    rd_kafka_resp_err_t err;
    if (!ctx || !A.mock_topic_create) return XKD_E_STATE;
    err = A.mock_topic_create(ctx->mcl, topic, partitions, replication);
    g_last_err = err;
    return err;
}

int32_t xkd_mock_set_controller(int64_t mctx, int32_t controller_id) {
    xkd_mock_ctx *ctx = (xkd_mock_ctx *)(intptr_t)mctx;
    if (!ctx || !A.mock_set_controller) return XKD_E_STATE;
    A.mock_set_controller(ctx->mcl, controller_id);
    return 0;
}

void xkd_mock_cluster_destroy(int64_t mctx) {
    xkd_mock_ctx *ctx = (xkd_mock_ctx *)(intptr_t)mctx;
    if (!ctx) return;
    if (ctx->mcl && A.mock_cluster_destroy) A.mock_cluster_destroy(ctx->mcl);
    if (ctx->rk && A.client_destroy) A.client_destroy(ctx->rk);
    free(ctx);
}
