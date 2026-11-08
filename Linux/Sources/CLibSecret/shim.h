// libsecret (the freedesktop Secret Service: GNOME Keyring, KWallet's
// bridge, KeePassXC) behind four plain-C helpers, so Swift never touches
// the varargs API or SecretSchema's attribute array. Every secret is keyed
// by (service, account), like the Mac Keychain items it stands in for.
// Errors come back as a g_malloc'd message (free with g_free), or NULL.
#include <libsecret/secret.h>
#include <string.h>

static inline const SecretSchema *oneroot_secret_schema(void) {
    static const SecretSchema schema = {
        "com.hillcraft_sc.OneRoot.Secret", SECRET_SCHEMA_NONE,
        {
            { "service", SECRET_SCHEMA_ATTRIBUTE_STRING },
            { "account", SECRET_SCHEMA_ATTRIBUTE_STRING },
            { NULL, (SecretSchemaAttributeType)0 },
        }
    };
    return &schema;
}

/// Stores (replacing) `password`. Returns 1 on success.
static inline int oneroot_secret_store(const char *service, const char *account, const char *label,
                                       const char *password, char **error_message) {
    GError *error = NULL;
    gboolean ok = secret_password_store_sync(oneroot_secret_schema(), SECRET_COLLECTION_DEFAULT, label, password,
                                             NULL, &error, "service", service, "account", account, NULL);
    if (error) { *error_message = g_strdup(error->message); g_error_free(error); }
    return ok ? 1 : 0;
}

/// The stored password (free with secret_password_free), or NULL when there
/// is none or the keyring couldn't be reached (then `error_message` is set).
static inline char *oneroot_secret_lookup(const char *service, const char *account, char **error_message) {
    GError *error = NULL;
    char *password = secret_password_lookup_sync(oneroot_secret_schema(), NULL, &error,
                                                 "service", service, "account", account, NULL);
    if (error) { *error_message = g_strdup(error->message); g_error_free(error); }
    return password;
}

/// Removes the entry. Returns 1 when one was removed.
static inline int oneroot_secret_clear(const char *service, const char *account, char **error_message) {
    GError *error = NULL;
    gboolean removed = secret_password_clear_sync(oneroot_secret_schema(), NULL, &error,
                                                  "service", service, "account", account, NULL);
    if (error) { *error_message = g_strdup(error->message); g_error_free(error); }
    return removed ? 1 : 0;
}
