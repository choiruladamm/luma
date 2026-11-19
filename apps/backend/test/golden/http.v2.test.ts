import { expect, it } from "vitest";
import { records } from "./scenario";

// A file of its own: D1 storage is shared within a file and the scenario starts from an empty database.
it("records every route on /v2", async () => {
  await expect(await records("v2")).toMatchFileSnapshot("./http.v2.golden.json");
});
