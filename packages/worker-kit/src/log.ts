/** Every log line names the request it belongs to; other fields are free-form, keys in snake_case. */
export type LogFields = { request_id: string } & Record<string, unknown>;

const line = (message: string, fields: LogFields) => JSON.stringify({ message, ...fields });

/**
 * Single-line JSON logs for Workers Logs (docs/workers.md, Conventions). `error` for unexpected
 * failures, `warn` for upstream failures the request survives, `info` for audit trails.
 * Tokens, keys, and sync record bodies never go in `fields`.
 */
export const log = {
  // oxlint-disable-next-line no-console -- the one place Workers write to the console
  error: (message: string, fields: LogFields) => console.error(line(message, fields)),
  // oxlint-disable-next-line no-console -- the one place Workers write to the console
  warn: (message: string, fields: LogFields) => console.warn(line(message, fields)),
  // oxlint-disable-next-line no-console -- the one place Workers write to the console
  info: (message: string, fields: LogFields) => console.log(line(message, fields)),
};
