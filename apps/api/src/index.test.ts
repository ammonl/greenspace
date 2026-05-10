import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { getGreenhouses, createRouter, handler, resolveDbConfig } from "./index.js";

const { secretsManagerSendMock } = vi.hoisted(() => ({
  secretsManagerSendMock: vi.fn(),
}));

vi.mock("./lib/session.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./lib/session.js")>();
  return {
    ...actual,
    deleteExpiredSessions: vi.fn().mockResolvedValue(5),
  };
});

vi.mock("./db/connection.js", () => ({
  createDatabase: vi.fn().mockReturnValue({}),
}));

vi.mock("@aws-sdk/client-secrets-manager", () => ({
  SecretsManagerClient: vi.fn().mockImplementation(() => ({
    send: secretsManagerSendMock,
  })),
  GetSecretValueCommand: vi.fn().mockImplementation((input: unknown) => input),
}));

describe("api", () => {
  it("returns greenhouse list", () => {
    expect(getGreenhouses()).toEqual(["Kronen", "Søen"]);
  });

  it("createRouter returns a router with routes registered", () => {
    const router = createRouter();
    expect(router).toBeDefined();
  });
});

describe("handler", () => {
  it("runs session cleanup for EventBridge scheduled events", async () => {
    const event = {
      source: "aws.events",
      "detail-type": "Scheduled Event",
      detail: {},
    };

    const result = await handler(event);
    expect(result.statusCode).toBe(200);
    const body = JSON.parse(result.body);
    expect(body.task).toBe("session-cleanup");
    expect(body.deletedSessions).toBe(5);
  });

  it("routes HTTP events normally", async () => {
    const event = {
      httpMethod: "GET",
      path: "/health",
      headers: {},
      body: null,
    };

    const result = await handler(event);
    expect(result.statusCode).toBe(200);
  });
});

describe("resolveDbConfig", () => {
  const originalEnv = { ...process.env };

  beforeEach(() => {
    secretsManagerSendMock.mockReset();
  });

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  it("loads connection params from the shared-db secret when DB_SECRET_ID is set", async () => {
    secretsManagerSendMock.mockResolvedValueOnce({
      SecretString: JSON.stringify({
        host: "shared-db.example.com",
        port: 5432,
        dbname: "greenspace_staging",
        username: "greenspace_staging_app",
        password: "secret-password",
      }),
    });
    process.env["DB_SECRET_ID"] = "rds/shared/greenspace_staging";
    process.env["DB_SSL"] = "true";

    const config = await resolveDbConfig();

    expect(secretsManagerSendMock).toHaveBeenCalledOnce();
    expect(secretsManagerSendMock).toHaveBeenCalledWith({
      SecretId: "rds/shared/greenspace_staging",
    });
    expect(config).toEqual({
      host: "shared-db.example.com",
      port: 5432,
      database: "greenspace_staging",
      user: "greenspace_staging_app",
      password: "secret-password",
      ssl: true,
    });
  });

  it("coerces a string port from the secret payload", async () => {
    secretsManagerSendMock.mockResolvedValueOnce({
      SecretString: JSON.stringify({
        host: "shared-db.example.com",
        port: "5432",
        dbname: "greenspace_staging",
        username: "greenspace_staging_app",
        password: "secret-password",
      }),
    });
    process.env["DB_SECRET_ID"] = "rds/shared/greenspace_staging";
    delete process.env["DB_SSL"];

    const config = await resolveDbConfig();

    expect(config.port).toBe(5432);
    expect(config.ssl).toBe(false);
  });

  it("throws when the shared-db secret is missing required fields", async () => {
    secretsManagerSendMock.mockResolvedValueOnce({
      SecretString: JSON.stringify({ host: "shared-db.example.com" }),
    });
    process.env["DB_SECRET_ID"] = "rds/shared/greenspace_staging";

    await expect(resolveDbConfig()).rejects.toThrow(/missing required fields/);
  });

  it("throws when the shared-db secret has a non-numeric port", async () => {
    secretsManagerSendMock.mockResolvedValueOnce({
      SecretString: JSON.stringify({
        host: "shared-db.example.com",
        port: "abc",
        dbname: "greenspace_staging",
        username: "greenspace_staging_app",
        password: "secret-password",
      }),
    });
    process.env["DB_SECRET_ID"] = "rds/shared/greenspace_staging";

    await expect(resolveDbConfig()).rejects.toThrow(/non-numeric port/);
  });

  it("falls back to individual env vars when DB_SECRET_ID is not set", async () => {
    delete process.env["DB_SECRET_ID"];
    process.env["DB_HOST"] = "localhost";
    process.env["DB_PORT"] = "5433";
    process.env["DB_NAME"] = "greenspace_local";
    process.env["DB_USER"] = "dev";
    process.env["DB_PASSWORD"] = "localpass";
    delete process.env["DB_SSL"];

    const config = await resolveDbConfig();

    expect(secretsManagerSendMock).not.toHaveBeenCalled();
    expect(config).toEqual({
      host: "localhost",
      port: 5433,
      database: "greenspace_local",
      user: "dev",
      password: "localpass",
      ssl: false,
    });
  });
});
