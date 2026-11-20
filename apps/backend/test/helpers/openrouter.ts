import { fakeOpenRouter as fake } from "@luma/core/testing/openrouter";
import { network } from "../setup";

export const fakeOpenRouter = (options?: Parameters<typeof fake>[1]) => fake(network, options);
