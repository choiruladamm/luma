import { queryOptions, useQuery } from "@tanstack/react-query";
import { getOverview } from "../api/overview-api";
import { overviewKeys } from "./query-keys";

export const overviewQuery = queryOptions({ queryKey: overviewKeys.all, queryFn: getOverview });

export const useOverview = () => useQuery(overviewQuery);
