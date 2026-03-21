extends RefCounted
class_name TokenManager

# ---------------------------------------------------------------------------
# TokenManager — typed coordinator for the token domain.
#
# Owned by ServiceRegistry.token.  Callers access the service through
# `registry.token.service` and connect to signals via `registry.token.service.<signal>`.
# ---------------------------------------------------------------------------

var service: ITokenService = null
