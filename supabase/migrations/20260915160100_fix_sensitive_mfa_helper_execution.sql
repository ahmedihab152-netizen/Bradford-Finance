-- Sensitive SECURITY INVOKER workflows must be able to run the MFA assertion.
-- The helper grants no capability; it only raises unless the configured AAL is met.
grant usage on schema private to authenticated;
grant execute on function private.require_admin_mfa_if_enabled() to authenticated;
