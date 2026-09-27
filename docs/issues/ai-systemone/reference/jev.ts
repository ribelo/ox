/** Thin, fail-closed adapter for the pinned OpenRouter System One JEV model. */

export const JEV_ENDPOINT = "https://openrouter.ai/api/v1/systemone" as const;
export const JEV_MODEL = "typesafe/jev-1.13-20260917" as const;

const MAX_REQUEST_BYTES = 4 * 1024 * 1024;
const MAX_RESPONSE_BYTES = 1 * 1024 * 1024;
const MAX_ATTEMPTS = 2;
const TRANSPORT_TIMEOUT_MS = 10_000;
const INITIAL_RETRY_DELAY_MS = 100;
/** JSON the System One API accepts and returns. */
export type JsonValue =
  | null
  | boolean
  | number
  | string
  | readonly JsonValue[]
  | { readonly [key: string]: JsonValue };

/** One option of a choice question: the selected key and its distribution. */
export interface ChoiceAnswer {
  type: "choice";
  choice: string;
  probabilities: Record<string, number>;
  confidence: number;
}

/**
 * One score answer: a position on the question's levels, optionally explained
 * by a legend keyed by the level index the API uses for this question.
 * `score` may fall between two levels.
 */
export interface ScoreAnswer {
  type: "score";
  score: number;
  legend?: Record<string, string>;
  probabilities: Record<string, number>;
  confidence: number;
}

/** Any answer this client accepts. */
export type JevAnswer = ChoiceAnswer | ScoreAnswer;

export interface ChoiceQuestion {
  type: "choice";
  instructions: JsonValue;
  criteria: Record<string, string | null>;
}

/** A score question: an ordered list of levels, judged one level at a time. */
export interface ScoreQuestion {
  type: "score";
  instructions: JsonValue;
  criteria: readonly string[];
}

/** Any question type this client is allowed to send. */
export type JevQuestion = ChoiceQuestion | ScoreQuestion;

export interface JevResponse {
  model: typeof JEV_MODEL;
  answers: Record<string, JevAnswer>;
  usage: { input_tokens: number; output_tokens: number; cost: number };
  id?: string;
  provider?: string;
}

export interface JevEvaluateOptions {
  readonly signal?: AbortSignal;
  readonly deadlineAt?: number;
}

export interface JevEvaluateInput {
  readonly state: JsonValue;
  readonly questions: Record<string, JevQuestion>;
}

export interface JevClient {
  evaluate(input: JevEvaluateInput, options?: JevEvaluateOptions): Promise<JevResponse>;
}

export type JevFailureCode =
  | "UNAVAILABLE"
  | "TIMEOUT"
  | "INVALID_RESPONSE"
  | "INPUT_TOO_LARGE"
  | "AUTHENTICATION";

const ERROR_MESSAGES: Record<JevFailureCode, string> = {
  UNAVAILABLE: "JEV service is unavailable.",
  TIMEOUT: "JEV evaluation timed out.",
  INVALID_RESPONSE: "JEV response is invalid.",
  INPUT_TOO_LARGE: "JEV request is too large.",
  AUTHENTICATION: "JEV authentication failed.",
};

/** The one error type this adapter throws; callers map `code` to a decision. */
export class JevError extends Error {
  readonly code: JevFailureCode;
  readonly retryable: boolean;

  constructor(code: JevFailureCode, retryable: boolean, message: string = ERROR_MESSAGES[code]) {
    super(message);
    this.name = "JevError";
    this.code = code;
    this.retryable = retryable;
    Object.setPrototypeOf(this, new.target.prototype);
  }
}

/** Fetch seam so tests and the evaluation CLI can substitute a transport. */
export type JevFetch = typeof globalThis.fetch;

export interface JevClientOptions {
  readonly getApiKey: () => string | undefined;
  readonly fetch?: JevFetch;
  readonly now?: () => number;
  readonly sleep?: (milliseconds: number) => Promise<void>;
}

const isRecord = (value: unknown): value is Record<string, unknown> => {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value) as unknown;
  return prototype === Object.prototype || prototype === null;
};

const hasOwn = (value: Record<string, unknown>, key: string): boolean =>
  Object.prototype.hasOwnProperty.call(value, key);

