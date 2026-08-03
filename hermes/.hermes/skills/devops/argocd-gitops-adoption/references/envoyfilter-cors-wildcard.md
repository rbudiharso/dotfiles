# Istio EnvoyFilter CORS for Wildcard Origin Matching

## Problem

Gateway API HTTPRoute CORS filter (`type: CORS`) only supports exact-match origins — no wildcards. You cannot do `*.internal.gift.id`. Every new subdomain requires a manual patch to the HTTPRoute's `allowOrigins` list.

## Solution: Lua EnvoyFilter on Istio Gateway

Use an Istio `EnvoyFilter` with a Lua filter that regex-matches origins and injects CORS headers. Apply at the gateway level so ALL routes through that gateway inherit it.

### When to use

- Multiple internal services need cross-origin requests to each other
- Origins follow a pattern (e.g. `https://*.internal.gift.id`)
- HTTPRoute CORS filter's exact-match list keeps growing
- Gateway is Istio-based (`gatewayClassName: istio`)

### When NOT to use

- Single origin — just use HTTPRoute CORS filter with exact match
- Non-Istio gateway — EnvoyFilter is Istio-specific
- External origins (`*.usetada.com`) — handle separately or add to regex

## EnvoyFilter YAML

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: cors-internal-gift-id
  namespace: istio-system
