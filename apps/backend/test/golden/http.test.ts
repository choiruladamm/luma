import { expect, it } from "vitest";
import { records } from "./scenario";

it("records every route on /v1", async () => {
  await expect(await records("v1")).toMatchFileSnapshot("./http.golden.json");
});