const invalidRequest = (): JevError => new JevError("INVALID_RESPONSE", false, "JEV request is invalid.");
const invalidResponse = (): JevError => new JevError("INVALID_RESPONSE", false);
const unavailable = (): JevError => new JevError("UNAVAILABLE", true);
const nonRetryableUnavailable = (): JevError => new JevError("UNAVAILABLE", false);
const timeout = (): JevError => new JevError("TIMEOUT", true);
const authentication = (): JevError => new JevError("AUTHENTICATION", false);
const inputTooLarge = (): JevError => new JevError("INPUT_TOO_LARGE", false);

const abortError = (): DOMException => new DOMException("The operation was aborted.", "AbortError");

const utf8ByteLength = (value: string): number => new TextEncoder().encode(value).byteLength;

const serializeRequest = (
  state: JsonValue,
  questions: Record<string, JevQuestion>,
): { body: string; questions: Record<string, JevQuestion> } => {
  const body = JSON.stringify({ model: JEV_MODEL, state, questions });
  if (utf8ByteLength(body) > MAX_REQUEST_BYTES) throw inputTooLarge();
  return { body, questions };
};

const parseResponse = (serialized: string): JevResponse => {
  let value: unknown;
  try {
    value = JSON.parse(serialized);
  } catch {
    throw invalidResponse();
  }
  if (!isRecord(value) || !isRecord(value.answers)) throw invalidResponse();
  return value as unknown as JevResponse;
};

const cancelResponseBody = (response: Response): void => {
  const body = response.body;
  if (!body) return;
  try {
    void Promise.resolve(body.cancel()).catch(() => undefined);
  } catch {
    // Body cleanup cannot replace the primary typed result.
  }
};

const readResponseBody = async (response: Response, signal: AbortSignal): Promise<string> => {
  const contentLength = response.headers.get("content-length");
  if (contentLength !== null) {
    const parsedLength = Number(contentLength);
    if (Number.isFinite(parsedLength) && parsedLength > MAX_RESPONSE_BYTES) {
      cancelResponseBody(response);
      throw invalidResponse();
    }
  }

  const race = <T>(operation: Promise<T>): Promise<T> => raceWithSignal(operation, signal);

  if (response.body) {
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let total = 0;
    try {
      while (true) {
        const result = await race(reader.read());
        if (result.done) break;
        const chunk = result.value;
        if (!(chunk instanceof Uint8Array)) throw invalidResponse();
        total += chunk.byteLength;
        if (total > MAX_RESPONSE_BYTES) throw invalidResponse();
        chunks.push(chunk);
      }
    } catch (error) {
      try {
        void Promise.resolve(reader.cancel()).catch(() => undefined);
      } catch {
        // Best-effort cancellation only.
      }
      if (error instanceof JevError) throw error;
      throw error instanceof DOMException && error.name === "AbortError" ? abortError() : invalidResponse();
    } finally {
      try {
        reader.releaseLock();
      } catch {
        // Standard Response readers support releaseLock.
      }
    }

    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    try {
      return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    } catch {
      throw invalidResponse();
    }
  }

  try {
    const text = await race(Promise.resolve(response.text()));
    if (typeof text !== "string" || utf8ByteLength(text) > MAX_RESPONSE_BYTES) throw invalidResponse();
    return text;
  } catch (error) {
    if (error instanceof JevError) throw error;
    throw error instanceof DOMException && error.name === "AbortError" ? abortError() : invalidResponse();
  }
};

const retryAfterMilliseconds = (response: Response, now: number, attempt: number): number => {
  const value = response.headers.get("retry-after");
  if (value !== null) {
    const seconds = Number(value.trim());
    if (Number.isFinite(seconds) && seconds >= 0) return seconds * 1_000;
    const date = Date.parse(value);
    if (Number.isFinite(date)) return Math.max(0, date - now);
  }
  return INITIAL_RETRY_DELAY_MS * 2 ** attempt;
};

const isContextOverflowBody = (serialized: string | undefined): boolean => {
  if (serialized === undefined) return false;
  let value: unknown;
  try {
    value = JSON.parse(serialized);
  } catch {
    return false;
  }
  if (!isRecord(value)) return false;

  const candidates: unknown[] = [value];
  const error = value.error;
  if (isRecord(error)) {
    candidates.push(error);
    if (isRecord(error.metadata)) candidates.push(error.metadata);
  }
  return candidates.some((candidate) => {
    if (!isRecord(candidate)) return false;
    const code = typeof candidate.code === "string" ? candidate.code : "";
    const message = typeof candidate.message === "string" ? candidate.message : "";
    const text = (code + " " + message).toLowerCase();
    return (
      /context[\s_-]*length/.test(text) ||
      /context[\s_-]*window/.test(text) ||
      /too[\s_-]*many[\s_-]*tokens/.test(text) ||
      /maximum[\s_-]+context/.test(text) ||
      /prompt[\s_-]+(?:is[\s_-]+)?too[\s_-]+long/.test(text)
    );
  });
};

