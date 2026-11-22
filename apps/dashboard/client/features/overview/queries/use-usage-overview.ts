import { queryOptions, useQuery } from "@tanstack/react-query";
import { getUsageOverview } from "../api/overview-api";
import { overviewKeys } from "./query-keys";

export const usageOverviewQuery = queryOptions({
  queryKey: overviewKeys.usage(),
  queryFn: getUsageOverview,
});

export const useUsageOverview = () => useQuery(usageOverviewQuery);
