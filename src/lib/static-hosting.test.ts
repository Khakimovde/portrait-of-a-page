import { describe, expect, it } from "vitest";
// @ts-expect-error Build tooling is plain JavaScript and intentionally independent of app TypeScript.
import { buildTarget } from "../../scripts/build-target.mjs";
import { SUPPORT_URL } from "./lootzy-rules";

describe("hosting targets", () => {
  it("exports static files for a normal local npm build", () => {
    expect(buildTarget({})).toBe("static");
  });
  it("preserves the Cloud API for managed deployments", () => {
    expect(buildTarget({ LOVABLE_NITRO_PRESET: "cloudflare-module" })).toBe("cloud");
    expect(buildTarget({ LOVABLE_SANDBOX: "1" })).toBe("cloud");
  });
  it("opens the requested support account", () => {
    expect(SUPPORT_URL).toBe("https://t.me/Lootzy_help");
  });
});