const discardAnd = (response: Response, error: JevError): never => {
  cancelResponseBody(response);
  throw error;
};

/** How this adapter waits between retries; injectable so tests never sleep. */
type JevSleep = (milliseconds: number, signal?: AbortSignal) => Promise<void>;

/** A serialized request body plus the questions the response must answer. */
type SerializedRequest = { body: string; questions: Record<string, JevQuestion> };

type Operation = {
  signal: AbortSignal;
  callerSignal: AbortSignal | undefined;
  deadlineAt: number;
  now: () => number;
};

const assertActive = (operation: Operation): void => {
  if (operation.callerSignal?.aborted) throw abortError();
  if (operation.signal.aborted || operation.now() >= operation.deadlineAt) throw timeout();
};

const raceWithSignal = async <T>(operation: Promise<T>, signal: AbortSignal): Promise<T> => {
  if (signal.aborted) throw abortError();
  let onAbort: (() => void) | undefined;
  const abortPromise = new Promise<never>((_resolve, reject) => {
    onAbort = () => reject(abortError());
    signal.addEventListener("abort", onAbort, { once: true });
  });
  try {
    return await Promise.race([operation, abortPromise]);
  } finally {
    if (onAbort !== undefined) signal.removeEventListener("abort", onAbort);
  }
};

type AttemptResult =
  | { kind: "response"; response: Response; body?: string }
  | { kind: "transport" }
  | { kind: "attempt-timeout" };

const performAttempt = async (
  fetchImpl: JevFetch,
  requestBody: string,
  apiKey: string,
  operation: Operation,
): Promise<AttemptResult> => {
  assertActive(operation);
  const attemptController = new AbortController();
  const remaining = operation.deadlineAt - operation.now();
  const timer = setTimeout(
    () => attemptController.abort(),
    Math.min(TRANSPORT_TIMEOUT_MS, remaining),
  );
  const signal = AbortSignal.any([operation.signal, attemptController.signal]);
  let response: Response | undefined;

  try {
    const fetchPromise = Promise.resolve().then(() =>
      fetchImpl(JEV_ENDPOINT, {
        method: "POST",
        headers: {
          Authorization: "Bearer " + apiKey,
          "Content-Type": "application/json",
        },
        body: requestBody,
        redirect: "error",
        signal,
      }),
    );
    void fetchPromise.then((lateResponse) => {
      if (operation.signal.aborted || attemptController.signal.aborted) cancelResponseBody(lateResponse);
    }, () => undefined);
    response = await raceWithSignal(fetchPromise, signal);
    if (operation.callerSignal?.aborted) throw abortError();
    if (operation.signal.aborted || operation.now() >= operation.deadlineAt) throw timeout();
    if (response.redirected || (response.status >= 300 && response.status < 400)) {
      return discardAnd(response, invalidResponse());
    }

    if (response.status >= 200 && response.status < 300) {
      const body = await readResponseBody(response, signal);
      assertActive(operation);
      return { kind: "response", response, body };
    }
    if (response.status === 400 || response.status === 422) {
      const body = await readResponseBody(response, signal);
      assertActive(operation);
      return { kind: "response", response, body };
    }
    return { kind: "response", response };
  } catch (error) {
    if (response) cancelResponseBody(response);
    if (operation.callerSignal?.aborted) throw abortError();
    if (operation.signal.aborted || operation.now() >= operation.deadlineAt) throw timeout();
    if (attemptController.signal.aborted) return { kind: "attempt-timeout" };
    if (error instanceof JevError && response !== undefined) throw error;
    if (error instanceof DOMException && error.name === "AbortError") return { kind: "transport" };
    return { kind: "transport" };
  } finally {
    clearTimeout(timer);
  }
};

const waitForRetry = async (
  milliseconds: number,
  operation: Operation,
  sleep: JevSleep,
): Promise<void> => {
  assertActive(operation);
  const remaining = operation.deadlineAt - operation.now();
  if (!Number.isFinite(remaining) || milliseconds >= remaining) throw timeout();
  try {
    await raceWithSignal(sleep(milliseconds, operation.signal), operation.signal);
  } catch (error) {
    if (operation.callerSignal?.aborted) throw abortError();
    if (operation.signal.aborted || operation.now() >= operation.deadlineAt) throw timeout();
    throw unavailable();
  }
  assertActive(operation);
};