spec:
  workloadSelector:
    labels:
      gateway.networking.k8s.io/gateway-name: external-gateway
  configPatches:
    - applyTo: HTTP_FILTER
      match:
        context: GATEWAY
        listener:
          filterChain:
            filter:
              name: envoy.filters.network.http_connection_manager
              subFilter:
                name: envoy.filters.http.router
      patch:
        operation: INSERT_BEFORE
        value:
          name: envoy.filters.http.lua.cors-internal
          typed_config:
            "@type": type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
            inlineCode: |
              local function is_internal_gift_id(origin)
                if not origin then return false end
                return string.match(origin, "^https://[a-z0-9-]+%.internal%.gift%.id$") ~= nil
              end

              function envoy_on_request(request_handle)
                local headers = request_handle:headers()
                local origin = headers:get("origin")
                local method = headers:get(":method")
                if origin and is_internal_gift_id(origin) then
                  request_handle:streamInfo():dynamicMetadata():set("cors_internal", "origin", origin)
                  if method == "OPTIONS" then
                    request_handle:streamInfo():dynamicMetadata():set("cors_internal", "responded", true)
                    request_handle:respond(
                      {
                        [":status"] = "204",
                        ["access-control-allow-origin"] = origin,
                        ["access-control-allow-methods"] = "GET, POST, PUT, PATCH, DELETE, OPTIONS",
                        ["access-control-allow-headers"] = "content-type, authorization, bridge-access-token, x-vnd-merchant-id, x-request-id",
                        ["access-control-allow-credentials"] = "true",
                        ["access-control-max-age"] = "86400"
                      },
                      ""
                    )
                  end
                end
              end

              function envoy_on_response(response_handle)
                local meta = response_handle:streamInfo():dynamicMetadata():get("cors_internal")
                if not meta or not meta["origin"] then return end
                if meta["responded"] then return end
                response_handle:headers():add("access-control-allow-origin", meta["origin"])
                response_handle:headers():add("access-control-allow-methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
                response_handle:headers():add("access-control-allow-headers", "content-type, authorization, bridge-access-token, x-vnd-merchant-id, x-request-id")
                response_handle:headers():add("access-control-allow-credentials", "true")
                response_handle:headers():add("access-control-max-age", "86400")
              end
```

## How it works

1. **`envoy_on_request`**: Checks `Origin` header against regex `^https://[a-z0-9-]+\.internal\.gift\.id$`. If match:
   - Stores origin in dynamic metadata for the response phase
   - For OPTIONS preflight: responds 204 immediately with CORS headers, sets `responded=true` flag
2. **`envoy_on_response`**: For non-OPTIONS requests (GET, POST, etc.), adds CORS headers to the upstream response. Skips if already responded in request phase.

The `responded` flag prevents duplicate headers — without it, both `on_request` (respond) and `on_response` (add headers) fire, producing doubled `access-control-allow-origin` values.

## Key decisions

- **Lua filter, not Envoy built-in CORS filter**: The built-in `envoy.filters.http.cors` filter with `allow_origin_regex_match` in RouteConfiguration patch does NOT work on Istio 1.28 — the `cors` field in `RouteConfiguration` is silently ignored (`unknown field "cors"` warning). Lua is the reliable approach.
- **`workloadSelector` labels**: Use `gateway.networking.k8s.io/gateway-name: external-gateway` — this is the label Istio gateway pods carry when created via Gateway API. Not `istio: ingressgateway` (that's for old-style Istio Gateway resources).
- **Regex, not wildcard**: Envoy CORS `allow_origin_regex_match` would work if the RouteConfiguration patch worked. Since it doesn't, Lua `string.match` with a Lua pattern is the regex engine.
- **Echo origin, not `*`**: Returns the actual requesting origin in `access-control-allow-origin` (not `*`). This is required when `allow-credentials: true`.

## Pitfalls

- **Built-in CORS filter + Lua = doubled headers**: If you insert both `envoy.filters.http.cors` (built-in) AND a Lua CORS filter, both add headers. Remove the built-in CORS filter — use only Lua. If a previous EnvoyFilter version added the built-in filter, restart the gateway pod (`kubectl rollout restart deployment external-gateway-istio -n istio-system`) to clear stale Envoy config.
- **HTTPRoute CORS filter must be removed**: If the HTTPRoute still has `type: CORS` filter, it adds its own headers on top of the EnvoyFilter. Remove the CORS filter from HTTPRoute spec (set `filters: []` or remove the filter entry) so the EnvoyFilter is the sole CORS authority.
- **Gateway pod restart needed after filter changes**: EnvoyFilter config changes are normally hot-reloaded, but if you're replacing a broken filter (e.g., removing built-in CORS filter that was causing duplicates), restart the gateway pod to ensure clean state.
- **`envoy_on_response` runs even after `respond()`**: Lua `respond()` in `on_request` sends the response but `on_response` still fires for that request. Use a metadata flag (`responded=true`) to skip header injection in `on_response` for preflight requests.
- **Non-matching origins get Envoy default CORS**: The built-in Envoy CORS filter (if previously inserted) may still add some headers for non-matching origins (e.g. `access-control-allow-methods: GET,HEAD,PUT,PATCH,POST,DELETE`). This is harmless — browsers ignore CORS headers without `access-control-allow-origin`.

## Verification

Test all three cases:

```bash
# 1. OPTIONS preflight from internal origin → 204 + clean CORS headers
curl -sk -X OPTIONS \
  -H "Origin: https://service-a.internal.gift.id" \
  -H "Access-Control-Request-Method: POST" \
  -D - -o /dev/null \
  https://service-b.internal.gift.id/api/path | grep -i "access-control\|HTTP"
# Expect: single access-control-allow-origin matching the Origin

# 2. GET from internal origin → 200 + CORS headers
curl -sk \
  -H "Origin: https://service-c.internal.gift.id" \
  -D - -o /dev/null \
  https://service-b.internal.gift.id/ | grep -i "access-control\|HTTP"
# Expect: single access-control-allow-origin matching the Origin

# 3. Non-internal origin → no internal CORS headers
curl -sk -X OPTIONS \
  -H "Origin: https://evil.example.com" \
  -H "Access-Control-Request-Method: GET" \
  -D - -o /dev/null \
  https://service-b.internal.gift.id/ | grep -i "access-control\|HTTP"
# Expect: no access-control-allow-origin from the Lua filter
```

Check for duplicate headers (sign of both built-in + Lua running):
```bash
# Count should be 1, not 2
curl -sk -X OPTIONS \
  -H "Origin: https://service-a.internal.gift.id" \
  -H "Access-Control-Request-Method: POST" \
  -D - -o /dev/null \
  https://service-b.internal.gift.id/ | grep -ic "^access-control-allow-origin:"
```

## Environment details (prd cluster)

- Gateway: `external-gateway` in `istio-system` namespace
- Gateway class: `istio` (Istio 1.28.3)
- Internal gift.id listener: `https-internal-gift-id` (hostname: `*.internal.gift.id`, port 443, HTTPS)
- Gateway pod label for workloadSelector: `gateway.networking.k8s.io/gateway-name: external-gateway`
- EnvoyFilter stored in manifest repo: `istio-system/cors-internal-gift-id.yaml`
