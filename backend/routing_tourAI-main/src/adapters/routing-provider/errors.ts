export type RoutingProviderErrorCode = 'timeout' | 'request_failed' | 'invalid_response';

/**
 * Thrown by any RoutingProviderAdapter implementation on failure. Kept
 * as a single shared type (not per-provider) so Orchestration can catch
 * one error class regardless of which provider is active for a city
 * (Section 2's provider-swap point).
 */
export class RoutingProviderError extends Error {
  readonly code: RoutingProviderErrorCode;
  readonly provider: string;

  constructor(
    message: string,
    code: RoutingProviderErrorCode,
    provider: string,
    options?: ErrorOptions,
  ) {
    super(message, options);
    this.name = 'RoutingProviderError';
    this.code = code;
    this.provider = provider;
  }
}