const evaluateWithOperation = async (
  fetchImpl: JevFetch,
  sleep: JevSleep,
  apiKey: string,
  request: SerializedRequest,
  operation: Operation,
): Promise<JevResponse> => {
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt += 1) {
    assertActive(operation);
    const result = await performAttempt(fetchImpl, request.body, apiKey, operation);
    if (result.kind === "attempt-timeout") {
      if (attempt + 1 >= MAX_ATTEMPTS) throw timeout();
      await waitForRetry(INITIAL_RETRY_DELAY_MS * 2 ** attempt, operation, sleep);
      continue;
    }
    if (result.kind === "transport") {
      if (attempt + 1 >= MAX_ATTEMPTS) throw unavailable();
      await waitForRetry(INITIAL_RETRY_DELAY_MS * 2 ** attempt, operation, sleep);
      continue;
    }

    const { response, body } = result;
    if (response.status === 401) return discardAnd(response, authentication());
    if (
      response.status === 413 ||
      ((response.status === 400 || response.status === 422) && isContextOverflowBody(body))
    ) {
      return discardAnd(response, inputTooLarge());
    }
    if (response.status === 429 || response.status === 529) {
      cancelResponseBody(response);
      if (attempt + 1 >= MAX_ATTEMPTS) throw unavailable();
      await waitForRetry(retryAfterMilliseconds(response, operation.now(), attempt), operation, sleep);
      continue;
    }
    if (response.status < 200 || response.status >= 300) {
      return discardAnd(
        response,
        response.status >= 400 && response.status < 500
          ? invalidResponse()
          : nonRetryableUnavailable(),
      );
    }
    if (body === undefined) return discardAnd(response, invalidResponse());
    return parseResponse(body);
  }
  throw unavailable();
};

const defaultSleep: JevSleep = (milliseconds, signal) =>
  new Promise<void>((resolve, reject) => {
    if (signal?.aborted) {
      reject(abortError());
      return;
    }
    let timer: ReturnType<typeof setTimeout> | undefined;
    const onAbort = () => {
      if (timer !== undefined) clearTimeout(timer);
      signal?.removeEventListener("abort", onAbort);
      reject(abortError());
    };
    timer = setTimeout(() => {
      signal?.removeEventListener("abort", onAbort);
      resolve();
    }, milliseconds);
    signal?.addEventListener("abort", onAbort, { once: true });
  });

export const createJevClient = (options: JevClientOptions): JevClient => {
  const now = options.now ?? Date.now;
  const sleep = options.sleep ?? defaultSleep;
  const fetchImpl = options.fetch ?? globalThis.fetch;

  return {
    async evaluate(input, evaluateOptions): Promise<JevResponse> {
      const callerSignal = evaluateOptions?.signal;
      const deadlineAt = evaluateOptions?.deadlineAt;
      const initialNow = now();
      if (callerSignal?.aborted) throw abortError();
      if (deadlineAt === undefined || !Number.isFinite(deadlineAt) || initialNow >= deadlineAt) {
        throw timeout();
      }
      if (typeof fetchImpl !== "function") throw nonRetryableUnavailable();

      const controller = new AbortController();
      const operation: Operation = { signal: controller.signal, callerSignal, deadlineAt, now };
      const onCallerAbort = () => controller.abort();
      callerSignal?.addEventListener("abort", onCallerAbort, { once: true });
      const deadlineTimer = setTimeout(() => controller.abort(), Math.min(deadlineAt - initialNow, 2_147_483_647));
      try {
        const request = serializeRequest(input?.state, input?.questions);
        assertActive(operation);
        let apiKey: unknown;
        try {
          apiKey = options.getApiKey();
        } catch {
          throw authentication();
        }
        if (typeof apiKey !== "string" || apiKey.trim().length === 0) throw authentication();
        try {
          const evaluation = evaluateWithOperation(fetchImpl, sleep, apiKey, request, operation);
          return await raceWithSignal(evaluation, operation.signal);
        } catch (error) {
          if (callerSignal?.aborted) throw abortError();
          if (operation.signal.aborted || now() >= deadlineAt) throw timeout();
          throw error;
        }
      } finally {
        clearTimeout(deadlineTimer);
        callerSignal?.removeEventListener("abort", onCallerAbort);
      }
    },
  };
};
